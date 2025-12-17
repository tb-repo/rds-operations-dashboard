# Backend Lambda Fixes - December 7, 2025

## Issues Found and Fixed

### 1. Approval Workflow Lambda - Missing Environment Variable
**Problem:** `rds-approval-workflow` Lambda was missing `INVENTORY_TABLE` environment variable
**Error:** `Failed to load configuration: Required environment variable not set: INVENTORY_TABLE`
**Fix:** Added `INVENTORY_TABLE=rds-inventory` to Lambda environment variables
**Status:** ✅ Fixed

### 2. Health Monitor Lambda - Module-Level Variable Error  
**Problem:** `rds-health-monitor` Lambda was trying to use `event` and `context` at module initialization
**Error:** `NameError: name 'event' is not defined`
**Location:** `handler.py` line 52
**Fix:** 
- Changed module-level logger initialization to `logger = None`
- Added logger initialization inside `lambda_handler` function with proper event/context
**Status:** ✅ Fixed and Deployed

### 3. BFF API Key Issue (Previously Fixed)
**Problem:** BFF was sending empty API keys to backend
**Fix:** Cached environment variables at startup
**Status:** ✅ Already Fixed

## Commands Used

### Update Approval Workflow Environment Variables
```powershell
aws lambda update-function-configuration `
  --function-name rds-approval-workflow `
  --environment "Variables={
    CLOUDWATCH_NAMESPACE=RDSDashboard,
    AUDIT_LOG_TABLE=audit-log,
    SNS_TOPIC_ARN=arn:aws:sns:ap-southeast-1:876595225096:rds-dashboard-alerts,
    APPROVALS_TABLE=rds-approvals,
    LOG_LEVEL=INFO,
    INVENTORY_TABLE=rds-inventory
  }"
```

### Deploy Health Monitor Fix
```powershell
cd lambda/health-monitor
Compress-Archive -Path * -DestinationPath ../health-monitor.zip -Force
cd ..
aws lambda update-function-code `
  --function-name rds-health-monitor `
  --zip-file fileb://health-monitor.zip
```

## Testing

After these fixes, test the following endpoints:

1. **Approvals** - Should now load without 500 errors
   ```
   GET /api/approvals
   POST /api/approvals
   ```

2. **Health Metrics** - Should now work for specific instances
   ```
   GET /api/health/:instanceId
   ```

3. **Operations** - Should execute without errors
   ```
   POST /api/operations
   ```

## Verification

Check CloudWatch logs to verify fixes:

```powershell
# Check approval workflow logs
aws logs tail /aws/lambda/rds-approval-workflow --follow

# Check health monitor logs  
aws logs tail /aws/lambda/rds-health-monitor --follow

# Check BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

## Expected Behavior After Fixes

✅ Approval workflow Lambda starts successfully
✅ Health monitor Lambda initializes without errors
✅ All API endpoints return proper responses
✅ No more 500 Internal Server Errors
✅ Proper error messages if data doesn't exist

## Next Steps

1. Wait 1-2 minutes for Lambda updates to propagate
2. Refresh the frontend application
3. Test all previously failing endpoints
4. Monitor CloudWatch logs for any remaining issues

## Root Causes

1. **Missing Environment Variables** - Lambda functions deployed without all required configuration
2. **Module-Level Initialization** - Python code trying to use function parameters at module level
3. **Incomplete Deployment** - Some Lambdas not updated with latest code/config

## Prevention

To prevent similar issues:
- Always validate Lambda environment variables after deployment
- Use CDK/CloudFormation to manage environment variables consistently
- Avoid module-level initialization that depends on function parameters
- Test all endpoints after deployment
- Monitor CloudWatch logs immediately after deployment
