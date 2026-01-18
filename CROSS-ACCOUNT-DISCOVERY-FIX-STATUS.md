# Cross-Account Discovery Fix Status

**Date:** January 16, 2026  
**Status:** 🔴 **ISSUE IDENTIFIED - ACTION REQUIRED**

## Problem Summary

Cross-account RDS instance discovery is not working because the required IAM role does not exist in the secondary AWS account (817214535871).

## Diagnostic Results

### ✅ What's Working

1. **Discovery Lambda Configuration**
   - Lambda function exists: `rds-discovery-prod`
   - Environment variables properly configured:
     - TARGET_ACCOUNTS: `["876595225096","817214535871"]`
     - TARGET_REGIONS: `["ap-southeast-1","eu-west-2","ap-south-1","us-east-1"]`
     - CROSS_ACCOUNT_ROLE_NAME: `RDSDashboardCrossAccountRole`
     - EXTERNAL_ID: `rds-dashboard-unique-external-id`

2. **Current Account Discovery**
   - 2 instances found in inventory from primary account (876595225096)
   - Discovery working correctly for primary account

### ❌ What's Broken

1. **Cross-Account Role Missing**
   - Role `RDSDashboardCrossAccountRole` does not exist in account 817214535871
   - Error: "User is not authorized to perform: sts:AssumeRole on resource"
   - Discovery Lambda cannot assume role to access secondary account

2. **No Cross-Account Instances**
   - 0 instances from secondary account (817214535871) in inventory
   - Cross-account discovery completely non-functional

## Root Cause

The cross-account IAM role has not been deployed to the secondary AWS account. The discovery Lambda is configured correctly but cannot access the secondary account without the role.

## Solution

Deploy the cross-account IAM role to account 817214535871 using the provided CloudFormation template.

### Option 1: Automated Deployment (Recommended)

```powershell
# Run the deployment script
./scripts/deploy-cross-account-role.ps1 -TargetAccount 817214535871

# If using AWS CLI profile:
./scripts/deploy-cross-account-role.ps1 -TargetAccount 817214535871 -ProfileName secondary-account
```

### Option 2: Manual Deployment

```bash
# Switch to secondary account credentials
export AWS_PROFILE=secondary-account  # or configure credentials

# Deploy CloudFormation stack
aws cloudformation deploy \
  --template-file infrastructure/cross-account-role.yaml \
  --stack-name rds-dashboard-cross-account-role \
  --parameter-overrides \
      ManagementAccountId=876595225096 \
      ExternalId=rds-dashboard-unique-external-id \
      RoleName=RDSDashboardCrossAccountRole \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
```

### Option 3: AWS Console Deployment

1. Log into AWS Console for account 817214535871
2. Go to CloudFormation service
3. Create new stack
4. Upload template: `infrastructure/cross-account-role.yaml`
5. Set parameters:
   - ManagementAccountId: `876595225096`
   - ExternalId: `rds-dashboard-unique-external-id`
   - RoleName: `RDSDashboardCrossAccountRole`
6. Acknowledge IAM resource creation
7. Create stack

## Verification Steps

After deploying the cross-account role:

### 1. Test Role Assumption

```powershell
# Run diagnostic script
./scripts/diagnose-cross-account-discovery.ps1
```

Expected output:
- ✅ Successfully assumed cross-account role
- ✅ Successfully accessed RDS in secondary account
- ✅ Found RDS instances in secondary account

### 2. Trigger Discovery

```powershell
# Manually invoke discovery Lambda
aws lambda invoke \
  --function-name rds-discovery-prod \
  --region ap-southeast-1 \
  response.json

# Check response
cat response.json
```

### 3. Verify Inventory

```powershell
# Check DynamoDB inventory table
aws dynamodb scan \
  --table-name rds-inventory-prod \
  --region ap-southeast-1 \
  --query 'Items[?account_id.S==`817214535871`].{ID:instance_id.S,Region:region.S}' \
  --output table
```

Expected: Instances from account 817214535871 should appear

### 4. Check Dashboard

1. Open dashboard: https://d2qvaswtmn22om.cloudfront.net
2. Login with credentials
3. Verify instances from both accounts are visible
4. Check that account information is displayed correctly

## IAM Role Details

The cross-account role provides:

### Trust Policy
- Allows account 876595225096 to assume the role
- Requires external ID: `rds-dashboard-unique-external-id`
- Prevents unauthorized access

### Permissions
- **RDS Operations**: Start, stop, reboot, snapshot creation
- **RDS Read**: Describe and list all RDS resources
- **CloudWatch**: Metrics and monitoring data
- **Cost Explorer**: Cost tracking and forecasting
- **EC2 Network**: VPC and security group information
- **Read-Only Access**: General AWS resource visibility

## Security Considerations

1. **External ID**: Prevents confused deputy problem
2. **Least Privilege**: Only necessary RDS and monitoring permissions
3. **Audit Trail**: All actions logged in CloudTrail
4. **Session Duration**: 15-minute sessions for security

## Timeline

- **Issue Discovered**: January 16, 2026
- **Root Cause Identified**: January 16, 2026
- **Solution Provided**: January 16, 2026
- **Deployment Required**: User action needed
- **Expected Resolution**: Within 15 minutes of deployment

## Impact

### Current Impact
- ❌ Cannot discover instances in secondary account
- ❌ Cannot manage instances in secondary account
- ❌ Incomplete infrastructure visibility
- ❌ Dashboard shows only 2 of 3 total instances

### After Fix
- ✅ Complete multi-account discovery
- ✅ Full infrastructure visibility
- ✅ Ability to manage all RDS instances
- ✅ Dashboard shows all 3 instances

## Related Documentation

- Cross-Account Setup Guide: `docs/cross-account-setup.md`
- Multi-Account Quick Start: `MULTI-ACCOUNT-QUICK-START.md`
- New Account Checklist: `NEW-ACCOUNT-CHECKLIST.md`

## Support

If you encounter issues:

1. Check CloudWatch Logs:
   ```bash
   aws logs tail /aws/lambda/rds-discovery-prod --follow --region ap-southeast-1
   ```

2. Run diagnostic script:
   ```powershell
   ./scripts/diagnose-cross-account-discovery.ps1
   ```

3. Review CloudFormation events:
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name rds-dashboard-cross-account-role \
     --region ap-southeast-1
   ```

---

**Status**: Waiting for user to deploy cross-account role in account 817214535871
