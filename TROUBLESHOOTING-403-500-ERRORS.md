# Troubleshooting 403 and 500 Errors

**Last Updated:** 2025-12-18  
**Issue:** Operations blocked with 403 errors and health endpoint returning 500 errors

## Quick Fix

If you're seeing errors like:
- `Authorization denied: Production instance protection`
- `Error fetching health metrics` with 500 status
- `Operations not allowed on production instances`

**Run this command:**

```powershell
# Diagnose the issue
.\diagnose-instance-environment.ps1 -InstanceId database-1

# Apply the fix (set to Development environment)
.\fix-instance-environment.ps1 -InstanceId database-1 -Environment Development -Force
```

## Understanding the Errors

### Error 1: 403 Authorization Denied

```
Authorization denied: Production instance protection
Instance not found
```

**Root Cause:** The system is classifying your instance as "production" and blocking operations for safety.

**Why this happens:**
1. Instance has `Environment: Production` tag in AWS
2. Instance has no `Environment` tag (defaults to production-level restrictions)
3. DynamoDB inventory is out of sync with actual AWS tags

### Error 2: 500 Health Endpoint Error

```
Error fetching health metrics
Request failed with status code 500
```

**Root Cause:** The health monitor Lambda is failing when processing the instance.

**Why this happens:**
1. Instance doesn't exist in DynamoDB inventory
2. Cross-account role permissions are missing
3. CloudWatch metrics API is failing
4. Instance is in an unexpected state

## Diagnostic Steps

### Step 1: Check Instance Environment Tag

```powershell
# Get instance ARN
$instanceArn = aws rds describe-db-instances --db-instance-identifier database-1 --query 'DBInstances[0].DBInstanceArn' --output text

# Check tags
aws rds list-tags-for-resource --resource-name $instanceArn
```

**Look for:**
```json
{
  "TagList": [
    {
      "Key": "Environment",
      "Value": "Production"  // ← This causes the 403 error
    }
  ]
}
```

### Step 2: Check DynamoDB Inventory

```powershell
# Check if instance exists in inventory
aws dynamodb get-item --table-name rds-inventory-prod --key '{"instance_id": {"S": "database-1"}}'
```

**If not found:** Run discovery to populate inventory
```powershell
.\scripts\activate-discovery.ps1
```

### Step 3: Check BFF Logs

```powershell
# Get recent BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

**Look for:**
- `Authorization denied: Production instance protection`
- `Error fetching instance details`
- `Instance not found`

### Step 4: Check Health Monitor Logs

```powershell
# Get recent health monitor logs
aws logs tail /aws/lambda/rds-health-monitor --follow
```

**Look for:**
- CloudWatch API errors
- Permission denied errors
- Instance not found errors

## Solutions

### Solution 1: Change Environment Tag (Recommended)

If the instance is actually a development/test instance:

```powershell
# Set to Development
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:REGION:ACCOUNT:db:database-1 \
  --tags Key=Environment,Value=Development

# Or use the fix script
.\fix-instance-environment.ps1 -InstanceId database-1 -Environment Development
```

**Environment options:**
- `Development` - Standard non-production rules
- `Test` - Standard non-production rules
- `Staging` - Standard non-production rules
- `POC` - Relaxed rules (no deletion protection required)
- `Sandbox` - Relaxed rules (no deletion protection required)

### Solution 2: Add Missing Environment Tag

If the instance has no Environment tag:

```powershell
# Add Environment tag
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:REGION:ACCOUNT:db:database-1 \
  --tags Key=Environment,Value=Development
```

### Solution 3: Refresh Dashboard Inventory

After changing tags, refresh the dashboard inventory:

```powershell
# Run discovery
.\scripts\activate-discovery.ps1

# Wait 2-3 minutes for completion
# Then try your operation again
```

### Solution 4: Use CloudOps for Production Instances

If the instance is truly production and you need to perform operations:

1. Go to the CloudOps section in the dashboard
2. Generate a change request instead of direct operations
3. This creates a documented, auditable change process

### Solution 5: Fix Health Monitor Issues

If health endpoint continues to fail:

```powershell
# Check Lambda permissions
aws lambda get-policy --function-name rds-health-monitor

# Check CloudWatch permissions
aws iam get-role-policy --role-name RDSHealthMonitorRole --policy-name CloudWatchAccess

# Manually invoke health monitor to see detailed errors
aws lambda invoke --function-name rds-health-monitor --payload '{"instance_id": "database-1"}' response.json
cat response.json
```

## Prevention

### 1. Always Tag New Instances

When creating RDS instances, always add the Environment tag:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-instance \
  --tags Key=Environment,Value=Development \
         Key=Team,Value=MyTeam \
         Key=CostCenter,Value=CC-1234 \
  ...
```

### 2. Use AWS Config for Tag Enforcement

Create an AWS Config rule to require Environment tags:

```yaml
# AWS Config rule
ConfigRuleName: require-rds-environment-tag
Source:
  Owner: AWS
  SourceIdentifier: REQUIRED_TAGS
InputParameters:
  tag1Key: Environment
  tag1Value: Production,Development,Test,Staging,POC,Sandbox
```

### 3. Regular Inventory Sync

Schedule regular discovery runs to keep inventory in sync:

```powershell
# Run discovery every hour (already configured in EventBridge)
# Or manually trigger when needed
.\scripts\activate-discovery.ps1
```

### 4. Monitor Dashboard Health

Set up CloudWatch alarms for:
- BFF 403/500 error rates
- Health monitor failures
- Discovery failures

## Common Scenarios

### Scenario 1: New Instance Not Showing Up

**Symptoms:**
- Instance exists in AWS but not in dashboard
- 404 errors when trying to access instance

**Solution:**
```powershell
# Run discovery
.\scripts\activate-discovery.ps1

# Wait 2-3 minutes
# Refresh dashboard
```

### Scenario 2: Operations Blocked After Tag Change

**Symptoms:**
- Changed Environment tag but still getting 403 errors
- Dashboard shows old environment

**Solution:**
```powershell
# Clear cache and refresh inventory
.\scripts\activate-discovery.ps1

# Wait for completion
# Try operation again
```

### Scenario 3: Health Metrics Not Loading

**Symptoms:**
- Instance details page shows "Error loading health metrics"
- 500 errors in BFF logs

**Solution:**
```powershell
# Check if instance is in inventory
aws dynamodb get-item --table-name rds-inventory-prod --key '{"instance_id": {"S": "database-1"}}'

# If not found, run discovery
.\scripts\activate-discovery.ps1

# Check health monitor logs for specific errors
aws logs tail /aws/lambda/rds-health-monitor --follow
```

### Scenario 4: Cross-Account Instance Issues

**Symptoms:**
- Instances from other AWS accounts not accessible
- Permission denied errors

**Solution:**
```powershell
# Verify cross-account role exists
aws iam get-role --role-name RDSDashboardCrossAccountRole --profile target-account

# Verify trust relationship
aws iam get-role --role-name RDSDashboardCrossAccountRole --query 'Role.AssumeRolePolicyDocument' --profile target-account

# Test assume role
aws sts assume-role --role-arn arn:aws:iam::TARGET_ACCOUNT:role/RDSDashboardCrossAccountRole --role-session-name test --external-id rds-dashboard-unique-id-12345
```

## Verification

After applying fixes, verify everything works:

### 1. Check Instance Classification

```powershell
.\diagnose-instance-environment.ps1 -InstanceId database-1
```

**Expected output:**
```
✅ Instance found: database-1
✅ Tags found:
   - Environment: Development
🎯 Environment Classification: Development
✅ Instance is correctly tagged as non-production.
```

### 2. Test Operations

Try a simple operation like creating a snapshot:

```powershell
# Via dashboard UI
# Or via API
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "instance_id": "database-1",
    "operation": "create_snapshot",
    "parameters": {
      "snapshot_id": "test-snapshot-$(date +%s)"
    }
  }'
```

**Expected response:**
```json
{
  "success": true,
  "operation": "create_snapshot",
  "snapshot_id": "test-snapshot-1234567890",
  "status": "available"
}
```

### 3. Check Health Metrics

```powershell
# Via dashboard UI - go to instance details page
# Or via API
curl https://your-bff-url/api/health/database-1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Expected response:**
```json
{
  "instance_id": "database-1",
  "metrics": {
    "CPUUtilization": 25.5,
    "DatabaseConnections": 10,
    "FreeStorageSpace": 50000000000
  },
  "timestamp": "2025-12-18T18:30:00Z"
}
```

## Getting Help

If issues persist after trying these solutions:

1. **Check the logs:**
   ```powershell
   # BFF logs
   aws logs tail /aws/lambda/rds-dashboard-bff --follow
   
   # Health monitor logs
   aws logs tail /aws/lambda/rds-health-monitor --follow
   
   # Operations logs
   aws logs tail /aws/lambda/rds-operations --follow
   ```

2. **Review documentation:**
   - [Environment Classification Guide](./docs/environment-classification.md)
   - [Operations Service Documentation](./docs/operations-service.md)
   - [Deployment Guide](./docs/deployment.md)

3. **Check CloudWatch metrics:**
   - BFF error rates
   - Lambda invocation errors
   - API Gateway 4xx/5xx errors

4. **Verify infrastructure:**
   ```powershell
   # Check all stacks are deployed
   aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
   
   # Verify Lambda functions exist
   aws lambda list-functions --query 'Functions[?contains(FunctionName, `rds-dashboard`)].FunctionName'
   ```

## Related Documentation

- [Environment Classification Guide](./docs/environment-classification.md)
- [Operations Service](./docs/operations-service.md)
- [BFF Security Guide](./docs/bff-security-guide.md)
- [Troubleshooting Guide](./OPERATIONS-TROUBLESHOOTING.md)

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-12-18  
**Maintained By:** DBA Team
