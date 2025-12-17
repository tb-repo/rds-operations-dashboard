# Cognito Configuration Fix - Complete

## Issue Identified
The Cognito domain URL in the frontend `.env` file was incomplete, causing authentication failures:
- **Incorrect**: `rds-dashboard-auth-876595225096`
- **Correct**: `rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com`

This caused the frontend to generate malformed OAuth URLs like:
```
https://rds-dashboard-auth-876595225096/oauth2/authorize?...
```

Instead of the correct:
```
https://rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com/oauth2/authorize?...
```

## Changes Made

### 1. Fixed Frontend Environment Configuration

**File**: `frontend/.env`
- Updated `VITE_COGNITO_DOMAIN` to include full domain suffix
- Added comments for CloudFront production URLs

**File**: `frontend/.env.production` (NEW)
- Created production environment file with CloudFront URLs
- Automatically used when running `npm run build`

### 2. Updated Cognito User Pool Client

Added CloudFront callback URLs to Cognito configuration:

**Callback URLs**:
- ✅ `http://localhost:3000/callback` (local dev)
- ✅ `http://localhost:5173/callback` (Vite dev server)
- ✅ `https://d2qvaswtmn22om.cloudfront.net/callback` (production)

**Logout URLs**:
- ✅ `http://localhost:3000/` (local dev)
- ✅ `http://localhost:5173/` (Vite dev server)
- ✅ `https://d2qvaswtmn22om.cloudfront.net/` (production)

### 3. Created Test Script

**File**: `test-cognito-config.ps1`
- Validates Cognito configuration
- Shows all callback URLs and OAuth settings
- Generates test authorization URLs

## Testing

### Local Development
```powershell
cd frontend
npm run dev
# Navigate to http://localhost:3000
# Click login - should redirect to correct Cognito URL
```

### CloudFront Production
```powershell
cd frontend
npm run build  # Uses .env.production automatically
# Deploy to S3/CloudFront
# Navigate to https://d2qvaswtmn22om.cloudfront.net
# Click login - should redirect to correct Cognito URL
```

### Verify Configuration
```powershell
./test-cognito-config.ps1
```

## Expected Behavior

### Login Flow
1. User clicks "Login" button
2. Frontend redirects to:
   ```
   https://rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com/oauth2/authorize?
     client_id=28e031hsul0mi91k0s6f33bs7s&
     response_type=code&
     scope=openid+email+profile&
     redirect_uri=<callback_url>&
     code_challenge=<pkce_challenge>&
     code_challenge_method=S256&
     state=<state>
   ```
3. User enters credentials on Cognito Hosted UI
4. Cognito redirects back to `<callback_url>` with authorization code
5. Frontend exchanges code for tokens using PKCE
6. User is authenticated

### Callback URLs by Environment
- **Local Dev**: `http://localhost:3000/callback`
- **Vite Dev**: `http://localhost:5173/callback`
- **Production**: `https://d2qvaswtmn22om.cloudfront.net/callback`

## Configuration Summary

| Setting | Value |
|---------|-------|
| User Pool ID | `ap-southeast-1_4tyxh4qJe` |
| Client ID | `28e031hsul0mi91k0s6f33bs7s` |
| Region | `ap-southeast-1` |
| Domain | `rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com` |
| OAuth Flow | Authorization Code with PKCE |
| Scopes | `openid`, `email`, `profile` |

## Next Steps

1. **Test locally**: Restart your dev server and try logging in
2. **Deploy to CloudFront**: Build and deploy the frontend
3. **Test production**: Access via CloudFront URL and verify login works

## Troubleshooting

If you still see issues:

1. **Clear browser cache**: Cognito may have cached the old domain
2. **Check browser console**: Look for CORS or redirect errors
3. **Verify callback URL**: Ensure it matches exactly (including trailing slash)
4. **Check Cognito logs**: CloudWatch logs for the User Pool

## Files Modified

- ✅ `frontend/.env` - Fixed Cognito domain
- ✅ `frontend/.env.production` - Created for CloudFront deployment
- ✅ Cognito User Pool Client - Added CloudFront callback URLs
- ✅ `test-cognito-config.ps1` - Created validation script

## Status

🎉 **READY TO TEST** - Configuration is complete and validated!
