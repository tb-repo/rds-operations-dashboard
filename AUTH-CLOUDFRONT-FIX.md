# Authentication & API URL Fixes - CloudFront & Local

## Issues Fixed

### Issue 1: CloudFront Redirect to Wrong Cognito Domain
**Problem**: When accessing via CloudFront, the app redirected to `https://rds-dashboard-auth-876595225096/oauth2/authorize` (missing full domain)
**Error**: `net::ERR_NAME_NOT_RESOLVED`

**Root Cause**: The `.env.production` file had hardcoded redirect URIs pointing to CloudFront, which prevented dynamic origin detection.

**Fix**: 
- Updated `.env.production` to remove hardcoded `VITE_COGNITO_REDIRECT_URI` and `VITE_COGNITO_LOGOUT_URI`
- App now uses `window.location.origin` dynamically at runtime
- This allows the same build to work on both localhost and CloudFront

### Issue 2: Wrong API URL in Local Development
**Problem**: Dashboard was calling `https://144nff7etd.execute-api.ap-southeast-1.amazonaws.com/prod/instances` instead of the BFF API
**Error**: API calls failing

**Root Cause**: Both `.env` and `.env.production` had the wrong BFF API URL

**Fix**:
- Updated `VITE_BFF_API_URL` in both `.env` and `.env.production` to correct BFF URL: `https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod`

## Files Modified

### 1. `frontend/.env`
```env
# BFF API URL - CORRECTED
VITE_BFF_API_URL=https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod

# Cognito domain - ALREADY CORRECT
VITE_COGNITO_DOMAIN=rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com

# Redirect URIs - NOW DYNAMIC (commented out)
# VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
# VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
```

### 2. `frontend/.env.production`
```env
# BFF API URL - CORRECTED
VITE_BFF_API_URL=https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod

# Cognito domain - ALREADY CORRECT
VITE_COGNITO_DOMAIN=rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com

# Redirect URIs - NOW DYNAMIC (commented out)
# VITE_COGNITO_REDIRECT_URI=https://d2qvaswtmn22om.cloudfront.net/callback
# VITE_COGNITO_LOGOUT_URI=https://d2qvaswtmn22om.cloudfront.net/
```

## How Dynamic Redirect URIs Work

The `App.tsx` file already had the correct logic:

```typescript
const cognitoService = new CognitoService({
  // ... other config
  redirectUri: import.meta.env.VITE_COGNITO_REDIRECT_URI || window.location.origin + '/callback',
  logoutUri: import.meta.env.VITE_COGNITO_LOGOUT_URI || window.location.origin,
})
```

By commenting out the environment variables, the fallback `window.location.origin` is used, which:
- On CloudFront: Uses `https://d2qvaswtmn22om.cloudfront.net`
- On localhost: Uses `http://localhost:3000` or `http://localhost:5173`

## Cognito Configuration

The Cognito User Pool Client is already configured with all necessary callback URLs:

**Callback URLs:**
- `http://localhost:3000/callback`
- `http://localhost:5173/callback`
- `https://d2qvaswtmn22om.cloudfront.net/callback`

**Logout URLs:**
- `http://localhost:3000/`
- `http://localhost:5173/`
- `https://d2qvaswtmn22om.cloudfront.net/`

## Deployment Steps Completed

1. ✅ Updated `.env` file with correct BFF URL and dynamic redirects
2. ✅ Updated `.env.production` file with correct BFF URL and dynamic redirects
3. ✅ Rebuilt frontend: `npm run build`
4. ✅ Deployed to S3: `aws s3 sync ./dist s3://rds-dashboard-frontend-876595225096/ --delete`
5. ✅ Invalidated CloudFront cache: `aws cloudfront create-invalidation --distribution-id E25MCU6AMR4FOK --paths "/*"`

## Testing Instructions

### CloudFront Testing
1. Open: `https://d2qvaswtmn22om.cloudfront.net`
2. Click "Login"
3. Should redirect to: `https://rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com/oauth2/authorize`
4. Login with: `admin@example.com` / `AdminPass123!`
5. Should redirect back to: `https://d2qvaswtmn22om.cloudfront.net/callback`
6. Dashboard should load data from BFF API

### Local Testing
1. Run: `npm run dev` (in frontend folder)
2. Open: `http://localhost:3000`
3. Click "Login"
4. Should redirect to Cognito with `redirect_uri=http://localhost:3000/callback`
5. Login and verify dashboard loads data

## Expected Behavior

✅ **CloudFront**: Login redirects to proper Cognito domain with CloudFront callback URL
✅ **Local**: Login redirects to proper Cognito domain with localhost callback URL
✅ **API Calls**: All API calls go to BFF at `https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod`
✅ **Single Build**: Same production build works on both CloudFront and localhost (for testing)

## Cache Invalidation

CloudFront cache invalidation is in progress. It may take 5-10 minutes for changes to propagate globally.

**Invalidation ID**: `I4I3ZXGFF64M1WSZV6NSL2IC88`
**Status**: InProgress
**Created**: 2025-12-07T16:11:04.636000+00:00

## Verification

After cache invalidation completes, test both scenarios:
1. Access via CloudFront and verify login works
2. Access via localhost and verify login works
3. Verify dashboard loads data from correct BFF API

Both should now work correctly with the same build!
