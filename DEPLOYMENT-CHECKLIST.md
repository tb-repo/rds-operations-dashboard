# 🚀 Authentication System Deployment Checklist

**Status:** Ready for deployment  
**Estimated Time:** 15-20 minutes  
**Prerequisites:** AWS CLI configured, CDK bootstrapped

---

## Pre-Deployment Checklist

### ✅ Prerequisites Verification

Run these commands to verify your environment:

```powershell
# Check AWS CLI is installed and configured
aws --version
aws sts get-caller-identity

# Check Node.js and npm
node --version
npm --version

# Check CDK is installed
npx aws-cdk --version

# Verify you're in the right directory
cd rds-operations-dashboard
pwd
```

**Expected Results:**
- AWS CLI version 2.x or higher
- Valid AWS credentials with admin permissions
- Node.js v18 or higher
- CDK v2.x

---

## Deployment Steps

### Step 1: Install Dependencies (2 minutes)

```powershell
# Install infrastructure dependencies
cd infrastructure
npm install

# Install BFF dependencies
cd ../bff
npm install

# Install frontend dependencies
cd ../frontend
npm install

cd ..
```

---

### Step 2: Bootstrap CDK (if not done already)

```powershell
cd infrastructure
npx aws-cdk bootstrap
```

**Note:** Only needed once per AWS account/region.

---

### Step 3: Deploy Auth Stack (5 minutes)

```powershell
# From rds-operations-dashboard directory
.\scripts\deploy-auth.ps1 -AdminEmail "your-email@company.com" -Environment prod
```

**What to expect:**
1. CDK will show you the resources to be created
2. Cognito User Pool will be created
3. User groups (Admin, DBA, ReadOnly) will be created
4. Your admin user will be created
5. You'll receive a temporary password

**⚠️ IMPORTANT:** Save the output! You'll need:
- User Pool ID
- Client ID
- Domain name
- Temporary password

**Example Output:**
```
========================================
Cognito Configuration
========================================
User Pool ID:       us-east-1_ABC123XYZ
Client ID:          1a2b3c4d5e6f7g8h9i0j
Domain:             rds-dashboard-auth-123456789012
Hosted UI URL:      https://rds-dashboard-auth-123456789012.auth.us-east-1.amazoncognito.com
JWT Issuer:         https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ABC123XYZ
Region:             us-east-1

========================================
Admin User Credentials
========================================
Email:              your-email@company.com
Temporary Password: Abc123!@#XyzTemp

⚠️  IMPORTANT: Save this password! You'll need to change it on first login.
```

---

### Step 4: Verify Auth Stack (1 minute)

```powershell
# Check the stack was created
aws cloudformation describe-stacks --stack-name RDSDashboard-Auth-prod

# Verify Cognito User Pool
aws cognito-idp list-user-pools --max-results 10

# Verify your user was created
aws cognito-idp admin-get-user `
  --user-pool-id <USER_POOL_ID_FROM_STEP_3> `
  --username your-email@company.com
```

---

### Step 5: Deploy BFF Stack (5 minutes)

First, check if you need to update the BFF stack configuration:

```powershell
# Check infrastructure/bin/app.ts to ensure auth stack is integrated
cat infrastructure/bin/app.ts
```

Then deploy:

```powershell
.\scripts\deploy-bff.ps1 -Environment prod
```

**What to expect:**
1. Docker image will be built for BFF
2. Lambda function will be created
3. API Gateway will be configured
4. Environment variables will be set

**⚠️ IMPORTANT:** Save the BFF API URL from the output!

**Example Output:**
```
BffApiUrl = https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod/
```

---

### Step 6: Update Frontend Configuration (2 minutes)

The frontend `.env` file should have been updated by Step 3, but verify:

```powershell
cat frontend/.env
```

**Should contain:**
```env
VITE_COGNITO_USER_POOL_ID=us-east-1_ABC123XYZ
VITE_COGNITO_CLIENT_ID=1a2b3c4d5e6f7g8h9i0j
VITE_COGNITO_DOMAIN=rds-dashboard-auth-123456789012
VITE_COGNITO_REGION=us-east-1
VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
VITE_API_URL=https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod
```

**Update VITE_API_URL** with the BFF API URL from Step 5.

---

### Step 7: Test Locally (5 minutes)

```powershell
cd frontend
npm run dev
```

**Test the authentication flow:**

1. Open http://localhost:3000
2. Click "Login" button
3. You should be redirected to Cognito Hosted UI
4. Enter your email and temporary password
5. Set a new password when prompted
6. You should be redirected back to the dashboard
7. Verify:
   - Your email shows in the header
   - "Users" link is visible in navigation (Admin only)
   - Dashboard loads successfully

**If successful, proceed to Step 8. If not, see Troubleshooting section below.**

---

### Step 8: Create Additional Test Users (2 minutes)

```powershell
# Create DBA user
.\scripts\create-cognito-user.ps1 -Email "dba@company.com" -Group DBA

# Create ReadOnly user
.\scripts\create-cognito-user.ps1 -Email "readonly@company.com" -Group ReadOnly
```

**Save the temporary passwords for these users!**

---

### Step 9: Test Role-Based Access (5 minutes)

