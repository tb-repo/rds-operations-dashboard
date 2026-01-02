# Pre-Deployment Testing Guide

## Overview

This guide provides step-by-step instructions to validate that all critical fixes (500 errors, 403 errors, and account discovery) are working correctly **before** deploying to production.

## Quick Validation (5 minutes)

### 1. Set Environment Variables

```powershell
# Required
$env:BFF_URL = "https://your-bff-domain.com"
$env:API_KEY = "your-api-gateway-key"

# Optional but recommended
$env:AUTH_TOKEN = "your-jwt-token"
$env:TEST_ACCOUNT_ID = "123456789012"
$env:COGNITO_USER_POOL_ID = "your-pool-id"
$env:TEST_USERNAME = "your-test-user"
```

### 2. Run Quick Validation

```powershell
# Quick focused test (recommended)
./validate-critical-fixes.ps1 -BffUrl $env:BFF_URL -ApiKey $env:API_KEY

# Comprehensive validation (optional)
./pre-deployment-validation.ps1
```

### 3. Expected Results

✅ **READY FOR DEPLOYMENT** - All tests pass
❌ **NOT READY** - Issues found, fix before deploying

## Detailed Testing Steps

### Step 1: Test Error Statistics Fix (500 → 200)

**Issue**: `/api/errors/statistics` was returning 500 errors

**Test**:
```powershell
./test-error-statistics-fix.ps1 -BffUrl $env:BFF_URL -ApiKey $env:API_KEY
```

**Expected Results**:
- ✅ BFF error statistics endpoint returns 200 OK
- ✅ Response contains statistics data or graceful fallback
- ✅ No more 500 errors in browser console

**If Test Fails**:
1. Check if BFF changes were deployed
2. Verify monitoring Lambda is working
3. Check CloudWatch logs for BFF and monitoring Lambda

### Step 2: Test Operations Authorization Fix (403 → 200/400)

**Issue**: `/api/operations` was returning 403 Forbidden

**Test**:
```powershell
./test-operations-403-fix.ps1 -BffUrl $env:BFF_URL -ApiKey $env:API_KEY -AuthToken $env:AUTH_TOKEN
```

**Expected Results**:
- ✅ Safe operations return 200 OK or 404 (test instance not found)
- ✅ Invalid operations return 400 Bad Request (not 403)
- ✅ No auth token returns 401 Unauthorized (not 403)
- ✅ Clear error messages for authorization failures

**If Test Fails**:
1. Check user is in Admin or DBA Cognito group:
   ```powershell
   aws cognito-idp admin-list-groups-for-user --user-pool-id $env:COGNITO_USER_POOL_ID --username $env:TEST_USERNAME
   ```
2. Add user to Admin group if needed:
   ```powershell
   aws cognito-idp admin-add-user-to-group --user-pool-id $env:COGNITO_USER_POOL_ID --username $env:TEST_USERNAME --group-name Admin
   ```
3. Check JWT token is valid and not expired
4. Verify operations Lambda changes were deployed

### Step 3: Test Account Discovery

**Issue**: Ensure account discovery is working for new account onboarding

**Test**:
```powershell
# Manual test with test account
$discoveryPayload = @{
    account_id = $env:TEST_ACCOUNT_ID
    regions = @("us-east-1")
} | ConvertTo-Json

$headers = @{
    'x-api-key' = $env:API_KEY
    'Authorization' = "Bearer $env:AUTH_TOKEN"
    'Content-Type' = 'application/json'
}

Invoke-RestMethod -Uri "$env:BFF_URL/api/discovery/trigger" -Method POST -Headers $headers -Body $discoveryPayload
```

**Expected Results**:
- ✅ Discovery endpoint accepts the request (200/202)
- ✅ Discovery process starts (check CloudWatch logs)
- ✅ No authentication errors

**If Test Fails**:
1. Check cross-account IAM roles are set up
2. Verify discovery Lambda is deployed
3. Check CloudWatch logs for discovery Lambda

## Comprehensive Testing

### Run All Tests Together

```powershell
# Set all environment variables first
$env:BFF_URL = "https://your-bff-domain.com"
$env:API_URL = "https://your-api-gateway.com/prod"
$env:API_KEY = "your-api-key"
$env:AUTH_TOKEN = "your-jwt-token"
$env:COGNITO_USER_POOL_ID = "your-pool-id"
$env:TEST_USERNAME = "your-test-user"
$env:TEST_ACCOUNT_ID = "123456789012"

# Run comprehensive validation
./pre-deployment-validation.ps1
```

