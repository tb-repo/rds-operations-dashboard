#!/usr/bin/env python3
"""
Property-Based Tests for Universal RDS Environment Support

Property 5: Universal RDS Environment Support
Validates: Requirements 3.1, 3.2, 3.4

Tests that the system works with RDS instances from any AWS environment
without requiring environment-specific configuration.

Governance Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-01-17T00:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.1.0",
  "traceability": "REQ-3.1, REQ-3.2, REQ-3.4 → DESIGN-001 → TASK-6.3",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
from hypothesis import given, strategies as st, settings, assume
import json
from typing import Dict, Any, List
from unittest.mock import Mock, patch, MagicMock
import sys
import os

# Add parent directories to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(os.path.join(os.path.dirname(__file__), '../discovery'))
sys.path.append(os.path.join(os.path.dirname(__file__), '../operations'))

from discovery.discovery import discover_all_instances, extract_instance_metadata
from operations.handler import OperationsHandler
from shared.environment_classifier import EnvironmentClassifier


# Test data generators
@st.composite
def rds_instance_data(draw):
    """Generate realistic RDS instance data for any environment."""
    instance_id = draw(st.text(min_size=5, max_size=50, alphabet=st.characters(whitelist_categories=('Ll', 'Lu', 'Nd'), whitelist_characters='-_')))
    
    # Generate various environment indicators
    environment_tags = draw(st.one_of(
        st.just({}),  # No environment tags
        st.dictionaries(
            st.sampled_from(['Environment', 'Env', 'ENV', 'Stage', 'STAGE']),
            st.sampled_from(['production', 'development', 'test', 'staging', 'poc', 'sandbox']),
            min_size=1, max_size=1
        )
    ))
    
    # Add other realistic tags
    other_tags = draw(st.dictionaries(
        st.text(min_size=1, max_size=20),
        st.text(min_size=1, max_size=50),
        max_size=5
    ))
    
    tags = {**environment_tags, **other_tags}
    
    account_id = draw(st.text(min_size=12, max_size=12, alphabet='0123456789'))
    region = draw(st.sampled_from(['us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1', 'ap-south-1']))
    
    return {
        'DBInstanceIdentifier': instance_id,
        'DBInstanceArn': f'arn:aws:rds:{region}:{account_id}:db:{instance_id}',
        'Engine': draw(st.sampled_from(['postgres', 'mysql', 'oracle-ee', 'sqlserver-ex'])),
        'EngineVersion': draw(st.text(min_size=3, max_size=10)),
        'DBInstanceClass': draw(st.sampled_from(['db.t3.micro', 'db.t3.small', 'db.r5.large', 'db.m5.xlarge'])),
        'DBInstanceStatus': draw(st.sampled_from(['available', 'stopped', 'starting', 'stopping'])),
        'AvailabilityZone': f'{region}a',
        'MultiAZ': draw(st.booleans()),
        'StorageType': draw(st.sampled_from(['gp2', 'gp3', 'io1'])),
        'AllocatedStorage': draw(st.integers(min_value=20, max_value=1000)),
        'StorageEncrypted': draw(st.booleans()),
        'PubliclyAccessible': draw(st.booleans()),
        'Endpoint': {
            'Address': f'{instance_id}.{account_id}.{region}.rds.amazonaws.com',
            'Port': draw(st.integers(min_value=1433, max_value=5432))
        },
        'BackupRetentionPeriod': draw(st.integers(min_value=0, max_value=35)),
        'AutoMinorVersionUpgrade': draw(st.booleans()),
        'DeletionProtection': draw(st.booleans()),
        'TagList': [{'Key': k, 'Value': v} for k, v in tags.items()]
    }


@st.composite
def environment_config(draw):
    """Generate various environment classification configurations."""
    return {
        'default_environment': draw(st.sampled_from(['non-production', 'development', 'unknown'])),
        'environment_tag_names': draw(st.lists(
            st.sampled_from(['Environment', 'Env', 'ENV', 'Stage', 'STAGE', 'environ']),
            min_size=1, max_size=6, unique=True
        )),
        'naming_patterns': {
            'production': ['^prod-', '-prod$', '^p-'],
            'development': ['^dev-', '-dev$'],
            'test': ['^test-', '-test$'],
            'staging': ['^stg-', '-staging$']
        },
        'account_mappings': draw(st.dictionaries(
            st.text(min_size=12, max_size=12, alphabet='0123456789'),
            st.sampled_from(['production', 'development', 'test']),
            max_size=3
        )),
        'instance_mappings': draw(st.dictionaries(
            st.text(min_size=5, max_size=20),
            st.sampled_from(['production', 'development', 'test']),
            max_size=3
        ))
    }


class TestUniversalRDSSupport:
    """Property-based tests for universal RDS environment support."""
    
    @given(rds_instance_data(), environment_config())
    @settings(max_examples=100, deadline=5000)
    def test_discovery_works_with_any_environment_configuration(self, instance_data, env_config):
        """
        Property 5a: Discovery works with any environment configuration.
        
        For any RDS instance and any environment configuration,
        the discovery process should complete successfully and classify the environment.
        """
        # Create classifier with the generated config
        classifier = EnvironmentClassifier(env_config)
        
        # Extract metadata should work with any instance
        region = instance_data['DBInstanceArn'].split(':')[3]
        metadata = extract_instance_metadata(instance_data, region, classifier)
        
        # Verify universal properties
        assert 'instance_id' in metadata
        assert 'environment' in metadata
        assert 'environment_classification_source' in metadata
        assert 'account_id' in metadata
        assert 'region' in metadata
        
        # Environment should be classified (never None or empty)
        assert metadata['environment']
        assert isinstance(metadata['environment'], str)
        assert len(metadata['environment']) > 0
        
        # Classification source should be valid
        valid_sources = ['aws_tag', 'manual_mapping', 'account_mapping', 'naming_pattern', 'default']
        assert metadata['environment_classification_source'] in valid_sources
    
    @given(st.lists(rds_instance_data(), min_size=1, max_size=10))
    @settings(max_examples=50, deadline=10000)
    def test_discovery_handles_mixed_environments(self, instances_data):
        """
        Property 5b: Discovery handles mixed environments correctly.
        
        For any collection of RDS instances from different environments,
        the discovery should classify each correctly without interference.
        """
        # Mock the AWS clients and config
        mock_config = Mock()
        mock_config.environment_classification = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment', 'Env', 'Stage'],
            'naming_patterns': {
                'production': ['^prod-', '-prod$'],
                'development': ['^dev-', '-dev$']
            }
        }
        
        with patch('discovery.discovery.AWSClients') as mock_aws, \
             patch('discovery.discovery.Config') as mock_config_class:
            
            # Setup mocks
            mock_rds_client = Mock()
            mock_aws.get_rds_client.return_value = mock_rds_client
            
            # Mock paginator to return our test instances
            mock_paginator = Mock()
            mock_rds_client.get_paginator.return_value = mock_paginator
            mock_paginator.paginate.return_value = [{'DBInstances': instances_data}]
            
            # Run discovery
            results = discover_all_instances(mock_config)
            
            # Verify results
            assert 'instances' in results
            assert 'environment_distribution' in results
            assert 'universal_classification' in results
            assert results['universal_classification'] is True
            
            # Each instance should be classified
            assert len(results['instances']) == len(instances_data)
            for instance in results['instances']:
                assert 'environment' in instance
                assert 'environment_classification_source' in instance
                assert instance['environment']  # Not empty
    
    @given(rds_instance_data())
    @settings(max_examples=100, deadline=5000)
    def test_operations_work_universally(self, instance_data):
        """
        Property 5c: Operations work with instances from any environment.
        
        For any RDS instance, the operations handler should be able to
        determine the appropriate operations policy without environment-specific config.
        """
        # Create operations handler
        with patch('operations.handler.Config') as mock_config_class, \
             patch('operations.handler.AWSClients') as mock_aws:
            
            mock_config = Mock()
            mock_config.get.return_value = {}  # No environment-specific config
            mock_config_class.load.return_value = mock_config
            
            mock_dynamodb = Mock()
            mock_aws.get_dynamodb_resource.return_value = mock_dynamodb
            
            handler = OperationsHandler()
            
            # Convert RDS instance data to our internal format
            region = instance_data['DBInstanceArn'].split(':')[3]
            account_id = instance_data['DBInstanceArn'].split(':')[4]
            
            instance_metadata = {
                'instance_id': instance_data['DBInstanceIdentifier'],
                'account_id': account_id,
                'region': region,
                'tags': {tag['Key']: tag['Value'] for tag in instance_data.get('TagList', [])}
            }
            
            # Test environment classification
            environment = handler.classifier.get_environment(instance_metadata)
            classification_source = handler.classifier.get_classification_source(instance_metadata)
            
            # Verify universal properties
            assert environment is not None
            assert isinstance(environment, str)
            assert len(environment) > 0
            assert classification_source in ['aws_tag', 'manual_mapping', 'account_mapping', 'naming_pattern', 'default']
    
    @given(st.lists(st.text(min_size=12, max_size=12, alphabet='0123456789'), min_size=1, max_size=5, unique=True))
    @settings(max_examples=50, deadline=5000)
    def test_cross_account_operations_work_universally(self, account_ids):
        """
        Property 5d: Cross-account operations work universally.
        
        For any set of AWS account IDs, the system should handle
        cross-account operations without account-specific configuration.
        """
        # Test that the environment classifier can handle any account
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {'production': ['^prod-']},
            'account_mappings': {},  # No specific account mappings
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        for account_id in account_ids:
            # Create a test instance for this account
            instance = {
                'instance_id': f'test-db-{account_id[-4:]}',
                'account_id': account_id,
                'region': 'us-east-1',
                'tags': {}
            }
            
            # Should classify successfully
            environment = classifier.get_environment(instance)
            source = classifier.get_classification_source(instance)
            
            assert environment == 'non-production'  # Default since no specific mapping
            assert source == 'default'
    
    def test_no_environment_specific_configuration_required(self):
        """
        Property 5e: System works without environment-specific configuration.
        
        The system should work with minimal or no environment-specific configuration,
        using intelligent defaults and universal patterns.
        """
        # Test with empty configuration
        empty_config = {}
        classifier = EnvironmentClassifier(empty_config)
        
        test_instances = [
            {'instance_id': 'prod-database-01', 'account_id': '123456789012', 'region': 'us-east-1', 'tags': {}},
            {'instance_id': 'dev-test-db', 'account_id': '123456789012', 'region': 'us-east-1', 'tags': {}},
            {'instance_id': 'random-db-name', 'account_id': '123456789012', 'region': 'us-east-1', 'tags': {}}
        ]
        
        for instance in test_instances:
            environment = classifier.get_environment(instance)
            source = classifier.get_classification_source(instance)
            
            # Should always return a valid environment
            assert environment is not None
            assert isinstance(environment, str)
            assert len(environment) > 0
            assert source in ['aws_tag', 'manual_mapping', 'account_mapping', 'naming_pattern', 'default']


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])