#### Test Admin Role (your account)
- ✅ Can see "Users" in navigation
- ✅ Can access User Management page
- ✅ Can add/remove roles
- ✅ Can see "Trigger Discovery" button
- ✅ Can see operations section on instance detail

#### Test DBA Role
1. Logout from admin account
2. Login with DBA credentials
3. Verify:
   - ✅ Can see "Trigger Discovery" button
   - ✅ Can see operations section
   - ❌ Cannot see "Users" in navigation
   - ❌ Cannot access /users page (should get 403)

#### Test ReadOnly Role
1. Logout from DBA account
2. Login with ReadOnly credentials
3. Verify:
   - ✅ Can view all dashboards
   - ❌ Cannot see "Trigger Discovery" button
   - ❌ Cannot see operations section
   - ❌ Cannot see "Users" in navigation

---

### Step 10: Verify Audit Logging (2 minutes)

```powershell
# Check BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --follow

# Check audit logs
aws logs tail /aws/rds-dashboard/audit --follow
```

**Look for:**
- Authentication events (login, logout)
- Authorization events (granted, denied)
- Operation events (if you executed any)

---

## Post-Deployment Verification

### ✅ Success Criteria

- [ ] Cognito User Pool created
- [ ] Admin, DBA, ReadOnly groups exist
- [ ] Admin user can log in
- [ ] BFF Lambda function deployed
- [ ] API Gateway configured
- [ ] Frontend can communicate with BFF
- [ ] JWT tokens are validated
- [ ] Role-based permissions work
- [ ] Audit logs are being written
- [ ] All test users can log in
- [ ] Each role has correct permissions

---

## Troubleshooting

### Issue: "Invalid redirect URI"

**Symptom:** After login, you get an error about invalid redirect URI

**Solution:**
1. Check Cognito User Pool Client settings
2. Verify callback URLs include your frontend URL
3. Update if needed:
```powershell
aws cognito-idp update-user-pool-client `
  --user-pool-id <USER_POOL_ID> `
  --client-id <CLIENT_ID> `
  --callback-urls "http://localhost:3000/callback" "http://localhost:5173/callback"
```

---

### Issue: "Token validation failed"

**Symptom:** BFF returns 401 errors

**Solution:**
1. Check BFF environment variables:
```powershell
aws lambda get-function-configuration `
  --function-name rds-dashboard-bff `
  --query 'Environment.Variables'
```

2. Verify COGNITO_USER_POOL_ID matches your User Pool ID
3. Update if needed and redeploy BFF

---

### Issue: "403 Forbidden" for all requests

**Symptom:** User can log in but gets 403 for all API calls

**Solution:**
1. Check user's Cognito groups:
```powershell
aws cognito-idp admin-list-groups-for-user `
  --user-pool-id <USER_POOL_ID> `
  --username your-email@company.com
```

2. If no groups, add user to a group:
```powershell
aws cognito-idp admin-add-user-to-group `
  --user-pool-id <USER_POOL_ID> `
  --username your-email@company.com `
  --group-name Admin
```

---

### Issue: "Cannot read properties of undefined (reading 'email')"

**Symptom:** Frontend crashes after login

**Solution:**
1. Check browser console for errors
2. Verify JWT token is being stored
3. Check AuthContext is properly initialized
4. Clear browser cache and try again

---

### Issue: BFF Docker build fails

**Symptom:** CDK deploy fails during Docker build

**Solution:**
1. Check Docker is running
2. Verify bff/Dockerfile exists
3. Check bff/package.json has all dependencies
4. Try building locally:
```powershell
cd bff
docker build -t test-bff .
```

---

## Rollback Procedure

If something goes wrong and you need to rollback:

### Rollback BFF
```powershell
cd infrastructure
npx aws-cdk destroy RDSDashboard-BFF-prod
```

### Rollback Auth (⚠️ This will delete users!)
```powershell
cd infrastructure
npx aws-cdk destroy RDSDashboard-Auth-prod
```

**Note:** Cognito User Pool has `RETAIN` policy, so it won't be deleted automatically. You'll need to manually delete it if needed.

---

## Next Steps After Successful Deployment

1. **Deploy to Production Frontend:**
   ```powershell
   cd frontend
   npm run build
   # Deploy dist/ to S3 or your hosting platform
   ```

2. **Update Cognito Callback URLs** for production domain

3. **Create Production Users** with real email addresses

4. **Set up CloudWatch Alarms** for BFF errors

5. **Configure Backup** for Cognito User Pool

6. **Document** the deployment for your team

7. **Train Users** on how to use the system

---

## Support Resources

- **Deployment Guide:** `docs/bff-deployment-guide.md`
- **Cognito Setup:** `docs/cognito-setup.md`
- **BFF Architecture:** `docs/bff-architecture.md`
- **Implementation Status:** `docs/AUTH-IMPLEMENTATION-STATUS.md`
- **Quick Start:** `DEPLOY-AUTH-NOW.md`

---

## 🎉 Congratulations!

If you've completed all steps successfully, your authentication system is now live!

Users can:
- ✅ Log in with Cognito
- ✅ Access features based on their role
- ✅ Have all actions audited
- ✅ Manage users (if Admin)

**The RDS Operations Dashboard is now secure and production-ready!**

