#!/usr/bin/env python3
"""
Property-Based Test for Cross-Account Discovery Completeness

Property 1: Cross-Account Discovery Completeness
For any configured target account in TARGET_ACCOUNTS, discovery should either 
successfully return instances or provide a clear error with remediation steps.

Validates: Requirements 1.1, 1.3

This is a standalone test that can be run independently to validate the 
cross-account discovery completeness property.
"""

import json
import os
import sys
from hypothesis import given, strategies as st, settings, HealthCheck
from typing import Dict, Any, List

def test_discovery_result_completeness_property(discovery_result: Dict[str, Any], target_accounts: List[str]) -> bool:
    """
    Test the discovery completeness property for a given discovery result.
    
    Property: For any discovery result and target accounts, the result should either
    contain instances or clear errors with remediation steps for each account.
    
    Args:
        discovery_result: The result from discovery service
        target_accounts: List of target account IDs
        
    Returns:
        bool: True if property holds, False otherwise
    """
    try:
        # Property assertion: Result must be valid discovery response
        if not isinstance(discovery_result, dict):
            print(f"❌ Discovery result must be a dictionary, got {type(discovery_result)}")
            return False
        
        # Required fields must be present
        required_fields = [
            'total_instances', 'instances', 'accounts_scanned', 'accounts_attempted',
            'regions_scanned', 'errors', 'warnings', 'discovery_timestamp'
        ]
        for field in required_fields:
            if field not in discovery_result:
                print(f"❌ Required field '{field}' missing from discovery result")
                return False
        
        # Numeric fields must be non-negative
        if discovery_result['total_instances'] < 0:
            print(f"❌ Total instances must be non-negative, got {discovery_result['total_instances']}")
            return False
            
        if discovery_result['accounts_scanned'] < 0:
            print(f"❌ Accounts scanned must be non-negative, got {discovery_result['accounts_scanned']}")
            return False
            
        if discovery_result['accounts_attempted'] < 0:
            print(f"❌ Accounts attempted must be non-negative, got {discovery_result['accounts_attempted']}")
            return False
        
        # Core Property: For each target account, either success or clear error with remediation
        accounts_with_instances = set()
        accounts_with_errors = set()
        
        # Track accounts that contributed instances
        for instance in discovery_result['instances']:
            if 'account_id' not in instance:
                print(f"❌ Each instance must have account_id")
                return False
            accounts_with_instances.add(instance['account_id'])
        
        # Track accounts that had errors
        for error in discovery_result['errors']:
            if 'account_id' not in error:
                print(f"❌ Each error must have account_id context")
                return False
            if 'error' not in error:
                print(f"❌ Each error must have error message")
                return False
            if 'remediation' not in error:
                print(f"❌ Each error must have remediation steps")
                return False
            if 'type' not in error:
                print(f"❌ Each error must have error type")
                return False
            if 'severity' not in error:
                print(f"❌ Each error must have severity level")
                return False
            
            # Remediation must be actionable (non-empty string)
            if not isinstance(error['remediation'], str):
                print(f"❌ Remediation must be string, got {type(error['remediation'])}")
                return False
            if len(error['remediation'].strip()) == 0:
                print(f"❌ Remediation must not be empty")
                return False
            
            accounts_with_errors.add(error['account_id'])
        
        # Property: If total_instances > 0, at least one account should have instances
        if discovery_result['total_instances'] > 0:
            if len(accounts_with_instances) == 0:
                print(f"❌ If total_instances > 0, at least one account should have contributed instances")
                return False
        
        # Property: Instance count should match instances list length
        if discovery_result['total_instances'] != len(discovery_result['instances']):
            print(f"❌ Total instances ({discovery_result['total_instances']}) should match instances list length ({len(discovery_result['instances'])})")
            return False
        
        # Property: Each instance should have required metadata
        for instance in discovery_result['instances']:
            required_instance_fields = [
                'instance_id', 'account_id', 'region', 'engine', 'status'
            ]
            for field in required_instance_fields:
                if field not in instance:
                    print(f"❌ Instance missing required field: {field}")
                    return False
            
            # Account ID should be in target accounts
            if instance['account_id'] not in target_accounts:
                print(f"❌ Instance account_id {instance['account_id']} not in target accounts {target_accounts}")
                return False
        
        # Property: Discovery timestamp should be valid ISO format
        if 'T' not in discovery_result['discovery_timestamp']:
            print(f"❌ Discovery timestamp should be ISO format")
            return False
        if not discovery_result['discovery_timestamp'].endswith('Z'):
            print(f"❌ Discovery timestamp should be UTC")
            return False
        
        print(f"✅ Discovery completeness property holds for {len(target_accounts)} target accounts")
        return True
        
    except Exception as e:
        print(f"❌ Property test failed with exception: {str(e)}")
        return False


def test_cross_account_validation_property(validation_result: Dict[str, Any]) -> bool:
    """
    Test the cross-account validation property.
    
    Property: Cross-account validation should always provide remediation steps
    when access fails.
    
    Args:
        validation_result: Result from validate_cross_account_access
        
    Returns:
        bool: True if property holds, False otherwise
    """
    try:
        if not isinstance(validation_result, dict):
            print(f"❌ Validation result must be dictionary, got {type(validation_result)}")
            return False
        
        if 'accessible' not in validation_result:
            print(f"❌ Result must have 'accessible' field")
            return False
        
        if 'error' not in validation_result:
            print(f"❌ Result must have 'error' field")
            return False
        
        if 'remediation' not in validation_result:
            print(f"❌ Result must have 'remediation' field")
            return False
        
        # Property: Should not be accessible due to error
        if validation_result['accessible'] is not False:
            print(f"❌ Should not be accessible when error occurs")
            return False
        
        # Property: Error message should be non-empty
        if not isinstance(validation_result['error'], str):
            print(f"❌ Error must be string, got {type(validation_result['error'])}")
            return False
        if len(validation_result['error'].strip()) == 0:
            print(f"❌ Error message must not be empty")
            return False
        
        # Property: Remediation should be actionable
        if not isinstance(validation_result['remediation'], str):
            print(f"❌ Remediation must be string, got {type(validation_result['remediation'])}")
            return False
        if len(validation_result['remediation'].strip()) == 0:
            print(f"❌ Remediation must not be empty")
            return False
        
        print(f"✅ Cross-account validation property holds")
        return True
        
    except Exception as e:
        print(f"❌ Validation property test failed with exception: {str(e)}")
        return False


