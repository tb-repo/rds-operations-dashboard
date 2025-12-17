# Quick Fix Steps - Cognito Authentication

## The Problem
The Cognito domain URL was incomplete, causing authentication to fail with malformed URLs.

## The Solution
✅ Fixed the Cognito domain in `.env` file  
✅ Added CloudFront callback URLs to Cognito  
✅ Created production environment file  

## What You Need to Do Now

### For Local Development (localhost:3000)

1. **Stop your dev server** (if running)
   ```powershell
   # Press Ctrl+C in the terminal running the dev server
   ```

2. **Restart the dev server**
   ```powershell
   cd frontend
   npm run dev
   ```

3. **Test the login**
   - Navigate to `http://localhost:3000`
   - Click "Login"
   - You should now see the correct Cognito URL:
     ```
     https://rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com/oauth2/authorize?...
     ```

### For CloudFront Production

1. **Build the frontend with production config**
   ```powershell
   cd frontend
   npm run build
   ```
   This automatically uses `.env.production` which has the CloudFront URLs

2. **Deploy to S3**
   ```powershell
   cd ..
   ./scripts/deploy-frontend.ps1
   ```

3. **Test on CloudFront**
   - Navigate to `https://d2qvaswtmn22om.cloudfront.net`
   - Click "Login"
   - Should redirect to Cognito and back successfully

## Verify the Fix

Run this to check configuration:
```powershell
./test-cognito-config.ps1
```

## What Changed

| File | Change |
|------|--------|
| `frontend/.env` | Fixed `VITE_COGNITO_DOMAIN` to include full domain |
| `frontend/.env.production` | Created with CloudFront URLs |
| Cognito User Pool Client | Added CloudFront callback URLs |

## Expected Behavior

### Before Fix ❌
```
https://rds-dashboard-auth-876595225096/oauth2/authorize?...
```
Result: DNS error, page not found

### After Fix ✅
```
https://rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com/oauth2/authorize?...
```
Result: Cognito login page loads correctly

## Troubleshooting

**Still seeing the old URL?**
- Clear browser cache
- Hard refresh (Ctrl+Shift+R)
- Restart dev server

**Getting CORS errors?**
- Check that callback URL matches exactly
- Verify you're using the correct environment file

**Token exchange failing?**
- Check browser console for PKCE errors
- Verify the state parameter is being passed correctly

## Status
🎉 **READY TO TEST** - Just restart your dev server!
