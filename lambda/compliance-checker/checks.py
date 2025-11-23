#!/usr/bin/env python3
"""
Compliance Checks Module

Implements all compliance validation rules for RDS instances.
"""

import os
import sys
from typing import Dict, List, Any, Optional
from datetime import datetime

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger
from shared.aws_clients import AWSClients

logger = get_logger(__name__)


class ComplianceChecker:
    """Performs compliance checks on RDS instances."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize compliance checker.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.rds_clients = {}  # Cache RDS clients by region
    
    def check_instance_compliance(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Run all compliance checks on an RDS instance.
        
        Args:
            instance: RDS instance metadata
            
        Returns:
            list: List of compliance violations
        """
        violations = []
        
        # Basic compliance checks (Task 5)
        violations.extend(self._check_backup_retention(instance))
        violations.extend(self._check_storage_encryption(instance))
        violations.extend(self._check_engine_version(instance))
        
        # Additional compliance checks (Task 5.1)
        violations.extend(self._check_multi_az(instance))
        violations.extend(self._check_deletion_protection(instance))
        violations.extend(self._check_pending_maintenance(instance))
        
        return violations
    
    def _check_backup_retention(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check if automated backups are enabled with retention >= 7 days.
        
        REQ-6.1: Verify automated backups enabled with retention >= 7 days
        """
        violations = []
        backup_retention = instance.get('backup_retention_period', 0)
        
        if backup_retention < 7:
            violations.append({
                'instance_id': instance['instance_id'],
                'check_type': 'backup_retention',
                'severity': 'Critical',
                'message': f"Backup retention is {backup_retention} days (minimum: 7 days)",
                'current_value': backup_retention,
                'required_value': 7,
                'remediation': f"Modify DB instance to set backup retention period to at least 7 days: aws rds modify-db-instance --db-instance-identifier {instance['instance_id']} --backup-retention-period 7"
            })
        
        return violations
    
    def _check_storage_encryption(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check if storage encryption is enabled for all environments.
        
        REQ-6.2: Validate storage encryption enabled for all RDS instances
        """
        violations = []
        storage_encrypted = instance.get('storage_encrypted', False)
        
        if not storage_encrypted:
            violations.append({
                'instance_id': instance['instance_id'],
                'check_type': 'storage_encryption',
                'severity': 'Critical',
                'message': "Storage encryption is not enabled",
                'current_value': False,
                'required_value': True,
                'remediation': "Storage encryption cannot be enabled on existing instances. Create a snapshot, copy it with encryption enabled, and restore from the encrypted snapshot."
            })
        
        return violations
    
    def _check_engine_version(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check database engine version compliance.
        
        REQ-6.3: PostgreSQL must be at (latest - 1) minor version or newer
        Oracle/MS-SQL: Informational only, no violations
        """
        violations = []
        engine = instance.get('engine', '').lower()
        current_version = instance.get('engine_version', '')
        
        # Only enforce for PostgreSQL
        if engine == 'postgres':
            # Get latest available version for this engine
            latest_version = self._get_latest_engine_version(
                instance.get('region'),
                engine,
                current_version
            )
            
            if latest_version and not self._is_version_compliant(current_version, latest_version):
                # Calculate how many versions behind
                versions_behind = self._calculate_versions_behind(current_version, latest_version)
                
                if versions_behind > 2:
                    severity = 'Critical'
                elif versions_behind > 1:
                    severity = 'High'
                else:
                    severity = 'Medium'
                
                violations.append({
                    'instance_id': instance['instance_id'],
                    'check_type': 'engine_version',
                    'severity': severity,
                    'message': f"PostgreSQL version {current_version} is {versions_behind} minor versions behind latest ({latest_version})",
                    'current_value': current_version,
                    'required_value': f"{latest_version} or newer",
                    'remediation': f"Upgrade to a newer PostgreSQL version. Latest available: {latest_version}"
                })
        
        # For Oracle and MS-SQL, just log informational data (no violations)
        elif engine in ['oracle-se2', 'oracle-ee', 'sqlserver-se', 'sqlserver-ee', 'sqlserver-ex', 'sqlserver-web']:
            logger.info(f"{instance['instance_id']}: {engine} version {current_version} (informational only)")
        
        return violations
    
    def _check_multi_az(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check if Multi-AZ is enabled for production instances.
        
        REQ-6.3: Multi-AZ required for production
        """
        violations = []
        multi_az = instance.get('multi_az', False)
        tags = instance.get('tags', {})
        environment = tags.get('Environment', '').lower()
        
        # Only enforce for production
        if environment == 'production' and not multi_az:
            violations.append({
                'instance_id': instance['instance_id'],
                'check_type': 'multi_az',
                'severity': 'High',
                'message': "Multi-AZ is not enabled for production instance",
                'current_value': False,
                'required_value': True,
                'remediation': f"Enable Multi-AZ: aws rds modify-db-instance --db-instance-identifier {instance['instance_id']} --multi-az --apply-immediately"
            })
        
        return violations
    
    def _check_deletion_protection(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check if deletion protection is enabled (except POC/Sandbox).
        
        REQ-6.4: Deletion protection required except for POC/Sandbox
        """
        violations = []
        deletion_protection = instance.get('deletion_protection', False)
        tags = instance.get('tags', {})
        environment = tags.get('Environment', '').lower()
        
        # Skip check for POC and Sandbox
        if environment in ['poc', 'sandbox']:
            return violations
        
        if not deletion_protection:
            violations.append({
                'instance_id': instance['instance_id'],
                'check_type': 'deletion_protection',
                'severity': 'High',
                'message': f"Deletion protection is not enabled for {environment} instance",
                'current_value': False,
                'required_value': True,
                'remediation': f"Enable deletion protection: aws rds modify-db-instance --db-instance-identifier {instance['instance_id']} --deletion-protection --no-apply-immediately"
            })
        
        return violations
    
    def _check_pending_maintenance(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check for pending maintenance actions.
        
        REQ-6.4: Alert if maintenance window is within 7 days
        """
        violations = []
        
        # Get pending maintenance from RDS API
        pending_maintenance = self._get_pending_maintenance(
            instance.get('region'),
            instance['instance_id']
        )
        
        if pending_maintenance:
            # Check if any maintenance is within 7 days
            for maintenance in pending_maintenance:
                action = maintenance.get('Action', 'Unknown')
                auto_applied_date = maintenance.get('AutoAppliedAfterDate')
                
                if auto_applied_date:
                    # Parse date and check if within 7 days
                    try:
                        maintenance_date = datetime.fromisoformat(auto_applied_date.replace('Z', '+00:00'))
                        days_until = (maintenance_date - datetime.now(maintenance_date.tzinfo)).days
                        
                        if days_until <= 7:
                            violations.append({
                                'instance_id': instance['instance_id'],
                                'check_type': 'pending_maintenance',
                                'severity': 'Medium',
                                'message': f"Pending maintenance action '{action}' scheduled in {days_until} days",
                                'current_value': f"{action} on {auto_applied_date}",
                                'required_value': 'No pending maintenance',
                                'remediation': f"Review and schedule maintenance during approved window: aws rds describe-pending-maintenance-actions --resource-identifier arn:aws:rds:{instance.get('region')}:*:db:{instance['instance_id']}"
                            })
                    except Exception as e:
                        logger.warn(f"Failed to parse maintenance date for {instance['instance_id']}: {str(e)}")
        
        return violations
    
    def _get_latest_engine_version(
        self,
        region: str,
        engine: str,
        current_version: str
    ) -> Optional[str]:
        """
        Get the latest available engine version from RDS API.
        
        Args:
            region: AWS region
            engine: Database engine
            current_version: Current engine version
            
        Returns:
            str: Latest available version or None
        """
        try:
            rds = self._get_rds_client(region)
            
            # Get major version from current version (e.g., "15" from "15.4")
            major_version = current_version.split('.')[0]
            
            response = rds.describe_db_engine_versions(
                Engine=engine,
                EngineVersion=f"{major_version}",
                DefaultOnly=False
            )
            
            versions = response.get('DBEngineVersions', [])
            if versions:
                # Get the latest version in this major version family
                latest = max(versions, key=lambda v: v['EngineVersion'])
                return latest['EngineVersion']
            
            return None
            
        except Exception as e:
            logger.warn(f"Failed to get latest engine version for {engine}: {str(e)}")
            return None
    
    def _get_pending_maintenance(
        self,
        region: str,
        instance_id: str
    ) -> List[Dict[str, Any]]:
        """
        Get pending maintenance actions for an instance.
        
        Args:
            region: AWS region
            instance_id: RDS instance identifier
            
        Returns:
            list: Pending maintenance actions
        """
        try:
            rds = self._get_rds_client(region)
            
            response = rds.describe_pending_maintenance_actions(
                Filters=[
                    {
                        'Name': 'db-instance-id',
                        'Values': [instance_id]
                    }
                ]
            )
            
            actions = response.get('PendingMaintenanceActions', [])
            if actions:
                return actions[0].get('PendingMaintenanceActionDetails', [])
            
            return []
            
        except Exception as e:
            logger.warn(f"Failed to get pending maintenance for {instance_id}: {str(e)}")
            return []
    
    def _get_rds_client(self, region: str):
        """Get or create RDS client for region."""
        if region not in self.rds_clients:
            self.rds_clients[region] = AWSClients.get_rds_client(region)
        return self.rds_clients[region]
    
    def _is_version_compliant(self, current: str, latest: str) -> bool:
        """
        Check if current version is compliant (within 1 minor version of latest).
        
        Args:
            current: Current version (e.g., "15.4")
            latest: Latest version (e.g., "15.5")
            
        Returns:
            bool: True if compliant
        """
        try:
            current_parts = [int(x) for x in current.split('.')]
            latest_parts = [int(x) for x in latest.split('.')]
            
            # Same major version
            if current_parts[0] != latest_parts[0]:
                return False
            
            # Within 1 minor version
            minor_diff = latest_parts[1] - current_parts[1]
            return minor_diff <= 1
            
        except Exception as e:
            logger.warn(f"Failed to compare versions {current} and {latest}: {str(e)}")
            return True  # Assume compliant if we can't parse
    
    def _calculate_versions_behind(self, current: str, latest: str) -> int:
        """
        Calculate how many minor versions behind current is from latest.
        
        Args:
            current: Current version
            latest: Latest version
            
        Returns:
            int: Number of versions behind
        """
        try:
            current_parts = [int(x) for x in current.split('.')]
            latest_parts = [int(x) for x in latest.split('.')]
            
            return latest_parts[1] - current_parts[1]
            
        except Exception:
            return 0