### Individual Diagnostic Scripts

If any test fails, run these diagnostic scripts:

```powershell
# Diagnose 500 errors
./diagnose-production-api-issues.ps1

# Diagnose 403 errors
./diagnose-operations-403-error.ps1 -UserPoolId $env:COGNITO_USER_POOL_ID -Username $env:TEST_USERNAME

# Fix user permissions
./fix-operations-403-error.ps1 -UserPoolId $env:COGNITO_USER_POOL_ID -Username $env:TEST_USERNAME -AddToAdminGroup
```

## Browser Testing

### 1. Test Dashboard Loading

1. Open browser to your dashboard URL
2. Login with test user credentials
3. Check browser console (F12) for errors
4. Verify no 500 or 403 errors appear

### 2. Test Error Statistics Widget

1. Navigate to main dashboard
2. Look for error monitoring section
3. Should show either:
   - ✅ Statistics data with error counts
   - ✅ "Temporarily unavailable" message (graceful fallback)
   - ❌ No 500 errors in console

### 3. Test Operations

1. Navigate to an instance detail page
2. Try to create a snapshot (safe operation)
3. Should either:
   - ✅ Work successfully
   - ✅ Show clear error message about permissions
   - ❌ No generic 403 errors

## CloudWatch Logs Monitoring

Monitor these log groups during testing:

```powershell
# BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --follow

# Operations Lambda logs
aws logs tail /aws/lambda/rds-operations --follow

# Monitoring Lambda logs
aws logs tail /aws/lambda/rds-monitoring-dashboard --follow

# Discovery Lambda logs
aws logs tail /aws/lambda/rds-discovery --follow
```

## Success Criteria

### ✅ Ready for Deployment When:

1. **Error Statistics**: Returns 200 OK or graceful fallback (no 500 errors)
2. **Operations Authorization**: Returns appropriate status codes:
   - 200 OK for successful operations
   - 400 Bad Request for validation errors
   - 401 Unauthorized for missing auth
   - 404 Not Found for missing instances
   - Clear error messages for permission issues
3. **Account Discovery**: Accepts requests and processes them
4. **Browser Console**: No 500 or 403 errors during normal usage
5. **Authentication Flow**: Proper 401 responses for missing tokens

### ❌ Not Ready When:

1. Still getting 500 errors on statistics endpoint
2. Still getting generic 403 errors on operations
3. Authentication not working properly
4. Browser console shows API errors
5. Discovery endpoint not responding

## Troubleshooting Common Issues

### Issue: Still Getting 500 Errors

**Cause**: BFF routing fix not deployed or monitoring Lambda not working

**Solution**:
1. Verify BFF changes are deployed
2. Check monitoring Lambda exists and is working
3. Verify API Gateway routes are correct

### Issue: Still Getting 403 Errors

**Cause**: User permissions or Lambda authorization logic

**Solution**:
1. Add user to Admin or DBA Cognito group
2. Refresh JWT token (logout/login)
3. Verify operations Lambda changes are deployed
4. Check CloudWatch logs for specific error messages

### Issue: Discovery Not Working

**Cause**: Cross-account permissions or Lambda deployment

**Solution**:
1. Verify cross-account IAM roles exist
2. Check discovery Lambda is deployed
3. Test with same-account first
4. Check CloudWatch logs for permission errors

## Post-Deployment Validation

After deploying, run the same tests to confirm everything works in production:

```powershell
# Update URLs to production endpoints
$env:BFF_URL = "https://your-production-bff.com"
$env:API_URL = "https://your-production-api.com/prod"

# Run validation again
./validate-critical-fixes.ps1 -BffUrl $env:BFF_URL -ApiKey $env:API_KEY
```

## Summary

This testing approach ensures:
- ✅ 500 errors are eliminated
- ✅ 403 errors are resolved with proper authorization
- ✅ Account discovery works for new accounts
- ✅ User experience is improved with better error messages
- ✅ All critical functionality works before production deployment

**Remember**: It's much easier to fix issues in development than in production. Take the time to validate thoroughly before deploying!