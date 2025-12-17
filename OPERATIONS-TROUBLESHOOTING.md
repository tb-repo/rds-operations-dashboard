# RDS Operations Troubleshooting Guide

**Date:** 2025-12-09  
**Issue:** RDS operations (start/stop instance) failing  

## Quick Diagnostics

### Step 1: Test Lambda Directly

```powershell
# Test starting a stopped instance
.\scripts\test-operations-lambda.ps1 -InstanceId "your-instance-id" -Operation "start_instance"

# Test stopping a running instance
.\scripts\test-operations-lambda.ps1 -InstanceId "your-instance-id" -Operation "stop_instance"
```

### Step 2: Check CloudWatch Logs

```powershell
# View recent logs
aws logs tail /aws/lambda/rds-dashboard-operations --since 10m --follow

# Search for errors
aws logs filter-log-events `
    --log-group-name /aws/lambda/rds-dashboard-operations `
    --start-time ((Get-Date).AddMinutes(-30).ToUniversalTime() | Get-Date -UFormat %s) `
    --filter-pattern "ERROR"
```

### Step 3: Verify IAM Permissions

```powershell
# Check Lambda execution role
aws lambda get-function-configuration `
    --function-name rds-dashboard-operations `
    --query 'Role'

# Get role name from ARN and check policies
$roleArn = aws lambda get-function-configuration --function-name rds-dashboard-operations --query 'Role' --output text
$roleName = $roleArn.Split('/')[-1]

aws iam list-attached-role-policies --role-name $roleName
aws iam list-role-policies --role-name $roleName
```

## Common Issues and Fixes

### Issue 1: Permission Denied (403)

**Symptoms:**
- Error: "User is not authorized to perform: rds:StartDBInstance"
- Status Code: 403

**Cause:** Lambda execution role missing RDS permissions

**Fix:**
```powershell
# Check current permissions
aws iam get-role-policy `
    --role-name RDSDashboardLambdaRole `
    --policy-name RDSOperationsPolicy

# If missing, add permissions (done via CDK)
cd infrastructure
npx cdk deploy RDSDashboard-IAM --require-approval never
```

**Required Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:StartDBInstance",
        "rds:StopDBInstance",
        "rds:RebootDBInstance",
        "rds:CreateDBSnapshot",
        "rds:ModifyDBInstance",
        "rds:DescribeDBInstances",
        "rds:DescribeDBSnapshots"
      ],
      "Resource": "*"
    }
  ]
}
```

### Issue 2: Instance Not Found (404)

**Symptoms:**
- Error: "Instance {instance_id} not found"
- Status Code: 404

**Cause:** Instance not in DynamoDB inventory table

**Fix:**
```powershell
# Check if instance exists in inventory
aws dynamodb get-item `
    --table-name rds-inventory-prod `
    --key '{"instance_id": {"S": "your-instance-id"}}'

# If missing, trigger discovery
aws lambda invoke `
    --function-name rds-dashboard-discovery `
    --payload '{}' `
    response.json
```

### Issue 3: Production Instance Blocked (403)

**Symptoms:**
- Error: "Operations not allowed on production instances"
- Status Code: 403

**Cause:** Instance classified as production

**Fix:**
```powershell
# Check instance classification
aws dynamodb get-item `
    --table-name rds-inventory-prod `
    --key '{"instance_id": {"S": "your-instance-id"}}' `
    --query 'Item.tags'

# Update tags if misclassified
# Production instances require CloudOps request
```

### Issue 4: Cross-Account Role Assumption Failed

**Symptoms:**
- Error: "AccessDenied when calling AssumeRole"
- Error: "Invalid external ID"

**Cause:** Cross-account role not configured or external ID mismatch

**Fix:**
```powershell
# Check external ID in Lambda environment
aws lambda get-function-configuration `
    --function-name rds-dashboard-operations `
    --query 'Environment.Variables.EXTERNAL_ID'

# Verify cross-account role exists
aws iam get-role `
    --role-name RDSDashboardCrossAccountRole `
    --profile target-account

# Check trust policy
aws iam get-role `
    --role-name RDSDashboardCrossAccountRole `
    --query 'Role.AssumeRolePolicyDocument' `
    --profile target-account
