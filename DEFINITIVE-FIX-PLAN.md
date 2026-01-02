# DEFINITIVE FIX PLAN - Root Cause Resolution

**Date:** December 22, 2025  
**Issue:** 500 Internal Server Error on `/api/errors/statistics`  
**Root Cause:** Overcomplicated architecture with 2 BFF functions

## Root Cause Analysis - COMPLETE

### The Real Problem
We have **2 BFF functions** that are causing confusion and authentication issues:

1. **`rds-dashboard-bff` (Original)**
   - Type: Container Image
   - Backend: `https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod`
   - API Key: `OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX` (from Secrets Manager)
   - Status: **Full BFF but authentication failing**

2. **`rds-dashboard-bff-prod` (Created Later)**
   - Type: ZIP Package  
   - Backend: `https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod`
   - API Key: Same as above
   - Status: **Limited function, only error endpoints**

### Why Both Are Failing
- **Backend 1** (`qxx9whmsd4`): Expects API key but BFF authentication is broken
- **Backend 2** (`0pjyr8lkpl`): Returns 403 Forbidden even with correct API key
- **API Gateway**: Keeps switching between the two, causing inconsistent behavior

## The Definitive Solution

### Option 1: Fix Original BFF (RECOMMENDED)
1. **Keep:** `rds-dashboard-bff` (original full BFF)
2. **Delete:** `rds-dashboard-bff-prod` (redundant limited function)
3. **Fix:** Authentication issue in original BFF
4. **Result:** Single BFF handling all endpoints properly

### Option 2: Simplify to Working Backend
1. **Update:** Original BFF to point to working backend
2. **Delete:** Prod BFF function
3. **Add:** Error endpoint handling to original BFF
4. **Result:** Single BFF with all functionality

## Immediate Action Plan

### Step 1: Test Direct Backend Access
```bash
# Test backend 1 with API key
curl -H "x-api-key: OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX" \
     https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances

# Test backend 2 with API key  
curl -H "x-api-key: OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX" \
     https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances
```

### Step 2: Fix BFF Authentication
- Check BFF code for API key usage
- Ensure proper header forwarding
- Fix any authentication middleware issues

### Step 3: Consolidate to Single BFF
- Delete redundant BFF function
- Update API Gateway to point to working BFF
- Add error endpoint handling if needed

### Step 4: Test End-to-End
- Verify all endpoints work through single BFF
- Test error statistics with proper fallback
- Confirm dashboard loads completely

## Why This Will Work

### Current Issues
- ❌ Two BFF functions causing confusion
- ❌ Different backends with different authentication
- ❌ API Gateway switching between functions
- ❌ Incomplete functionality in prod BFF

### After Fix
- ✅ Single BFF function handling all requests
- ✅ Consistent authentication to one backend
- ✅ API Gateway pointing to one function
- ✅ Complete functionality including error handling

## Benefits of Single BFF Architecture

1. **Simplicity:** One function to maintain and debug
2. **Consistency:** All requests go through same authentication
3. **Reliability:** No confusion about which function handles what
4. **Maintainability:** Single codebase for all BFF functionality
5. **Performance:** No switching between different functions

## Implementation Priority

### HIGH PRIORITY (Fix Now)
1. Identify which backend actually works
2. Fix authentication in original BFF
3. Point API Gateway to working BFF
4. Delete redundant BFF function

### MEDIUM PRIORITY (After Fix)
1. Add comprehensive error handling
2. Implement proper fallback for error endpoints
3. Add monitoring and alerting
4. Document the simplified architecture

## Success Criteria

### ✅ Dashboard Working
- All pages load without errors
- Instance, health, costs, compliance data displays
- Error monitoring shows graceful fallback
- No 500 Internal Server Errors

### ✅ Single BFF Function
- Only one BFF function exists
- API Gateway points to single function
- All endpoints work through same function
- Consistent authentication and error handling

### ✅ Maintainable Architecture
- Clear documentation of BFF functionality
- Single source of truth for API routing
- Simplified deployment and debugging
- No redundant or conflicting functions

---

**Next Action:** Execute Step 1 to determine which backend works, then implement the fix immediately.