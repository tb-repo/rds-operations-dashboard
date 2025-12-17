# 🚀 Deploy Authentication System - Quick Start

**Status:** ✅ All code is ready. Just run these commands!

---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Node.js and npm installed
- CDK bootstrapped in your AWS account

---

## 🎯 Quick Deployment (5 Minutes)

### Step 1: Deploy Cognito (2 minutes)

```powershell
cd rds-operations-dashboard
.\scripts\deploy-auth.ps1 -AdminEmail "your-email@company.com" -Environment prod
```

**What happens:**
- ✅ Creates Cognito User Pool
- ✅ Creates Admin, DBA, ReadOnly groups
- ✅ Creates your admin user
- ✅ Gives you a temporary password
- ✅ Updates frontend .env file

**Save the output!** You'll need:
- User Pool ID
- Client ID
- Temporary password

---

### Step 2: Deploy BFF (2 minutes)

```powershell
.\scripts\deploy-bff.ps1 -Environment prod
```

**What happens:**
- ✅ Builds BFF Docker container
- ✅ Deploys to Lambda
- ✅ Configures API Gateway
- ✅ Sets up Cognito integration

**Save the output:** BFF API URL

---

### Step 3: Update Frontend Config (30 seconds)

The frontend `.env` file was already updated by Step 1, but verify it has:

```env
VITE_COGNITO_USER_POOL_ID=us-east-1_XXXXXXXXX
VITE_COGNITO_CLIENT_ID=XXXXXXXXXXXXXXXXXXXXXXXXXX
VITE_COGNITO_DOMAIN=rds-dashboard-auth-XXXXXXXXXXXX
VITE_COGNITO_REGION=us-east-1
VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
VITE_API_URL=<BFF_API_URL_FROM_STEP_2>
```

---

### Step 4: Test Locally (1 minute)

```powershell
cd frontend
npm install
npm run dev
```

**Test the flow:**
1. Open http://localhost:3000
2. Click "Login"
3. Enter your email and temporary password
4. Set a new password
5. You should be redirected to the dashboard
6. Verify your email shows in the header

---

## ✅ Success Checklist

After deployment, verify:

- [ ] Can access Cognito Hosted UI
- [ ] Can log in with admin credentials
- [ ] Redirected back to dashboard after login
- [ ] User email shows in header
- [ ] "Users" link visible in navigation (Admin only)
- [ ] Can access User Management page
- [ ] Can view all dashboards
- [ ] "Trigger Discovery" button visible (Admin/DBA)
- [ ] Operations section visible on instance detail (Admin/DBA)

---

## 🔐 Create Additional Users

### Create DBA User
```powershell
.\scripts\create-cognito-user.ps1 -Email "dba@company.com" -Group DBA
```

### Create ReadOnly User
```powershell
.\scripts\create-cognito-user.ps1 -Email "readonly@company.com" -Group ReadOnly
```

---

## 🧪 Test Different Roles

### Test Admin Role
- ✅ Can see "Users" in navigation
- ✅ Can access User Management page
- ✅ Can add/remove roles
- ✅ Can execute operations
- ✅ Can generate CloudOps

### Test DBA Role
- ✅ Can execute operations on non-prod instances
- ✅ Can generate CloudOps requests
- ❌ Cannot see "Users" in navigation
- ❌ Cannot access User Management

### Test ReadOnly Role
- ✅ Can view all dashboards
- ❌ Cannot execute operations
- ❌ Cannot generate CloudOps
- ❌ Cannot see "Users" in navigation

---

## 🐛 Troubleshooting

### Issue: "Invalid redirect URI"
**Solution:** Check that the callback URL in Cognito matches your frontend URL

### Issue: "Token validation failed"
**Solution:** Verify BFF has correct COGNITO_USER_POOL_ID environment variable

### Issue: "403 Forbidden"
**Solution:** Check that user is in the correct Cognito group

### Issue: "Cannot read user info"
**Solution:** Verify JWT token is being sent in Authorization header

---

## 📊 Monitoring

### Check Audit Logs
```powershell
aws logs tail /aws/rds-dashboard/audit --follow
```

### Check BFF Logs
```powershell
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

---

## 🎉 You're Done!

The authentication system is now live. Users can:
- Log in with Cognito
- Access features based on their role
- Have all actions audited
- Manage users (if Admin)

---

## 📞 Need Help?

- **Deployment Issues:** Check `docs/bff-deployment-guide.md`
- **Cognito Setup:** Check `docs/cognito-setup.md`
- **Architecture:** Check `docs/bff-architecture.md`
- **Implementation Status:** Check `docs/AUTH-IMPLEMENTATION-STATUS.md`