```

### Issue 5: Instance in Invalid State

**Symptoms:**
- Error: "Cannot start instance in state: starting"
- Error: "Cannot stop instance in state: stopping"

**Cause:** Instance already transitioning

**Fix:**
Wait for current operation to complete, then retry.

```powershell
# Check current instance status
aws rds describe-db-instances `
    --db-instance-identifier your-instance-id `
    --query 'DBInstances[0].DBInstanceStatus'

# Valid states for operations:
# - start_instance: stopped
# - stop_instance: available
# - reboot_instance: available
```

### Issue 6: Timeout (504)

**Symptoms:**
- Error: "Operation timed out after 300 seconds"
- Status: timeout

**Cause:** RDS operation taking longer than Lambda timeout

**Fix:**
```powershell
# Increase Lambda timeout
aws lambda update-function-configuration `
    --function-name rds-dashboard-operations `
    --timeout 600

# Or use async invocation
aws lambda invoke `
    --function-name rds-dashboard-operations `
    --invocation-type Event `
    --payload file://payload.json `
    response.json
```

## Testing Checklist

- [ ] Lambda function exists and is deployed
- [ ] Lambda has correct IAM permissions
- [ ] Instance exists in DynamoDB inventory
- [ ] Instance is classified as non-production
- [ ] Instance is in correct state for operation
- [ ] Cross-account role configured (if needed)
- [ ] External ID matches (if cross-account)
- [ ] CloudWatch logs show detailed error

## Manual Testing Commands

### Test Start Instance

```powershell
# Create payload
$payload = @'
{
  "body": "{\"operation\":\"start_instance\",\"instance_id\":\"your-instance-id\",\"parameters\":{}}",
  "requestContext": {
    "identity": {
      "userArn": "arn:aws:iam::123456789012:user/test-user",
      "sourceIp": "127.0.0.1"
    }
  }
}
'@

$payload | Out-File payload.json -Encoding UTF8

# Invoke Lambda
aws lambda invoke `
    --function-name rds-dashboard-operations `
    --payload file://payload.json `
    --cli-binary-format raw-in-base64-out `
    response.json

# Check response
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

### Test Stop Instance

```powershell
# Create payload
$payload = @'
{
  "body": "{\"operation\":\"stop_instance\",\"instance_id\":\"your-instance-id\",\"parameters\":{}}",
  "requestContext": {
    "identity": {
      "userArn": "arn:aws:iam::123456789012:user/test-user",
      "sourceIp": "127.0.0.1"
    }
  }
}
'@

$payload | Out-File payload.json -Encoding UTF8

# Invoke Lambda
aws lambda invoke `
    --function-name rds-dashboard-operations `
    --payload file://payload.json `
    --cli-binary-format raw-in-base64-out `
    response.json

# Check response
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

## Debugging Steps

1. **Enable Debug Logging**
```powershell
aws lambda update-function-configuration `
    --function-name rds-dashboard-operations `
    --environment Variables={LOG_LEVEL=DEBUG}
```

2. **Check Lambda Configuration**
```powershell
aws lambda get-function-configuration `
    --function-name rds-dashboard-operations
```

3. **Verify Environment Variables**
```powershell
aws lambda get-function-configuration `
    --function-name rds-dashboard-operations `
    --query 'Environment.Variables'
```

4. **Test RDS API Directly**
```powershell
# Test if you can start instance directly
aws rds start-db-instance --db-instance-identifier your-instance-id

# Test if you can describe instance
aws rds describe-db-instances --db-instance-identifier your-instance-id
```

## Next Steps

If issue persists after trying above fixes:

1. Share the exact error message from CloudWatch logs
2. Share the Lambda response JSON
3. Share the instance details from DynamoDB
4. Verify the instance state in AWS Console

## Contact

For additional support, provide:
- CloudWatch log stream name
- Request ID from error
- Instance ID
- Operation attempted
- Full error message
