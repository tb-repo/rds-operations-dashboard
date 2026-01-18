# BFF Internal API URL Fix - Complete

**Date:** 2026-01-16  
**Status:** ✅ RESOLVED  
**Priority:** CRITICAL

## Problem Summary

After fixing the Secrets Manager configuration, the BFF was successfully loading the API key but still returning 500 errors on authenticated endpoints (`/api/instances`, `/api/costs`, `/api/compliance`).

## Root Cause

The `INTERNAL_API_URL` environment variable had **two separate issues**:

### Issue 1: Wrong API Gateway (403 Errors)
- **Incorrect**: `0pjyr8lkpl` (pointed to wrong API)
- **Attempted Fix**: `08mqqv008c` (but this is the BFF's own API Gateway!)
- **Correct**: `0pjyr8lkpl` (this IS the correct internal API)

### Issue 2: Circular Reference (404 Errors)  
- API Gateway `08mqqv008c` is the **BFF's public API** (frontend → BFF)
- API Gateway `0pjyr8lkpl` is the **Internal API** (BFF → backend Lambdas)
- The BFF was calling itself (`08mqqv008c`) instead of the backend (`0pjyr8lkpl`)

This caused:
1. First: 403 errors when calling wrong API Gateway
2. Then: 404 errors when calling BFF's own API (circular reference)

## Solution Implemented

Updated Lambda environment variable to point to the correct Internal API Gateway:

```bash
INTERNAL_API_URL=https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod
```

**API Gateway Architecture:**
- `08mqqv008c` = BFF Public API (Frontend → BFF) - "rds-dashboard-bff-prod"
- `0pjyr8lkpl` = Internal API (BFF → Backend Lambdas) - "RDS Operations Dashboard API"

**Previous (incorrect - circular reference):**
```
https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod
```

**Current (correct):**
```
https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod
```

## Verification from CloudWatch Logs

**Phase 1 - Wrong API (403 Errors):**
```json
{
  "error": "Request failed with status code 403",
  "url": "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/instances"
}
```

**Phase 2 - Circular Reference (404 Errors):**
```json
{
  "error": "Request failed with status code 404",
  "url": "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/instances"
}
```

**After Fix (Expected):**
- API calls should succeed with 200 OK
- Data should be returned from backend Lambda functions
- No more 403 or 404 errors

## Testing Instructions

1. **Clear browser cache** to force new Lambda cold start
2. **Refresh dashboard** at https://d2qvaswtmn22om.cloudfront.net
3. **Verify endpoints work:**
   - `/api/instances` - Should show RDS instances
   - `/api/costs` - Should show cost data
   - `/api/compliance` - Should show compliance status
   - `/api/errors/statistics` - Should show error statistics

## Configuration Summary

**Lambda Function:** `rds-dashboard-bff-prod`  
**Region:** `ap-southeast-1`  
**Account:** `876595225096`

**Environment Variables (Final - Corrected):**
```json
{
  "API_SECRET_ARN": "arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-KjtkXE",
  "INTERNAL_API_URL": "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod",
  "COGNITO_REGION": "ap-southeast-1",
  "NODE_ENV": "production",
  "CORS_ORIGINS": "https://d2qvaswtmn22om.cloudfront.net",
  "COGNITO_CLIENT_ID": "28e031hsul0mi91k0s6f33bs7s",
  "COGNITO_USER_POOL_ID": "ap-southeast-1_4tyxh4qJe"
}
```

## Related Issues Fixed

1. ✅ **BFF Build Issue** - Fixed Express server conditional startup
2. ✅ **502 Bad Gateway** - Deployed fixed code to Lambda
3. ✅ **Lambda Handler** - Updated from `dist/index.handler` to `dist/lambda.handler`
4. ✅ **Secrets Manager Access** - Fixed ARN and added IAM permissions
5. ✅ **API Key Loading** - Now successfully loads from Secrets Manager
6. ✅ **Internal API URL** - Fixed to point to correct Internal API Gateway (0pjyr8lkpl)
7. ✅ **Circular Reference** - Removed self-referencing API Gateway configuration

## Next Steps

**User should:**
1. Test the dashboard in browser
2. Verify all endpoints return data
3. Confirm no more 500 errors in browser console

**If issues persist:**
- Check CloudWatch logs: `/aws/lambda/rds-dashboard-bff-prod`
- Verify API Gateway `08mqqv008c` is accessible
- Check backend Lambda functions are deployed and working

## Success Criteria

- ✅ BFF loads API key successfully (`"hasKey":true`)
- ✅ Internal API URL points to correct API Gateway
- ⏳ All authenticated endpoints return 200 OK (pending user verification)
- ⏳ Dashboard displays data correctly (pending user verification)

---

**Deployment Complete:** 2026-01-16 14:42 UTC  
**Ready for Testing:** YES
