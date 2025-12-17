# API Path Fix - BFF Routes

## Issue

Dashboard was showing error: **"Failed to load dashboard data - The requested resource was not found"**

## Root Cause

The frontend was calling API endpoints without the `/api` prefix (e.g., `/instances`), but the BFF expects all routes to be under `/api/*` (e.g., `/api/instances`).

**BFF Route Configuration** (`bff/src/index.ts`):
```typescript
// All authenticated routes are under /api
app.use('/api', authMiddleware.authenticate())

app.get('/api/instances', ...)
app.get('/api/costs', ...)
app.get('/api/compliance', ...)
// etc.
```

**Frontend API Calls** (before fix):
```typescript
apiClient.get('/instances')  // ❌ 404 Not Found
apiClient.get('/costs')      // ❌ 404 Not Found
```

## Fix Applied

Updated all API calls in `frontend/src/lib/api.ts` to include the `/api` prefix:

### Changes Made:

```typescript
// Instances
- `/instances` → `/api/instances`
- `/instances/${id}` → `/api/instances/${id}`

// Health & Alerts
- `/health` → `/api/health`
- `/health/${id}` → `/api/health/${id}`

// Costs
- `/costs` → `/api/costs`

// Compliance
- `/compliance` → `/api/compliance`
- `/compliance/${id}` → `/api/compliance/${id}`

// Operations
- `/operations` → `/api/operations`

// CloudOps
- `/cloudops` → `/api/cloudops`
- `/cloudops/history` → `/api/cloudops/history`
```

## Deployment

1. ✅ Updated `frontend/src/lib/api.ts` with `/api` prefix for all routes
2. ✅ Rebuilt frontend: `npm run build`
3. ✅ Deployed to S3: `aws s3 sync ./dist s3://rds-dashboard-frontend-876595225096/ --delete`
4. ✅ Invalidated CloudFront cache: `aws cloudfront create-invalidation --distribution-id E25MCU6AMR4FOK --paths "/*"`

**Invalidation ID**: `IILMHE6XFY5XT32YL33EEC2TN`
**Status**: InProgress
**Created**: 2025-12-07T16:17:58.594000+00:00

## Testing

After CloudFront cache invalidation completes (5-10 minutes):

1. **CloudFront**: Open `https://d2qvaswtmn22om.cloudfront.net`
2. **Login**: Use `admin@example.com` / `AdminPass123!`
3. **Dashboard**: Should now load instances and data successfully

### Expected API Calls:
- `GET https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances`
- `GET https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/health`
- `GET https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/costs`
- `GET https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/compliance`

All requests will include the `Authorization: Bearer <token>` header automatically.

## Summary of All Fixes

This completes the authentication and API integration fixes:

1. ✅ **Cognito Domain**: Fixed full domain URL in environment files
2. ✅ **Dynamic Redirect URIs**: Removed hardcoded URIs to use `window.location.origin`
3. ✅ **BFF API URL**: Updated to correct BFF endpoint (`km9ww1hh3k`)
4. ✅ **API Path Prefix**: Added `/api` prefix to all frontend API calls

The dashboard should now work correctly on both CloudFront and localhost!
