"""
RDS Discovery Module

Discovers RDS instances in the current AWS account and regions.
"""

import os
from datetime import datetime
from typing import List, Dict, Any
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from shared import AWSClients, StructuredLogger

logger = StructuredLogger('discovery')


def discover_all_instances(config: Any) -> Dict[str, Any]:
    """
    Discover RDS instances in current account and configured regions.
    
    Args:
        config: Application configuration
    
    Returns:
        dict: Discovery results with instances list
    """
    instances = []
    errors = []
    regions_scanned = []
    
    # Get regions from environment or use default
    target_regions_str = os.environ.get('TARGET_REGIONS', '["ap-southeast-1"]')
    try:
        import json
        target_regions = json.loads(target_regions_str)
    except:
        target_regions = ['ap-southeast-1']
    
    logger.info(f'Starting discovery in {len(target_regions)} regions', regions=target_regions)
    
    for region in target_regions:
        try:
            logger.info(f'Discovering instances in region', region=region)
            
            # Get RDS client for region
            rds_client = AWSClients.get_rds_client(region=region)
            
            # Describe all RDS instances
            paginator = rds_client.get_paginator('describe_db_instances')
            page_iterator = paginator.paginate()
            
            region_instances = 0
            for page in page_iterator:
                for db_instance in page['DBInstances']:
                    try:
                        instance_data = extract_instance_metadata(db_instance, region)
                        instances.append(instance_data)
                        region_instances += 1
                    except Exception as e:
                        logger.error(f'Failed to extract instance metadata',
                                   instance_id=db_instance.get('DBInstanceIdentifier'),
                                   error=str(e))
                        errors.append({
                            'instance_id': db_instance.get('DBInstanceIdentifier'),
                            'region': region,
                            'error': str(e)
                        })
            
            regions_scanned.append(region)
            logger.info(f'Discovered {region_instances} instances in region', 
                       region=region, count=region_instances)
            
        except Exception as e:
            logger.error(f'Failed to discover instances in region',
                        region=region, error=str(e))
            errors.append({
                'region': region,
                'error': str(e)
            })
    
    results = {
        'instances': instances,
        'total_instances': len(instances),
        'accounts_scanned': 1,  # Current account only
        'regions_scanned': len(regions_scanned),
        'errors': errors
    }
    
    logger.info('Discovery completed',
               total_instances=len(instances),
               regions=len(regions_scanned),
               errors=len(errors))
    
    return results


def extract_instance_metadata(db_instance: Dict[str, Any], region: str) -> Dict[str, Any]:
    """
    Extract metadata from RDS instance.
    
    Args:
        db_instance: RDS instance description
        region: AWS region
    
    Returns:
        dict: Instance metadata
    """
    # Extract tags
    tags = {}
    if 'TagList' in db_instance:
        for tag in db_instance['TagList']:
            tags[tag['Key']] = tag['Value']
    
    # Build instance metadata
    instance_data = {
        'instance_id': db_instance['DBInstanceIdentifier'],
        'arn': db_instance['DBInstanceArn'],
        'engine': db_instance['Engine'],
        'engine_version': db_instance['EngineVersion'],
        'instance_class': db_instance['DBInstanceClass'],
        'status': db_instance['DBInstanceStatus'],
        'region': region,
        'availability_zone': db_instance.get('AvailabilityZone'),
        'multi_az': db_instance.get('MultiAZ', False),
        'storage_type': db_instance.get('StorageType'),
        'allocated_storage': db_instance.get('AllocatedStorage'),
        'iops': db_instance.get('Iops'),
        'storage_encrypted': db_instance.get('StorageEncrypted', False),
        'kms_key_id': db_instance.get('KmsKeyId'),
        'publicly_accessible': db_instance.get('PubliclyAccessible', False),
        'endpoint': db_instance.get('Endpoint', {}).get('Address') if db_instance.get('Endpoint') else None,
        'port': db_instance.get('Endpoint', {}).get('Port') if db_instance.get('Endpoint') else None,
        'vpc_id': db_instance.get('DBSubnetGroup', {}).get('VpcId') if db_instance.get('DBSubnetGroup') else None,
        'backup_retention_period': db_instance.get('BackupRetentionPeriod'),
        'preferred_backup_window': db_instance.get('PreferredBackupWindow'),
        'preferred_maintenance_window': db_instance.get('PreferredMaintenanceWindow'),
        'latest_restorable_time': db_instance.get('LatestRestorableTime'),
        'auto_minor_version_upgrade': db_instance.get('AutoMinorVersionUpgrade', False),
        'deletion_protection': db_instance.get('DeletionProtection', False),
        'tags': tags,
        'discovered_at': datetime.utcnow().isoformat() + 'Z',
        'last_updated': datetime.utcnow().isoformat() + 'Z'
    }
    
    return instance_data
