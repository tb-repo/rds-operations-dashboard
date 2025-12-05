# Authentication & RBAC Setup Guide

## 🚀 Quick Start

This guide will help you set up and deploy the authentication and RBAC system.

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured
- AWS CDK installed (`npm install -g aws-cdk`)
- Access to AWS account with permissions to create Cognito resources

## Step 1: Install Dependencies

### Backend (BFF)
```bash
cd rds-operations-dashboard/bff
npm install
```

This will install the new package:
- `@aws-sdk/client-cognito-identity-provider@^3.490.0`

### Frontend
```bash
cd rds-operations-dashboard/frontend
npm install
```

This will install the new package:
- `amazon-cognito-identity-js@^6.3.7`

## Step 2: Deploy Cognito User Pool

The Cognito stack is already defined in `infrastructure/lib/auth-stack.ts`.

```bash
cd rds-operations-dashboard/infrastructure
npm install
npm run cdk deploy RDSAuthStack
```

After deployment, note the outputs:
- `UserPoolId`
- `UserPoolClientId`
- `UserPoolDomain`

## Step 3: Create Initial Admin User

### Option A: Using AWS Console
1. Go to AWS Cognito Console
2. Select your User Pool
3. Click "Create user"
4. Enter email address
5. Set temporary password
6. Add user to "Admin" group

### Option B: Using AWS CLI
```bash
# Create user
aws cognito-idp admin-create-user \
  --user-pool-id <USER_POOL_ID> \
  --username admin@example.com \
  --user-attributes Name=email,Value=admin@example.com Name=email_verified,Value=true \
  --temporary-password TempPassword123! \
  --message-action SUPPRESS

# Add to Admin group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id <USER_POOL_ID> \
  --username admin@example.com \
  --group-name Admin
```

### Option C: Using the provided script
```powershell
cd rds-operations-dashboard/scripts
.\create-cognito-user.ps1 -UserPoolId <USER_POOL_ID> -Email admin@example.com -Group Admin
```

## Step 4: Configure Environment Variables

### BFF Environment Variables

Create or update `rds-operations-dashboard/bff/.env`:

```bash
# Cognito Configuration
COGNITO_USER_POOL_ID=ap-southeast-1_xxxxxxxxx
COGNITO_REGION=ap-southeast-1
COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
JWT_ISSUER=https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_xxxxxxxxx

# Audit Logging
AUDIT_LOG_GROUP=/aws/rds-dashboard/audit
ENABLE_AUDIT_LOGGING=true
TOKEN_VALIDATION_CACHE_TTL=3600

# Internal API
INTERNAL_API_URL=https://your-internal-api-url.execute-api.ap-southeast-1.amazonaws.com
INTERNAL_API_KEY=your-internal-api-key

# CORS
FRONTEND_URL=https://your-frontend-domain.com

# Server
PORT=3000
NODE_ENV=production
```

### Frontend Environment Variables

Create or update `rds-operations-dashboard/frontend/.env`:

```bash
# Cognito Configuration
VITE_COGNITO_USER_POOL_ID=ap-southeast-1_xxxxxxxxx
VITE_COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
VITE_COGNITO_DOMAIN=rds-dashboard-auth-prod.auth.ap-southeast-1.amazoncognito.com
VITE_COGNITO_REDIRECT_URI=https://your-frontend-domain.com/callback
VITE_COGNITO_LOGOUT_URI=https://your-frontend-domain.com/
VITE_COGNITO_REGION=ap-southeast-1

# BFF API
VITE_BFF_API_URL=https://your-bff-url.com
```

For local development:
```bash
VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback
VITE_COGNITO_LOGOUT_URI=http://localhost:3000/
VITE_BFF_API_URL=http://localhost:3000
```

## Step 5: Build and Deploy

### BFF
```bash
cd rds-operations-dashboard/bff
npm run build
# Deploy to your hosting platform (EC2, ECS, Lambda, etc.)
```

### Frontend
```bash
cd rds-operations-dashboard/frontend
npm run build
# Deploy to your hosting platform (S3+CloudFront, Amplify, etc.)
```

## Step 6: Test the System

### 1. Access the Application
Navigate to your frontend URL. You should be redirected to the login page.

