# RDS Operations Dashboard - Testing URLs

## Frontend Application
**URL:** https://d2qvaswtmn22om.cloudfront.net

This is your main application URL. Open this in your browser to test the dashboard.

## What to Test

### 1. Login
- Navigate to the URL above
- You should be redirected to the Cognito login page
- Login with your credentials

### 2. Dashboard Pages
After login, test these pages:
- **Dashboard** - Main overview page
- **Instances** - List of RDS instances
- **Compliance** - Compliance status
- **Costs** - Cost analysis
- **Approvals** - Approval workflow (this was failing before)
- **User Management** - User administration

### 3. Specific Fixes to Verify

#### Fixed: Approvals Dashboard (500 Error)
- Navigate to the Approvals page
- Should now load without 500 errors
- You should see approval requests (if any exist)

#### Fixed: Health Metrics (404 Error)
- Click on any instance
- Health metrics should now load
- No more 404 errors for `/api/health/:instanceId`

#### Fixed: Operations (500 Error)
- Try to execute an operation on an instance
- Should work without 500 errors

## API Endpoints (for reference)

### BFF API
**Base URL:** https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod

**Endpoints:**
- `GET /health` - Health check (no auth)
- `GET /api/health/:instanceId` - Instance health metrics
- `GET /api/instances` - List instances
- `GET /api/approvals` - List approval requests
- `POST /api/approvals` - Create/manage approvals
- `POST /api/operations` - Execute operations

### Internal API
**Base URL:** https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod

This is the backend API that the BFF calls (not directly accessible from frontend).

## Troubleshooting

If you still see errors:

1. **Clear browser cache** - The frontend may have cached old API responses
2. **Check browser console** - Look for any remaining errors
3. **Check CloudWatch logs**:
   ```powershell
   # BFF logs
   aws logs tail /aws/lambda/rds-dashboard-bff --follow
   
   # Backend API logs
   aws logs tail /aws/lambda/rds-operations --follow
   ```

## What Was Fixed

### Issue 1: Empty API Key
- **Problem:** BFF was sending empty API keys to backend
- **Fix:** Cached environment variables at startup
- **Result:** All backend API calls now include proper authentication

### Issue 2: Double Slashes in URLs
- **Problem:** URLs had `/prod//instances` instead of `/prod/instances`
- **Fix:** Removed trailing slash from INTERNAL_API_URL
- **Result:** Clean URL paths

### Issue 3: Missing Routes
- **Problem:** Some endpoints weren't properly configured
- **Fix:** All routes now properly registered in BFF
- **Result:** All endpoints accessible

## Expected Behavior

✅ Login works
✅ Dashboard loads
✅ Instances list displays
✅ Approvals page loads (no 500 error)
✅ Health metrics display (no 404 error)
✅ Operations can be executed (no 500 error)
✅ All API calls succeed with proper authentication

## Test Credentials

If you need to create a test user:
```powershell
cd rds-operations-dashboard
.\scripts\create-cognito-user.ps1
```

## Support

If you encounter any issues:
1. Check the browser console for errors
2. Check CloudWatch logs for the BFF Lambda
3. Verify the BFF environment variables are set correctly
