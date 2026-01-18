"""
RDS Discovery Module

Discovers RDS instances in the current AWS account and regions with universal environment support.
Automatically classifies environments based on tags, naming patterns, and account mappings.
"""

import os
from datetime import datetime
from typing import List, Dict, Any
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from shared import AWSClients, StructuredLogger, Config
from shared.environment_classifier import EnvironmentClassifier

logger = StructuredLogger('discovery')


def discover_all_instances(config: Any) -> Dict[str, Any]:
    """
    Discover RDS instances in current account and configured regions with universal environment support.
    
    Args:
        config: Application configuration
    
    Returns:
        dict: Discovery results with instances list and environment classification
    """
    instances = []
    errors = []
    regions_scanned = []
    
    # Initialize environment classifier with universal configuration
    env_config = getattr(config, 'environment_classification', {}) if config else {}
    if not env_config:
        # Use universal default configuration if none provided
        env_config = {
            'default_environment': 'non-production',
            'environment_tag_names': [
                'Environment', 'Env', 'ENV', 'environment', 'env',
                'Environ', 'environ', 'ENVIRON', 'Stage', 'stage', 'STAGE'
            ],
            'naming_patterns': {
                'production': ['^prod-', '^prd-', '^p-', '-prod$', '-prd$', '-production$'],
                'development': ['^dev-', '^development-', '-dev$', '-development$'],
                'test': ['^test-', '^tst-', '^qa-', '-test$', '-tst$', '-qa$'],
                'staging': ['^stg-', '^staging-', '^stage-', '-stg$', '-staging$'],
                'poc': ['^poc-', '^demo-', '^exp-', '^experiment-', '-poc$', '-demo$'],
                'sandbox': ['^sandbox-', '^sbx-', '-sandbox$', '-sbx$']
            }
        }
    
    classifier = EnvironmentClassifier(env_config)
    
    # Get regions from environment or use default
    target_regions_str = os.environ.get('TARGET_REGIONS', '["ap-southeast-1"]')
    try:
        import json
        target_regions = json.loads(target_regions_str)
    except:
        target_regions = ['ap-southeast-1']
    
    logger.info(f'Starting universal discovery in {len(target_regions)} regions', 
               regions=target_regions, 
               classifier_config=bool(env_config))
    
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
                        instance_data = extract_instance_metadata(db_instance, region, classifier)
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
    
    # Analyze environment distribution
    environment_stats = {}
    for instance in instances:
        env = instance.get('environment', 'unknown')
        environment_stats[env] = environment_stats.get(env, 0) + 1
    
    results = {
        'instances': instances,
        'total_instances': len(instances),
        'accounts_scanned': 1,  # Current account only
        'regions_scanned': len(regions_scanned),
        'environment_distribution': environment_stats,
        'universal_classification': True,
        'errors': errors
    }
    
    logger.info('Universal discovery completed',
               total_instances=len(instances),
               regions=len(regions_scanned),
               environment_distribution=environment_stats,
               errors=len(errors))
    
    return results


def extract_instance_metadata(db_instance: Dict[str, Any], region: str, classifier: EnvironmentClassifier) -> Dict[str, Any]:
    """
    Extract metadata from RDS instance with universal environment classification.
    
    Args:
        db_instance: RDS instance description
        region: AWS region
        classifier: Environment classifier instance
    
    Returns:
        dict: Instance metadata with environment classification
    """
    # Extract tags
    tags = {}
    if 'TagList' in db_instance:
        for tag in db_instance['TagList']:
            tags[tag['Key']] = tag['Value']
    
    # Get current account ID from ARN
    arn = db_instance['DBInstanceArn']
    account_id = arn.split(':')[4] if ':' in arn else 'unknown'
    
    # Build basic instance metadata
    instance_data = {
        'instance_id': db_instance['DBInstanceIdentifier'],
        'arn': db_instance['DBInstanceArn'],
        'account_id': account_id,
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
    
    # Add universal environment classification
    environment = classifier.get_environment(instance_data)
    classification_source = classifier.get_classification_source(instance_data)
    
    instance_data.update({
        'environment': environment,
        'environment_classification_source': classification_source,
        'environment_classification_timestamp': datetime.utcnow().isoformat() + 'Z'
    })
    
    logger.info('Instance classified',
               instance_id=instance_data['instance_id'],
               environment=environment,
               classification_source=classification_source,
               account_id=account_id,
               region=region)
    
    return instance_data
