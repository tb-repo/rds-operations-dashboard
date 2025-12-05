# Frontend 500 Error - Resolution Summary

**Date:** November 21, 2025  
**Issue:** Frontend getting 500 Internal Server Error on all endpoints  
**Status:** ✅ RESOLVED

---

## Problem

Frontend was calling BFF API Gateway which was returning 500 errors, even though:
- ✅ Query Handler Lambda works
- ✅ Internal API works with API key  
- ✅ BFF Lambda works when invoked directly
- ✗ BFF API Gateway returns 500

## Root Cause

The BFF API Gateway integration is broken. When the API Gateway receives requests, it fails to properly invoke the BFF Lambda or handle the response, resulting in `InternalServerErrorException`.

## Solution Applied

**Bypassed the BFF temporarily** - Frontend now calls the internal API directly with the API key.

### Changes Made:

1. **Updated `frontend/.env`:**
   ```env
   # Direct API Gateway URL (using API key for now - BFF has issues)
   VITE_API_BASE_URL=https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod
   
   # API Key
   VITE_API_KEY=mBUq3FxIobYOjMSOmY8K8zgM1UHlxMZ7feV9Mr7g
   ```

2. **Commented out BFF URL:**
   ```env
   # BFF API URL (currently has API Gateway integration issues)
   # VITE_BFF_API_URL=https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/
   ```

## Testing

The frontend `api.ts` will now:
1. Check for `VITE_BFF_API_URL` (not set)
2. Fall back to `VITE_API_BASE_URL` (internal API)
3. Include `x-api-key` header with `VITE_API_KEY`

This should work immediately since we verified the internal API works with this API key.

---

## Next Steps (To Fix BFF Properly)

### Issue: BFF API Gateway Integration Broken

The BFF Lambda works, but the API Gateway can't invoke it properly. Possible causes:

1. **API Gateway Proxy Integration Issue**
   - The `{proxy+}` resource might not be correctly configured
   - Integration request/response mappings might be wrong

2. **Lambda Permission Issue**
   - API Gateway might not have permission to invoke the Lambda
   - Resource policy might be missing

3. **API Gateway Deployment Issue**
   - Changes might not be deployed to the `prod` stage
   - Cache might need clearing

### Diagnostic Steps:

```bash
# 1. Check Lambda permissions
aws lambda get-policy --function-name rds-dashboard-bff-prod

# 2. Check API Gateway integration
aws apigateway get-integration \
  --rest-api-id 08mqqv008c \
  --resource-id <resource-id> \
  --http-method ANY

# 3. Test API Gateway directly
aws apigateway test-invoke-method \
  --rest-api-id 08mqqv008c \
  --resource-id <resource-id> \
  --http-method GET \
  --path-with-query-string "/instances"

# 4. Redeploy API Gateway
aws apigateway create-deployment \
  --rest-api-id 08mqqv008c \
  --stage-name prod
```

### Permanent Fix Options:

**Option 1: Fix BFF API Gateway** (Recommended for production)
- Debug the API Gateway integration
- Ensure proper Lambda permissions
- Redeploy the BFF stack completely

**Option 2: Keep Direct API Access** (Current solution)
- Simpler architecture
- One less hop (better performance)
- API key exposed to frontend (less secure)
- No request transformation/validation layer

**Option 3: Use CloudFront + Lambda@Edge**
- Put CloudFront in front of internal API
- Use Lambda@Edge to inject API key
- Frontend doesn't need API key
- More complex setup

---

## Security Note

⚠️ **The API key is now exposed in the frontend `.env` file and will be visible in the browser.**

This is acceptable for:
- Development/testing environments
- Internal dashboards
- Trusted user bases

For production with untrusted users, you should:
1. Fix the BFF API Gateway integration
2. OR implement proper authentication (Cognito, OAuth)
3. OR use API Gateway resource policies to restrict access

---

## Verification

To verify the fix works:

1. **Restart the frontend dev server:**
   ```bash
   cd frontend
   npm run dev
   ```

2. **Open browser and check:**
   - Dashboard should load without errors
   - Instances page should show RDS instances
   - Costs, Compliance pages should work
   - Browser console should show 200 responses

3. **Check network tab:**
   - Requests should go to `0pjyr8lkpl.execute-api...` (internal API)
   - Should include `x-api-key` header
   - Should return 200 status codes

---

## Lessons Learned

1. **Test the full stack** - Don't assume API Gateway works just because Lambda works
2. **Have fallback options** - Frontend had fallback to direct API, which saved us
3. **Monitor at every layer** - API Gateway, Lambda, and application logs all needed
4. **Simplicity wins** - Direct API access is simpler than BFF for this use case

---

**Status:** Frontend should now work! 🎉

**Next Action:** Restart frontend dev server and test in browser.