### 2. Login with Admin User
- Click "Sign In with Corporate Account"
- You'll be redirected to Cognito Hosted UI
- Enter the admin email and temporary password
- You'll be prompted to set a new password
- After successful login, you'll be redirected back to the dashboard

### 3. Verify Permissions
As an admin user, you should see:
- ✅ Dashboard with "Trigger Discovery" button
- ✅ All navigation items including "Users"
- ✅ Operations section on instance detail pages
- ✅ User Management page

### 4. Create Additional Users
1. Go to User Management page
2. Use AWS Console or CLI to create new users
3. Assign roles using the User Management UI

### 5. Test Different Roles

**DBA User:**
- Can view all dashboards
- Can execute operations on non-prod instances
- Can generate CloudOps requests
- Cannot access User Management

**ReadOnly User:**
- Can view all dashboards
- Cannot execute operations
- Cannot generate CloudOps requests
- Cannot access User Management

## Step 7: Verify Audit Logging

Check CloudWatch Logs for audit events:

```bash
aws logs tail /aws/rds-dashboard/audit --follow
```

You should see logs for:
- Authentication events (login success/failure)
- Authorization decisions (granted/denied)
- Operations executed
- CloudOps requests generated
- User role changes

## Troubleshooting

### Issue: "Cannot find module 'amazon-cognito-identity-js'"
**Solution:** Run `npm install` in the frontend directory

### Issue: "Cannot find module '@aws-sdk/client-cognito-identity-provider'"
**Solution:** Run `npm install` in the bff directory

### Issue: "Invalid redirect URI"
**Solution:** Ensure the redirect URI in Cognito matches your frontend URL exactly

### Issue: "Token validation failed"
**Solution:** 
- Check that COGNITO_USER_POOL_ID and COGNITO_REGION are correct in BFF
- Verify JWT_ISSUER matches the format: `https://cognito-idp.{region}.amazonaws.com/{userPoolId}`

### Issue: "403 Forbidden" on API calls
**Solution:**
- Verify user has the required permission
- Check that the JWT token is being sent in the Authorization header
- Verify the BFF authorization middleware is working

### Issue: User can't see certain UI elements
**Solution:**
- Verify user is in the correct Cognito group
- Check that permissions are correctly mapped in AuthContext
- Verify PermissionGuard components are working

## Security Checklist

- ✅ HTTPS enabled for all endpoints
- ✅ Cognito User Pool has strong password policy
- ✅ JWT tokens stored in memory only (not localStorage)
- ✅ CORS configured to allow only your frontend domain
- ✅ Security headers configured (Helmet.js)
- ✅ Audit logging enabled
- ✅ Production instances protected from operations
- ✅ Token expiration enforced

## Monitoring

### CloudWatch Metrics to Monitor
- Authentication success/failure rate
- Authorization denial rate
- Token validation errors
- API latency

### CloudWatch Alarms to Set Up
- Failed login attempts > 10 in 5 minutes
- Authorization denials > 50 in 5 minutes
- Token validation failures > 20 in 5 minutes

## Maintenance

### Adding a New User
1. Create user in Cognito (Console or CLI)
2. Assign to appropriate group
3. User will receive email with temporary password
4. User logs in and sets permanent password

### Changing User Roles
1. Admin logs into User Management page
2. Finds the user
3. Adds or removes roles as needed
4. Changes take effect immediately

### Adding a New Permission
1. Add permission to `Permission` type in AuthContext
2. Add permission to role mapping in `ROLE_PERMISSIONS`
3. Add endpoint mapping in `ENDPOINT_PERMISSIONS` (BFF)
4. Update permission descriptions
5. Redeploy BFF and Frontend

## Support

For issues or questions:
1. Check CloudWatch Logs for errors
2. Verify environment variables are correct
3. Test with different user roles
4. Review audit logs for authorization decisions

## Next Steps

1. ✅ Deploy to production
2. ✅ Create production users
3. ✅ Set up monitoring and alerts
4. ✅ Train users on the new authentication system
5. ✅ Document any custom configurations
6. ✅ Set up backup admin users

---

**Status**: Ready for deployment
**Last Updated**: November 23, 2025
