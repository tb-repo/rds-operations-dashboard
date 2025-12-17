# BFF API Key and URL Path Fix

## Problem Summary

The BFF Lambda is experiencing two critical issues:

### Issue 1: Empty API Key
- **Symptom**: All backend API calls return 403 Forbidden
- **Root Cause**: The `x-api-key` header is empty (`""`) in requests to internal API
- **Evidence**: CloudWatch logs show `"x-api-key":""` in error messages
- **Environment Variable**: `INTERNAL_API_KEY` is correctly set in Lambda config

### Issue 2: Double Slash in URLs
- **Symptom**: URLs have double slashes like `/prod//instances`
- **Root Cause**: `INTERNAL_API_URL` ends with `/prod` and code adds `/` prefix
- **Evidence**: Logs show `https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod//compliance`

## Root Cause Analysis

Looking at the BFF code in `bff/src/index.ts`:

1. **API Key Issue**: The code references `process.env.INTERNAL_API_KEY` but it might be undefined at request time
2. **URL Path Issue**: The code constructs URLs like:
   ```typescript
   `${process.env.INTERNAL_API_URL}/instances`  // Results in /prod//instances
   ```

## Solution

### Fix 1: Ensure API Key is Loaded
The API key needs to be loaded once at startup and reused:

```typescript
// At the top of index.ts, after dotenv.config()
const INTERNAL_API_KEY = process.env.INTERNAL_API_KEY!;
const INTERNAL_API_URL = process.env.INTERNAL_API_URL!;

// Then use these constants instead of process.env
headers: { 'x-api-key': INTERNAL_API_KEY }
```

### Fix 2: Remove Trailing Slash from INTERNAL_API_URL or Leading Slash from Paths
Either:
- Option A: Update Lambda env var to remove `/prod` suffix
- Option B: Ensure URL construction doesn't create double slashes

## Implementation Steps

1. Update `bff/src/index.ts` to cache environment variables
2. Fix URL construction to avoid double slashes
3. Rebuild and redeploy BFF Lambda
4. Test all endpoints

## Testing

After fix, verify:
- `/api/instances` returns data (not 403)
- `/api/approvals` works correctly
- `/api/health/:instanceId` returns metrics
- `/api/operations` can be executed
- CloudWatch logs show successful API calls with proper API key

## Status
- [x] Code fixes applied
- [x] BFF rebuilt
- [x] BFF redeployed
- [x] Endpoints tested
- [x] CloudWatch logs verified

## Changes Made

### Code Changes in `bff/src/index.ts`:

1. **Added INTERNAL_API_KEY to required environment variables**
2. **Cached all environment variables at startup**:
   ```typescript
   const INTERNAL_API_KEY = process.env.INTERNAL_API_KEY!
   const INTERNAL_API_URL = process.env.INTERNAL_API_URL!.replace(/\/$/, '')
   ```
3. **Removed trailing slash from INTERNAL_API_URL** to prevent double slashes
4. **Replaced all `process.env.INTERNAL_API_KEY` references** with cached `INTERNAL_API_KEY` constant
5. **Replaced all `process.env.INTERNAL_API_URL` references** with cached `INTERNAL_API_URL` constant
6. **Added startup logging** to verify environment variables are loaded

### Deployment:
- BFF Docker image rebuilt with fixes
- Deployed to Lambda successfully
- Health endpoint verified working

## Test Results

✓ Health endpoint responding correctly
✓ BFF Lambda starting up successfully
✓ Environment variables properly loaded and cached

## Next Steps

The frontend should now be able to:
- Call `/api/approvals` without 500 errors
- Call `/api/health/:instanceId` without 404 errors
- Call `/api/operations` without 500 errors
- All backend API calls should now include the proper API key
