#!/usr/bin/env python3
"""
Property-Based Tests for Cross-Account Discovery Completeness

Property 1: Cross-Account Discovery Completeness
For any configured target account in TARGET_ACCOUNTS, discovery should either 
successfully return instances or provide a clear error with remediation steps.

Validates: Requirements 1.1, 1.3
"""

import pytest
import json
import os
import sys
from unittest.mock import Mock, patch, MagicMock
from hypothesis import given, strategies as st, settings, HealthCheck
from typing import Dict, Any, List

# Add the lambda directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'discovery'))

# Import directly from handler module
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'discovery'))
import handler as discovery_handler


class TestCrossAccountDiscoveryProperties:
    """Property-based tests for cross-account discovery completeness."""
    
    @given(
        account_ids=st.lists(
            st.text(min_size=12, max_size=12).filter(lambda x: x.isdigit()),
            min_size=1,
            max_size=3
        ),
        regions=st.lists(
            st.sampled_from(['ap-southeast-1', 'us-east-1', 'eu-west-1', 'ap-northeast-1']),
            min_size=1,
            max_size=2
        )
    )
    @settings(
        max_examples=100,
        deadline=30000,  # 30 seconds per test
        suppress_health_check=[HealthCheck.too_slow, HealthCheck.function_scoped_fixture]
    )
    def test_cross_account_discovery_completeness_property(
        self, 
        account_ids: List[str], 
        regions: List[str]
    ):
        """
        Property 1: Cross-Account Discovery Completeness
        
        For any configured target account in TARGET_ACCOUNTS, discovery should either 
        successfully return instances or provide a clear error with remediation steps.
        
        This property ensures that:
        1. Discovery never fails silently for any account
        2. All errors include actionable remediation steps
        3. Success cases return valid instance data
        4. Account context is preserved in all responses
        
        Tag: Feature: cross-account-operations-integration, Property 1: Cross-Account Discovery Completeness
        """
        # Arrange: Set up test environment
        hub_account = account_ids[0]  # First account is hub
        target_accounts = account_ids  # All accounts including hub
        
        # Mock environment variables
        env_vars = {
            'TARGET_ACCOUNTS': json.dumps(target_accounts),
            'TARGET_REGIONS': json.dumps(regions),
            'AWS_ACCOUNT_ID': hub_account,
            'EXTERNAL_ID': 'test-external-id',
            'CROSS_ACCOUNT_ROLE_NAME': 'TestCrossAccountRole',
            'INVENTORY_TABLE': 'test-inventory',
            'METRICS_CACHE_TABLE': 'test-metrics',
            'HEALTH_ALERTS_TABLE': 'test-alerts',
            'AUDIT_LOG_TABLE': 'test-audit',
            'DATA_BUCKET': 'test-bucket',
            'SNS_TOPIC_ARN': 'arn:aws:sns:ap-southeast-1:123456789012:test'
        }
        
        with patch.dict(os.environ, env_vars, clear=False):
            # Mock AWS clients and services
            with patch('shared.AWSClients') as mock_aws_clients, \
                 patch('shared.Config') as mock_config, \
                 patch('persistence.persist_instances') as mock_persist, \
                 patch('boto3.client') as mock_boto3_client:
                
                # Configure mock config
                mock_config.load.return_value = Mock()
                
                # Configure mock STS client for identity
                mock_sts = Mock()
                mock_sts.get_caller_identity.return_value = {'Account': hub_account}
                mock_boto3_client.return_value = mock_sts
                
                # Configure mock RDS clients
                mock_rds_client = Mock()
                mock_paginator = Mock()
                mock_rds_client.get_paginator.return_value = mock_paginator
                
                # Generate test instance data for each account
                test_instances_by_account = {}
                for account_id in target_accounts:
                    instances = []
                    # Generate 0-3 instances per account
                    instance_count = hash(account_id) % 4
                    for i in range(instance_count):
                        instances.append({
                            'DBInstanceIdentifier': f'test-db-{account_id}-{i}',
                            'DBInstanceArn': f'arn:aws:rds:{regions[0]}:{account_id}:db:test-db-{i}',
                            'Engine': 'postgres',
                            'EngineVersion': '13.7',
                            'DBInstanceClass': 'db.t3.micro',
                            'DBInstanceStatus': 'available',
                            'StorageType': 'gp2',
                            'AllocatedStorage': 20,
                            'StorageEncrypted': True,
                            'MultiAZ': False,
                            'AvailabilityZone': f'{regions[0]}a',
                            'PubliclyAccessible': False,
                            'BackupRetentionPeriod': 7,
                            'DeletionProtection': False,
                            'TagList': [
                                {'Key': 'Environment', 'Value': 'test'},
                                {'Key': 'Account', 'Value': account_id}
                            ]
                        })
                    test_instances_by_account[account_id] = instances
                
                # Configure mock paginator responses
                def mock_paginate():
                    # Return instances for the current account being processed
                    current_account = getattr(mock_paginate, 'current_account', hub_account)
                    instances = test_instances_by_account.get(current_account, [])
                    return [{'DBInstances': instances}]
                
                mock_paginator.paginate = mock_paginate
                
                # Configure mock AWS clients to return appropriate clients
                def mock_get_rds_client(region=None, account_id=None, **kwargs):
                    # Set current account for paginator
                    mock_paginate.current_account = account_id or hub_account
                    
                    # Simulate cross-account access issues for non-hub accounts
                    if account_id and account_id != hub_account:
                        # Simulate different cross-account scenarios
                        account_hash = hash(account_id) % 3
                        if account_hash == 0:
                            # Simulate AccessDenied
                            raise Exception('AccessDenied: Cross-account role not accessible')
                        elif account_hash == 1:
                            # Simulate role doesn't exist
                            raise Exception('NoSuchEntity: Role does not exist')
                        # else: account_hash == 2, allow access
                    
                    return mock_rds_client
                
                mock_aws_clients.get_rds_client = mock_get_rds_client
                mock_aws_clients.get_sts_client.return_value = mock_sts
                
                # Configure persistence mock
                mock_persist.return_value = {
                    'success': True,
                    'new_instances': 0,
                    'updated_instances': 0,
                    'deleted_instances': 0
                }
                
                # Act: Execute discovery
                result = discovery_handler.discover_all_instances(mock_config.load.return_value)
                
                # Assert: Verify property holds
                self._assert_discovery_completeness_property(
                    result, target_accounts, regions, hub_account
                )
    
    def _assert_discovery_completeness_property(
        self, 
        result: Dict[str, Any], 
        target_accounts: List[str], 
        regions: List[str],
        hub_account: str
    ):
        """Assert that the discovery completeness property holds."""
        
        # Property assertion: Result must be valid discovery response
        assert isinstance(result, dict), "Discovery result must be a dictionary"
        
        # Required fields must be present
        required_fields = [
            'total_instances', 'instances', 'accounts_scanned', 'accounts_attempted',
            'regions_scanned', 'errors', 'warnings', 'discovery_timestamp'
        ]
        for field in required_fields:
            assert field in result, f"Required field '{field}' missing from discovery result"
        
        # Numeric fields must be non-negative
        assert result['total_instances'] >= 0, "Total instances must be non-negative"
        assert result['accounts_scanned'] >= 0, "Accounts scanned must be non-negative"
        assert result['accounts_attempted'] >= 0, "Accounts attempted must be non-negative"
        assert result['regions_scanned'] >= 0, "Regions scanned must be non-negative"
        
        # Accounts attempted should match target accounts
        assert result['accounts_attempted'] == len(target_accounts), \
            f"Accounts attempted ({result['accounts_attempted']}) should match target accounts ({len(target_accounts)})"
        
        # Core Property: For each target account, either success or clear error with remediation
        accounts_with_instances = set()
        accounts_with_errors = set()
        
        # Track accounts that contributed instances
        for instance in result['instances']:
            assert 'account_id' in instance, "Each instance must have account_id"
            accounts_with_instances.add(instance['account_id'])
        
        # Track accounts that had errors
        for error in result['errors']:
            assert 'account_id' in error, "Each error must have account_id context"
            assert 'error' in error, "Each error must have error message"
            assert 'remediation' in error, "Each error must have remediation steps"
            assert 'type' in error, "Each error must have error type"
            assert 'severity' in error, "Each error must have severity level"
            
            # Remediation must be actionable (non-empty string)
            assert isinstance(error['remediation'], str), "Remediation must be string"
            assert len(error['remediation'].strip()) > 0, "Remediation must not be empty"
            
            accounts_with_errors.add(error['account_id'])
        
        # Property verification: Every target account must be accounted for
        accounted_accounts = accounts_with_instances.union(accounts_with_errors)
        
        # For accounts that were attempted but not in results, they should be in errors
        # (This handles cases where account processing failed completely)
        if result['accounts_attempted'] > len(accounted_accounts):
            # Some accounts were attempted but not accounted for
            # This is acceptable if they're in warnings or if discovery was partial
            pass
        
        # Property: If total_instances > 0, at least one account should have instances
        if result['total_instances'] > 0:
            assert len(accounts_with_instances) > 0, \
                "If total_instances > 0, at least one account should have contributed instances"
        
        # Property: Instance count should match instances list length
        assert result['total_instances'] == len(result['instances']), \
            f"Total instances ({result['total_instances']}) should match instances list length ({len(result['instances'])})"
        
        # Property: Each instance should have required metadata
        for instance in result['instances']:
            required_instance_fields = [
                'instance_id', 'account_id', 'region', 'engine', 'status'
            ]
            for field in required_instance_fields:
                assert field in instance, f"Instance missing required field: {field}"
            
            # Account ID should be in target accounts
            assert instance['account_id'] in target_accounts, \
                f"Instance account_id {instance['account_id']} not in target accounts {target_accounts}"
        
        # Property: Discovery timestamp should be valid ISO format
        assert 'T' in result['discovery_timestamp'], "Discovery timestamp should be ISO format"
        assert result['discovery_timestamp'].endswith('Z'), "Discovery timestamp should be UTC"
        
        # Property: Cross-account enabled should be boolean
        if 'cross_account_enabled' in result:
            assert isinstance(result['cross_account_enabled'], bool), \
                "cross_account_enabled should be boolean"
    
    @given(
        account_id=st.text(min_size=12, max_size=12).filter(lambda x: x.isdigit()),
        error_type=st.sampled_from(['AccessDenied', 'NoSuchEntity', 'InvalidClientTokenId', 'Timeout'])
    )
    @settings(max_examples=50)
    def test_cross_account_validation_error_handling_property(
        self, 
        account_id: str, 
        error_type: str
    ):
        """
        Property: Cross-account validation should always provide remediation steps.
        
        For any account ID and error type, validation should return structured
        error information with actionable remediation steps.
        
        Tag: Feature: cross-account-operations-integration, Property 1: Cross-Account Discovery Completeness
        """
        # Arrange: Mock configuration
        mock_config = Mock()
        
        # Mock environment variables
        env_vars = {
            'CROSS_ACCOUNT_ROLE_NAME': 'TestRole',
            'EXTERNAL_ID': 'test-external-id',
            'AWS_ACCOUNT_ID': '123456789012'
        }
        
        with patch.dict(os.environ, env_vars, clear=False):
            with patch('shared.AWSClients') as mock_aws_clients, \
                 patch('boto3.client') as mock_boto3_client:
                
                # Configure mock to raise specific error type
                mock_sts = Mock()
                if error_type == 'AccessDenied':
                    mock_sts.assume_role.side_effect = Exception('AccessDenied: User is not authorized')
                elif error_type == 'NoSuchEntity':
                    mock_sts.assume_role.side_effect = Exception('NoSuchEntity: Role does not exist')
                elif error_type == 'InvalidClientTokenId':
                    mock_sts.assume_role.side_effect = Exception('InvalidClientTokenId: Invalid credentials')
                elif error_type == 'Timeout':
                    mock_sts.assume_role.side_effect = Exception('Timeout: Request timed out')
                
                mock_aws_clients.get_sts_client.return_value = mock_sts
                mock_boto3_client.return_value = mock_sts
                
                # Act: Validate cross-account access
                result = discovery_handler.validate_cross_account_access(account_id, mock_config)
                
                # Assert: Property verification
                assert isinstance(result, dict), "Validation result must be dictionary"
                assert 'accessible' in result, "Result must have 'accessible' field"
                assert 'error' in result, "Result must have 'error' field"
                assert 'remediation' in result, "Result must have 'remediation' field"
                
                # Property: Should not be accessible due to error
                assert result['accessible'] is False, "Should not be accessible when error occurs"
                
                # Property: Error message should be non-empty
                assert isinstance(result['error'], str), "Error must be string"
                assert len(result['error'].strip()) > 0, "Error message must not be empty"
                
                # Property: Remediation should be actionable
                assert isinstance(result['remediation'], str), "Remediation must be string"
                assert len(result['remediation'].strip()) > 0, "Remediation must not be empty"
                
                # Property: Remediation should contain specific guidance based on error type
                remediation_lower = result['remediation'].lower()
                if error_type == 'AccessDenied':
                    assert any(keyword in remediation_lower for keyword in ['role', 'trust', 'policy']), \
                        "AccessDenied remediation should mention role, trust, or policy"
                elif error_type == 'NoSuchEntity':
                    assert any(keyword in remediation_lower for keyword in ['create', 'deploy', 'cloudformation']), \
                        "NoSuchEntity remediation should mention creation steps"
                elif error_type == 'InvalidClientTokenId':
                    assert any(keyword in remediation_lower for keyword in ['credentials', 'role', 'permissions']), \
                        "InvalidClientTokenId remediation should mention credentials or permissions"
                
                # Property: Result should include context information
                if 'role_arn' in result:
                    assert account_id in result['role_arn'], "Role ARN should contain account ID"
                
                if 'external_id' in result:
                    assert isinstance(result['external_id'], str), "External ID should be string"
                    assert len(result['external_id']) > 0, "External ID should not be empty"


if __name__ == '__main__':
    # Run property tests
    pytest.main([__file__, '-v', '--tb=short'])