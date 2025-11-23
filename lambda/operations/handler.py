#!/usr/bin/env python3
"""
RDS Operations Service Handler

Provides self-service operations for non-production RDS instances.
Supports snapshot creation, instance reboot, and backup window modification.

Requirements: REQ-7 (Self-Service Operations for Non-Production)
"""

import json
import os
import time
import boto3
from datetime import datetime
from typing import Dict, Any, Optional
from decimal import Decimal

from shared import StructuredLogger
from shared import AWSClients
from shared import Config
from shared.environment_classifier import EnvironmentClassifier

logger = StructuredLogger("operations")


class OperationsHandler:
    """Handle self-service RDS operations."""
    
    ALLOWED_OPERATIONS = ['create_snapshot', 'reboot', 'reboot_instance', 'modify_backup_window']
    OPERATION_TIMEOUT = 300  # 5 minutes
    POLL_INTERVAL = 30  # 30 seconds
    
    def __init__(self):
        """Initialize operations handler."""
        self.config = Config.load()
        self.dynamodb = AWSClients.get_dynamodb_resource()
        self.audit_table = os.environ.get('AUDIT_LOG_TABLE', 'audit-log-prod')
        self.inventory_table = os.environ.get('INVENTORY_TABLE', 'rds-inventory-prod')
        
        # Initialize environment classifier
        env_config = self.config.get('environment_classification', {})
        self.classifier = EnvironmentClassifier(env_config)
    
    def handle_request(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle operations request from API Gateway.
        
        Args:
            event: API Gateway event
            
        Returns:
            dict: Response with operation result
        """
        try:
            # Parse request body
            body = json.loads(event.get('body', '{}'))
            
            # Support both 'operation' and 'operation_type' for backwards compatibility
            operation = body.get('operation') or body.get('operation_type')
            instance_id = body.get('instance_id')
            parameters = body.get('parameters', {})
            user_identity = event.get('requestContext', {}).get('identity', {})
            
            # Validate request
            validation_result = self._validate_request(
                operation, instance_id, parameters, user_identity
            )
            
            if not validation_result['valid']:
                return self._error_response(400, validation_result['error'])
            
            # Get instance details
            instance = self._get_instance(instance_id)
            if not instance:
                return self._error_response(404, f"Instance {instance_id} not found")
            
            # Check environment (must be non-production)
            environment = self.classifier.get_environment(instance)
            if environment == 'production':
                return self._error_response(
                    403,
                    "Operations not allowed on production instances. "
                    "Please create a CloudOps request."
                )
            
            # Execute operation
            logger.info(f"Executing {operation} on {instance_id}")
            result = self._execute_operation(
                operation, instance, parameters, user_identity
            )
            
            # Log to audit trail
            self._log_audit(
                operation, instance_id, parameters, user_identity, result
            )
            
            return self._success_response(result)
            
        except Exception as e:
            logger.error(f"Error handling operations request: {str(e)}")
            return self._error_response(500, f"Internal error: {str(e)}")
    
    def _validate_request(
        self,
        operation: str,
        instance_id: str,
        parameters: Dict[str, Any],
        user_identity: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Validate operation request.
        
        Args:
            operation: Operation type
            instance_id: RDS instance identifier
            parameters: Operation parameters
            user_identity: User identity from API Gateway
            
        Returns:
            dict: Validation result with 'valid' and 'error' keys
        """
        # Check operation type
        if not operation:
            return {'valid': False, 'error': 'Operation type is required'}
        
        if operation not in self.ALLOWED_OPERATIONS:
            return {
                'valid': False,
                'error': f"Operation '{operation}' not allowed. "
                        f"Allowed: {', '.join(self.ALLOWED_OPERATIONS)}"
            }
        
        # Check instance ID
        if not instance_id:
            return {'valid': False, 'error': 'Instance ID is required'}
        
        # Validate operation-specific parameters
        if operation == 'create_snapshot':
            if not parameters.get('snapshot_id'):
                return {'valid': False, 'error': 'snapshot_id is required'}
        
        elif operation == 'modify_backup_window':
            if not parameters.get('backup_window'):
                return {'valid': False, 'error': 'backup_window is required'}
            
            # Validate backup window format (HH:MM-HH:MM)
            backup_window = parameters['backup_window']
            if not self._validate_backup_window_format(backup_window):
                return {
                    'valid': False,
                    'error': 'Invalid backup_window format. Use HH:MM-HH:MM'
                }
        
        return {'valid': True, 'error': None}
    
    def _validate_backup_window_format(self, window: str) -> bool:
        """
        Validate backup window format.
        
        Args:
            window: Backup window string (HH:MM-HH:MM)
            
        Returns:
            bool: True if valid format
        """
        try:
            parts = window.split('-')
            if len(parts) != 2:
                return False
            
            for part in parts:
                time_parts = part.split(':')
                if len(time_parts) != 2:
                    return False
                
                hour, minute = int(time_parts[0]), int(time_parts[1])
                if not (0 <= hour <= 23 and 0 <= minute <= 59):
                    return False
            
            return True
        except (ValueError, AttributeError):
            return False
    
    def _get_instance(self, instance_id: str) -> Optional[Dict[str, Any]]:
        """
        Get instance details from inventory.
        
        Args:
            instance_id: RDS instance identifier
            
        Returns:
            dict: Instance details or None if not found
        """
        try:
            table = self.dynamodb.Table(self.inventory_table)
            response = table.get_item(Key={'instance_id': instance_id})
            return response.get('Item')
        except Exception as e:
            logger.error(f"Error getting instance {instance_id}: {str(e)}")
            return None
    
    def _execute_operation(
        self,
        operation: str,
        instance: Dict[str, Any],
        parameters: Dict[str, Any],
        user_identity: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Execute RDS operation.
        
        Args:
            operation: Operation type
            instance: Instance details
            parameters: Operation parameters
            user_identity: User identity
            
        Returns:
            dict: Operation result
        """
        instance_id = instance['instance_id']
        account_id = instance['account_id']
        region = instance['region']
        
        # Get RDS client for target account/region
        # For same-account operations, don't assume role
        current_account = os.environ.get('AWS_ACCOUNT_ID') or boto3.client('sts').get_caller_identity()['Account']
        
        if account_id == current_account:
            # Same account - use direct client
            rds_client = AWSClients.get_rds_client(region=region)
        else:
            # Cross-account - assume role
            external_id = os.environ.get('EXTERNAL_ID', 'rds-dashboard-unique-id-12345')
            role_name = os.environ.get('CROSS_ACCOUNT_ROLE_NAME', 'RDSDashboardCrossAccountRole')
            
            rds_client = AWSClients.get_rds_client(
                region=region,
                account_id=account_id,
                role_name=role_name,
                external_id=external_id
            )
        
        start_time = time.time()
        
        try:
            if operation == 'create_snapshot':
                result = self._create_snapshot(
                    rds_client, instance_id, parameters
                )
            
            elif operation in ['reboot', 'reboot_instance']:
                result = self._reboot_instance(
                    rds_client, instance_id, parameters
                )
            
            elif operation == 'modify_backup_window':
                result = self._modify_backup_window(
                    rds_client, instance_id, parameters
                )
            
            else:
                raise ValueError(f"Unknown operation: {operation}")
            
            duration = time.time() - start_time
            result['duration_seconds'] = round(duration, 2)
            result['success'] = True
            
            return result
            
        except Exception as e:
            duration = time.time() - start_time
            logger.error(f"Operation {operation} failed: {str(e)}")
            return {
                'success': False,
                'error': str(e),
                'duration_seconds': round(duration, 2)
            }

    def _create_snapshot(
        self,
        rds_client: Any,
        instance_id: str,
        parameters: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Create manual snapshot of RDS instance.
        
        Args:
            rds_client: RDS client
            instance_id: RDS instance identifier
            parameters: Snapshot parameters
            
        Returns:
            dict: Snapshot creation result
        """
        snapshot_id = parameters['snapshot_id']
        tags = parameters.get('tags', [])
        
        logger.info(f"Creating snapshot {snapshot_id} for {instance_id}")
        
        # Create snapshot
        response = rds_client.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_id,
            DBInstanceIdentifier=instance_id,
            Tags=tags
        )
        
        snapshot = response['DBSnapshot']
        
        # Poll until snapshot is available or timeout
        status = self._wait_for_snapshot(
            rds_client, snapshot_id, self.OPERATION_TIMEOUT
        )
        
        return {
            'operation': 'create_snapshot',
            'snapshot_id': snapshot_id,
            'status': status,
            'snapshot_arn': snapshot.get('DBSnapshotArn'),
            'snapshot_create_time': snapshot.get('SnapshotCreateTime').isoformat()
            if snapshot.get('SnapshotCreateTime') else None
        }
    
    def _wait_for_snapshot(
        self,
        rds_client: Any,
        snapshot_id: str,
        timeout: int
    ) -> str:
        """
        Wait for snapshot to become available.
        
        Args:
            rds_client: RDS client
            snapshot_id: Snapshot identifier
            timeout: Timeout in seconds
            
        Returns:
            str: Final snapshot status
        """
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = rds_client.describe_db_snapshots(
                    DBSnapshotIdentifier=snapshot_id
                )
                
                if response['DBSnapshots']:
                    status = response['DBSnapshots'][0]['Status']
                    
                    if status == 'available':
                        logger.info(f"Snapshot {snapshot_id} is available")
                        return status
                    
                    if status in ['failed', 'deleted']:
                        logger.error(f"Snapshot {snapshot_id} failed: {status}")
                        return status
                    
                    logger.info(f"Snapshot {snapshot_id} status: {status}")
                
                time.sleep(self.POLL_INTERVAL)
                
            except Exception as e:
                logger.error(f"Error checking snapshot status: {str(e)}")
                return 'error'
        
        logger.warn(f"Snapshot {snapshot_id} timed out after {timeout}s")
        return 'timeout'
    
    def _reboot_instance(
        self,
        rds_client: Any,
        instance_id: str,
        parameters: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Reboot RDS instance.
        
        Args:
            rds_client: RDS client
            instance_id: RDS instance identifier
            parameters: Reboot parameters
            
        Returns:
            dict: Reboot result
        """
        force_failover = parameters.get('force_failover', False)
        
        logger.info(f"Rebooting instance {instance_id} (force_failover={force_failover})")
        
        # Reboot instance
        response = rds_client.reboot_db_instance(
            DBInstanceIdentifier=instance_id,
            ForceFailover=force_failover
        )
        
        instance = response['DBInstance']
        
        # Poll until instance is available or timeout
        status = self._wait_for_instance_available(
            rds_client, instance_id, self.OPERATION_TIMEOUT
        )
        
        return {
            'operation': 'reboot_instance',
            'instance_id': instance_id,
            'status': status,
            'force_failover': force_failover
        }
    
    def _wait_for_instance_available(
        self,
        rds_client: Any,
        instance_id: str,
        timeout: int
    ) -> str:
        """
        Wait for instance to become available.
        
        Args:
            rds_client: RDS client
            instance_id: Instance identifier
            timeout: Timeout in seconds
            
        Returns:
            str: Final instance status
        """
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = rds_client.describe_db_instances(
                    DBInstanceIdentifier=instance_id
                )
                
                if response['DBInstances']:
                    status = response['DBInstances'][0]['DBInstanceStatus']
                    
                    if status == 'available':
                        logger.info(f"Instance {instance_id} is available")
                        return status
                    
                    if status in ['failed', 'deleted', 'incompatible-parameters']:
                        logger.error(f"Instance {instance_id} failed: {status}")
                        return status
                    
                    logger.info(f"Instance {instance_id} status: {status}")
                
                time.sleep(self.POLL_INTERVAL)
                
            except Exception as e:
                logger.error(f"Error checking instance status: {str(e)}")
                return 'error'
        
        logger.warn(f"Instance {instance_id} timed out after {timeout}s")
        return 'timeout'
    
    def _modify_backup_window(
        self,
        rds_client: Any,
        instance_id: str,
        parameters: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Modify backup window for RDS instance.
        
        Args:
            rds_client: RDS client
            instance_id: RDS instance identifier
            parameters: Modification parameters
            
        Returns:
            dict: Modification result
        """
        backup_window = parameters['backup_window']
        apply_immediately = parameters.get('apply_immediately', True)
        
        logger.info(f"Modifying backup window for {instance_id} to {backup_window}")
        
        # Modify backup window
        response = rds_client.modify_db_instance(
            DBInstanceIdentifier=instance_id,
            PreferredBackupWindow=backup_window,
            ApplyImmediately=apply_immediately
        )
        
        instance = response['DBInstance']
        
        return {
            'operation': 'modify_backup_window',
            'instance_id': instance_id,
            'backup_window': backup_window,
            'apply_immediately': apply_immediately,
            'status': instance.get('DBInstanceStatus'),
            'pending_backup_window': instance.get('PendingModifiedValues', {}).get(
                'BackupRetentionPeriod'
            )
        }
    
    def _log_audit(
        self,
        operation: str,
        instance_id: str,
        parameters: Dict[str, Any],
        user_identity: Dict[str, Any],
        result: Dict[str, Any]
    ) -> None:
        """
        Log operation to audit trail.
        
        Args:
            operation: Operation type
            instance_id: RDS instance identifier
            parameters: Operation parameters
            user_identity: User identity
            result: Operation result
        """
        try:
            table = self.dynamodb.Table(self.audit_table)
            
            timestamp = datetime.utcnow().isoformat()
            audit_id = f"{instance_id}#{timestamp}"
            
            # Convert float to Decimal for DynamoDB
            if 'duration_seconds' in result:
                result['duration_seconds'] = Decimal(str(result['duration_seconds']))
            
            item = {
                'audit_id': audit_id,
                'timestamp': timestamp,
                'operation': operation,
                'instance_id': instance_id,
                'parameters': json.dumps(parameters),
                'user_identity': json.dumps(user_identity),
                'result': json.dumps(result, default=str),
                'success': result.get('success', False),
                'ttl': int(time.time()) + (90 * 24 * 60 * 60)  # 90 days retention
            }
            
            table.put_item(Item=item)
            logger.info(f"Audit log created: {audit_id}")
            
        except Exception as e:
            logger.error(f"Error logging audit trail: {str(e)}")
    
    def _success_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create success response."""
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(data, default=str)
        }
    
    def _error_response(self, status_code: int, message: str) -> Dict[str, Any]:
        """Create error response."""
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': message})
        }


def lambda_handler(event, context):
    """
    Lambda handler for operations service.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        dict: API Gateway response
    """
    handler = OperationsHandler()
    return handler.handle_request(event)