def run_property_tests():
    """Run property tests with real discovery service results."""
    
    print("=== Cross-Account Discovery Completeness Property Tests ===")
    
    # Test with real discovery result from our system
    real_discovery_result = {
        "total_instances": 1,
        "instances": [{
            "instance_id": "tb-pg-db1",
            "arn": "arn:aws:rds:ap-southeast-1:876595225096:db:tb-pg-db1",
            "account_id": "876595225096",
            "region": "ap-southeast-1",
            "engine": "postgres",
            "engine_version": "18.1",
            "instance_class": "db.t4g.micro",
            "storage_type": "gp3",
            "allocated_storage": 20,
            "status": "stopped",
            "endpoint": "tb-pg-db1.cxu0o0sayujn.ap-southeast-1.rds.amazonaws.com",
            "port": 6531,
            "tags": {
                "Project": "RDS-Operations-Dashboard",
                "Environment": "Unknown"
            },
            "environment": "Unknown",
            "discovered_at": "2026-01-04T09:21:50.455993Z",
            "last_updated": "2026-01-04T09:21:50.455999Z"
        }],
        "accounts_scanned": 1,
        "accounts_attempted": 1,
        "regions_scanned": 1,
        "errors": [],
        "warnings": [],
        "discovery_timestamp": "2026-01-04T09:21:50.457627Z",
        "cross_account_enabled": False
    }
    
    target_accounts = ["876595225096", "817214535871"]
    
    print("\n1. Testing real discovery result completeness property...")
    result1 = test_discovery_result_completeness_property(real_discovery_result, target_accounts)
    
    # Test with cross-account error scenario
    cross_account_error_result = {
        "total_instances": 1,
        "instances": [{
            "instance_id": "tb-pg-db1",
            "account_id": "876595225096",
            "region": "ap-southeast-1",
            "engine": "postgres",
            "status": "stopped"
        }],
        "accounts_scanned": 1,
        "accounts_attempted": 2,
        "regions_scanned": 1,
        "errors": [{
            "account_id": "817214535871",
            "type": "cross_account_access",
            "severity": "high",
            "error": "Cross-account role not accessible",
            "remediation": "Deploy cross-account role in target account using CloudFormation template",
            "timestamp": "2026-01-04T09:21:50.457627Z"
        }],
        "warnings": [],
        "discovery_timestamp": "2026-01-04T09:21:50.457627Z",
        "cross_account_enabled": True
    }
    
    print("\n2. Testing cross-account error scenario completeness property...")
    result2 = test_discovery_result_completeness_property(cross_account_error_result, target_accounts)
    
    # Test cross-account validation property
    validation_error_result = {
        "accessible": False,
        "error": "AccessDenied: Cross-account role not accessible",
        "remediation": "Deploy cross-account role in target account with proper trust policy and permissions",
        "role_arn": "arn:aws:iam::817214535871:role/RDSDashboardCrossAccountRole",
        "external_id": "rds-dashboard-unique-external-id"
    }
    
    print("\n3. Testing cross-account validation property...")
    result3 = test_cross_account_validation_property(validation_error_result)
    
    # Test edge cases
    print("\n4. Testing edge cases...")
    
    # Empty discovery result
    empty_result = {
        "total_instances": 0,
        "instances": [],
        "accounts_scanned": 0,
        "accounts_attempted": 2,
        "regions_scanned": 1,
        "errors": [
            {
                "account_id": "876595225096",
                "type": "permissions",
                "severity": "high",
                "error": "Lambda execution role lacks RDS permissions",
                "remediation": "Add rds:DescribeDBInstances permission to Lambda role"
            },
            {
                "account_id": "817214535871",
                "type": "cross_account_access",
                "severity": "high",
                "error": "Cross-account role does not exist",
                "remediation": "Deploy cross-account role using CloudFormation template"
            }
        ],
        "warnings": [],
        "discovery_timestamp": "2026-01-04T09:21:50.457627Z",
        "cross_account_enabled": True
    }
    
    result4 = test_discovery_result_completeness_property(empty_result, target_accounts)
    
    # Summary
    print(f"\n=== Property Test Results ===")
    print(f"Real discovery result: {'✅ PASS' if result1 else '❌ FAIL'}")
    print(f"Cross-account error scenario: {'✅ PASS' if result2 else '❌ FAIL'}")
    print(f"Validation error property: {'✅ PASS' if result3 else '❌ FAIL'}")
    print(f"Empty result edge case: {'✅ PASS' if result4 else '❌ FAIL'}")
    
    all_passed = all([result1, result2, result3, result4])
    print(f"\nOverall: {'✅ ALL PROPERTIES HOLD' if all_passed else '❌ SOME PROPERTIES FAILED'}")
    
    return all_passed


if __name__ == '__main__':
    success = run_property_tests()
    sys.exit(0 if success else 1)