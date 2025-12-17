# 404 Routing Errors - Fix Summary

**Date**: December 7, 2025  
**Status**: ⚠️ IN PROGRESS  

## Issues Found

### 1. Users Endpoint - 404 Error
**Problem**: Frontend calling `/users` but BFF expects `/api/users`

**Fixed in**:
- `frontend/src/pages/UserManagement.tsx`
  - Changed `/users` → `/api/users`
  - Changed `/users/${userId}/groups` → `/api/users/${userId}/groups`
  - Changed `/users/${userId}/groups/${role}` → `/api/users/${userId}/groups/${role}`

### 2. Approvals Endpoint - 404 Error
**Problem**: Frontend calling `/approvals` but BFF expects `/api/approvals`

**Fixed in**:
- `frontend/src/pages/ApprovalsDashboard.tsx`
  - Changed all `/approvals` → `/api/approvals` (4 occurrences)

### 3. Health Endpoint - 404 Error
**Problem**: Frontend calling `/api/health` and `/api/health/:instanceId` but BFF only had `/health`

**Fixed in**:
- `bff/src/index.ts`
  - Added `/api/health` endpoint (mirrors `/health`)
  - Added `/api/health/:instanceId` endpoint for instance-specific health metrics

### 4. Operations Endpoint - 500 Error
**Problem**: Operations endpoint exists but returns 500 error

**Status**: Needs investigation - likely backend Lambda issue

## Deployment Status

✅ Frontend - Deployed to S3 and CloudFront invalidated  
⚠️ BFF - Needs Docker to be running for deployment  

## Next Steps

1. **Start Docker Desktop**
2. **Deploy BFF**:
   ```powershell
   cd infrastructure
   npx cdk deploy RDSDashboard-BFF --require-approval never
   ```

3. **Test endpoints**:
   - Users: https://d2qvaswtmn22om.cloudfront.net/users
   - Approvals: https://d2qvaswtmn22om.cloudfront.net/approvals
   - Health: Check instance detail pages

4. **Investigate Operations 500 error**:
   - Check BFF logs
   - Check operations Lambda logs
   - Verify operations Lambda has shared module

## Root Cause

**Inconsistent routing conventions** between frontend and BFF:
- Some endpoints used `/api` prefix, others didn't
- Frontend assumed all endpoints had `/api` prefix
- BFF had mixed conventions

## Prevention

- Document API routing conventions
- Use consistent `/api` prefix for all authenticated endpoints
- Keep `/health` without prefix for load balancer health checks
- Add integration tests that verify routing

## Files Changed

1. `frontend/src/pages/UserManagement.tsx` - Fixed 3 endpoints
2. `frontend/src/pages/ApprovalsDashboard.tsx` - Fixed 4 endpoints  
3. `bff/src/index.ts` - Added 2 health endpoints

## Testing Checklist

After BFF deployment:
- [ ] Users page loads without 404
- [ ] Can view user list
- [ ] Can add/remove roles
- [ ] Approvals page loads without 404
- [ ] Can view pending approvals
- [ ] Health metrics display on instance detail page
- [ ] Operations (start/stop) work without 500 error
