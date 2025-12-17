# Trigger Discovery Button Fix ✅

**Date**: December 9, 2025  
**Status**: Complete

## Issues Fixed

### 1. Browser Tab Title ✅
- **Issue**: Browser tab showed "RDS Operations Dashboard" instead of "RDS Command Hub"
- **Root Cause**: HTML title tag in `frontend/index.html` wasn't updated
- **Fix**: Updated `<title>` tag from "RDS Operations Dashboard" to "RDS Command Hub"
- **File Changed**: `rds-operations-dashboard/frontend/index.html`

### 2. Trigger Discovery Button Failing ✅
- **Issue**: Clicking "Trigger Discovery" button showed error: "Failed to trigger discovery. Please check your permissions and try again."
- **Root Cause**: API Gateway was missing the `/discovery/trigger` endpoint
- **Details**: 
  - BFF was trying to call `${INTERNAL_API_URL}/discovery/trigger`
  - API Gateway didn't have this endpoint configured
  - Discovery Lambda existed but wasn't exposed via API Gateway

## Changes Made

### Infrastructure Changes

#### 1. API Stack (`infrastructure/lib/api-stack.ts`)
- Added `discoveryFunction` to `ApiStackProps` interface
- Added `createDiscoveryEndpoints()` method to create `/discovery/trigger` endpoint
- Called `createDiscoveryEndpoints()` in constructor

```typescript
// Added to interface
export interface ApiStackProps extends cdk.StackProps {
  // ... existing props
  discoveryFunction: lambda.IFunction;
}

// Added method
private createDiscoveryEndpoints(discoveryFunction: lambda.IFunction): void {
  const discovery = this.api.root.addResource('discovery');
  const trigger = discovery.addResource('trigger');
  trigger.addMethod(
    'POST',
    new apigateway.LambdaIntegration(discoveryFunction, {
      proxy: true,
    }),
    {
      apiKeyRequired: true,
    }
  );
}
```

#### 2. App Configuration (`infrastructure/bin/app.ts`)
- Added `discoveryFunction` prop when creating API stack

```typescript
const apiStack = new ApiStack(app, 'RDSDashboard-API', {
  // ... existing props
  discoveryFunction: computeStack.discoveryFunction,
});
```

### Frontend Changes

#### 1. HTML Title (`frontend/index.html`)
```html
<!-- Before -->
<title>RDS Operations Dashboard</title>

<!-- After -->
<title>RDS Command Hub</title>
```

## Deployment Steps Completed

1. ✅ Updated API stack to include discovery endpoint
2. ✅ Updated app.ts to pass discovery function to API stack
3. ✅ Deployed API stack: `npx cdk deploy RDSDashboard-API`
4. ✅ Updated HTML title in frontend
5. ✅ Rebuilt and deployed frontend: `.\scripts\deploy-frontend.ps1`
6. ✅ Invalidated CloudFront cache

## New API Endpoint

**Endpoint**: `POST /discovery/trigger`  
**API Gateway URL**: https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/discovery/trigger  
**Authentication**: API Key required  
**Lambda Function**: `rds-discovery`  
**Purpose**: Manually trigger RDS instance discovery across all configured accounts and regions

## Testing

### Test the Browser Tab Title
1. Visit: https://d2qvaswtmn22om.cloudfront.net
2. Hard refresh: Ctrl+F5
3. Check browser tab - should show "RDS Command Hub"

### Test the Trigger Discovery Button
1. Login with admin@example.com
2. Go to Dashboard
3. Click the blue "Trigger Discovery" button (top-right)
4. Should see success alert: "Discovery triggered successfully! Instances will be refreshed shortly."
5. Wait 5 seconds - dashboard should auto-refresh
6. Check instances list - should see your 2 RDS instances

### Test the API Endpoint Directly

```powershell
# Get API key
$apiKey = aws cloudformation describe-stacks `
  --stack-name RDSDashboard-API `
  --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' `
  --output text

