#!/usr/bin/env python3
"""
Test cross-account role validation
"""
import boto3
import json
import os

def test_cross_account_access():
    """Test cross-account role assumption"""
    
    # Configuration
    cross_account = "817214535871"
    hub_account = "876595225096"
    role_name = "RDSDashboardCrossAccountRole"
    external_id = "rds-dashboard-unique-external-id"
    
    print(f"Testing cross-account access to account {cross_account}")
    print(f"Hub account: {hub_account}")
    print(f"Role name: {role_name}")
    print(f"External ID: {external_id[:8]}...")
    
    try:
        # Get current account
        sts = boto3.client('sts')
        current_identity = sts.get_caller_identity()
        current_account = current_identity['Account']
        print(f"Current account: {current_account}")
        
        if current_account != hub_account:
            print(f"❌ Expected to be running in hub account {hub_account}, but running in {current_account}")
            return False
        
        # Try to assume cross-account role
        role_arn = f"arn:aws:iam::{cross_account}:role/{role_name}"
        print(f"Attempting to assume role: {role_arn}")
        
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName='cross-account-test',
            ExternalId=external_id,
            DurationSeconds=900
        )
        
        print("✅ Role assumption successful")
        
        # Test RDS access with assumed role
        credentials = response['Credentials']
        rds_client = boto3.client(
            'rds',
            region_name='ap-southeast-1',
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )
        
        print("Testing RDS access with assumed role...")
        instances_response = rds_client.describe_db_instances(MaxRecords=5)
        instance_count = len(instances_response['DBInstances'])
        
        print(f"✅ RDS access successful - found {instance_count} instances in cross-account")
        
        if instance_count > 0:
            for instance in instances_response['DBInstances']:
                print(f"  - {instance['DBInstanceIdentifier']} ({instance['DBInstanceStatus']})")
        
        return True
        
    except Exception as e:
        error_str = str(e)
        print(f"❌ Cross-account access failed: {error_str}")
        
        # Provide specific guidance
        if 'AccessDenied' in error_str:
            print("\n🔧 Remediation steps:")
            print(f"1. Ensure role '{role_name}' exists in account {cross_account}")
            print(f"2. Update trust policy to allow account {hub_account}")
            print(f"3. Include ExternalId '{external_id}' in trust policy")
            print("4. Attach RDS permissions to the role")
            print("\nExample trust policy:")
            trust_policy = {
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"AWS": f"arn:aws:iam::{hub_account}:root"},
                    "Action": "sts:AssumeRole",
                    "Condition": {"StringEquals": {"sts:ExternalId": external_id}}
                }]
            }
            print(json.dumps(trust_policy, indent=2))
        
        elif 'does not exist' in error_str:
            print(f"\n🔧 Role '{role_name}' does not exist in account {cross_account}")
            print("Deploy the cross-account role using:")
            print(f"aws cloudformation deploy --template-file infrastructure/cross-account-role.yaml --stack-name rds-dashboard-cross-account-role --parameter-overrides ManagementAccountId={hub_account} ExternalId={external_id} --capabilities CAPABILITY_NAMED_IAM --region ap-southeast-1")
        
        return False

if __name__ == '__main__':
    success = test_cross_account_access()
    exit(0 if success else 1)