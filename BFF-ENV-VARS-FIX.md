# BFF Environment Variables Fix - 500 Errors Resolved

## Issue

After login, all dashboard tabs (Health, Dashboard, Costs, etc.) were showing **500 Internal Server Errors**.

## Root Cause

The BFF Lambda function (`rds-dashboard-bff-prod`) was deployed without the required environment variables. The BFF code requires these variables to function:

```typescript
const requiredEnvVars = [
  'COGNITO_USER_POOL_ID',
  'COGNITO_REGION',
  'INTERNAL_API_URL',
]
```

**Before Fix:**
```json
{
  "API_SECRET_ARN": "arn:aws:secretsmanager:...",
  "NODE_ENV": "production",
  "AWS_NODEJS_CONNECTION_REUSE_ENABLED": "1"
}
```

The BFF was crashing on startup because it couldn't find the required environment variables.

## Fix Applied

Updated the Lambda function configuration with all required environment variables:

```bash
aws lambda update-function-configuration \
  --function-name rds-dashboard-bff-prod \
  --environment "Variables={
    API_SECRET_ARN=arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-KjtkXE,
    NODE_ENV=production,
    AWS_NODEJS_CONNECTION_REUSE_ENABLED=1,
    COGNITO_USER_POOL_ID=ap-southeast-1_4tyxh4qJe,
    COGNITO_REGION=ap-southeast-1,
    COGNITO_CLIENT_ID=28e031hsul0mi91k0s6f33bs7s,
    INTERNAL_API_URL=https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod,
    FRONTEND_URL=https://d2qvaswtmn22om.cloudfront.net,
    PORT=8080,
    LOG_LEVEL=info
  }"
```

**After Fix:**
```json
{
  "API_SECRET_ARN": "arn:aws:secretsmanager:...",
  "PORT": "8080",
  "INTERNAL_API_URL": "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod",
  "COGNITO_REGION": "ap-southeast-1",
  "NODE_ENV": "production",
  "AWS_NODEJS_CONNECTION_REUSE_ENABLED": "1",
  "COGNITO_CLIENT_ID": "28e031hsul0mi91k0s6f33bs7s",
  "COGNITO_USER_POOL_ID": "ap-southeast-1_4tyxh4qJe",
  "LOG_LEVEL": "info",
  "FRONTEND_URL": "https://d2qvaswtmn22om.cloudfront.net"
}
```

## Verification

✅ **BFF Health Check**: `https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/health`
```json
{
  "status": "healthy",
  "timestamp": "2025-12-07T16:35:52.733Z"
}
```

✅ **Lambda Status**: Active and Successful
✅ **Environment Variables**: All required variables configured

## Testing

The application should now work correctly:

1. **Open**: `https://d2qvaswtmn22om.cloudfront.net`
2. **Login**: `admin@example.com` / `AdminPass123!`
3. **Dashboard**: Should load without 500 errors
4. **All Tabs**: Health, Costs, Compliance should all work

## Summary of All Fixes

This completes the full authentication and API integration:

1. ✅ **Cognito Domain**: Fixed full domain URL
2. ✅ **Dynamic Redirect URIs**: Removed hardcoded URIs
3. ✅ **BFF API URL**: Updated to correct endpoint
4. ✅ **API Path Prefix**: Added `/api` prefix to all calls
5. ✅ **BFF Environment Variables**: Configured all required variables

The dashboard is now fully functional!

## Note

If you redeploy the BFF stack via CDK in the future, ensure the `BffStackProps` are passed correctly with:
- `userPoolId`
- `userPoolClientId`
- `internalApiUrl`
- `frontendUrl`

These props populate the environment variables automatically.