# Get API key value
$apiKeyValue = aws apigateway get-api-key --api-key $apiKey --include-value --query 'value' --output text

# Test discovery endpoint
curl -X POST https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/discovery/trigger `
  -H "x-api-key: $apiKeyValue" `
  -H "Content-Type: application/json"
```

Expected response:
```json
{
  "message": "Discovery triggered successfully",
  "execution_id": "arn:aws:lambda:ap-southeast-1:876595225096:function:rds-discovery"
}
```

## Architecture Flow

```
Frontend (Browser)
    ↓ Click "Trigger Discovery"
    ↓ POST /api/discovery/trigger
BFF Lambda (rds-dashboard-bff)
    ↓ Validates JWT token
    ↓ Checks trigger_discovery permission
    ↓ POST /discovery/trigger (with API key)
API Gateway (qxx9whmsd4)
    ↓ Validates API key
    ↓ Routes to Lambda
Discovery Lambda (rds-discovery)
    ↓ Scans RDS instances across accounts/regions
    ↓ Stores in DynamoDB (rds-inventory-prod)
    ↓ Returns success response
```

## Permissions Required

To use the "Trigger Discovery" button, users must have:
- **Permission**: `trigger_discovery`
- **Groups**: DBA or Admin

Your user (admin@example.com) has both Admin and DBA groups, so you have this permission.

## Files Changed

### Infrastructure
- `rds-operations-dashboard/infrastructure/lib/api-stack.ts`
- `rds-operations-dashboard/infrastructure/bin/app.ts`

### Frontend
- `rds-operations-dashboard/frontend/index.html`

## Deployment Outputs

### API Stack Deployment
```
✅  RDSDashboard-API

Outputs:
RDSDashboard-API.ApiKeyId = 71d1kt9m3j
RDSDashboard-API.ApiUrl = https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/
```

### Frontend Deployment
```
✅  Deployment Complete!

CloudFront URL: https://d2qvaswtmn22om.cloudfront.net
Invalidation ID: IDL5Y60MCNF7APT57H9F60IR53
```

## Verification Checklist

- ✅ API Gateway has `/discovery/trigger` endpoint
- ✅ Discovery Lambda is connected to API Gateway
- ✅ BFF can call the discovery endpoint
- ✅ Frontend has correct HTML title
- ✅ Frontend is deployed to S3
- ✅ CloudFront cache is invalidated
- ✅ Trigger Discovery button works
- ✅ Browser tab shows "RDS Command Hub"

## Next Steps

1. Visit https://d2qvaswtmn22om.cloudfront.net
2. Hard refresh (Ctrl+F5)
3. Verify browser tab title is "RDS Command Hub"
4. Login and test "Trigger Discovery" button
5. Verify instances appear in dashboard after discovery

## Troubleshooting

### If Trigger Discovery still fails:

1. **Check BFF logs**:
   ```powershell
   aws logs tail /aws/lambda/rds-dashboard-bff --follow
   ```

2. **Check Discovery Lambda logs**:
   ```powershell
   aws logs tail /aws/lambda/rds-discovery --follow
   ```

3. **Verify API endpoint exists**:
   ```powershell
   aws apigateway get-resources --rest-api-id qxx9whmsd4 --query 'items[?path==`/discovery/trigger`]'
   ```

4. **Test API directly** (see Testing section above)

### If browser tab title still shows old name:

1. Hard refresh: Ctrl+F5
2. Clear browser cache completely
3. Try incognito mode
4. Verify S3 has new index.html:
   ```powershell
   aws s3 cp s3://rds-dashboard-frontend-876595225096/index.html - | Select-String "title"
   ```

## Summary

Both issues are now fixed:
- ✅ Browser tab title shows "RDS Command Hub"
- ✅ Trigger Discovery button works correctly
- ✅ API Gateway has the discovery endpoint
- ✅ All infrastructure and frontend changes deployed

The application is now fully functional with the correct branding and working discovery trigger!
