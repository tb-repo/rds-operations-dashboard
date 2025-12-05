# Cognito Authentication Setup Guide

## Overview

This guide explains how to set up AWS Cognito authentication for the RDS Operations Dashboard. Cognito provides secure user authentication with support for multiple user roles and permissions.

## Architecture

```
User → Cognito Hosted UI → JWT Token → BFF → Internal API
```

## User Roles and Permissions

### Admin Role
- **Full system access** including user management
- **Permissions**:
  - ✅ View all dashboards (instances, metrics, compliance, costs)
  - ✅ Execute operations on non-production instances
  - ✅ Generate CloudOps change requests
  - ✅ Trigger discovery scans
  - ✅ Manage users and assign roles

### DBA Role
- **Operational access** for database administrators
- **Permissions**:
  - ✅ View all dashboards
  - ✅ Execute operations on non-production instances
  - ✅ Generate CloudOps change requests
  - ✅ Trigger discovery scans
  - ❌ Cannot manage users

### ReadOnly Role
- **View-only access** for monitoring and reporting
- **Permissions**:
  - ✅ View all dashboards
  - ❌ Cannot execute operations
  - ❌ Cannot generate CloudOps requests
  - ❌ Cannot trigger discovery scans
  - ❌ Cannot manage users

## Deployment

### Prerequisites

- AWS CLI configured with appropriate credentials
- CDK installed (`npm install -g aws-cdk`)
- PowerShell (for deployment scripts)

### Step 1: Deploy Auth Stack

```powershell
# Deploy with initial admin user
.\scripts\deploy-auth.ps1 `
    -Environment prod `
    -AdminEmail admin@company.com `
    -FrontendDomain dashboard.company.com

# Or deploy without creating admin user
.\scripts\deploy-auth.ps1 -Environment prod
```

This will:
1. Create Cognito User Pool
2. Create user groups (Admin, DBA, ReadOnly)
3. Configure Hosted UI with OAuth
4. Create initial admin user (if email provided)
5. Update frontend `.env` file with Cognito configuration

### Step 2: Save Admin Credentials

The script will output:
```
Admin User Credentials
========================================
Email:              admin@company.com
Temporary Password: Abc123!@#XyzDef456
```

**⚠️ IMPORTANT**: Save these credentials securely! The temporary password is only shown once.

### Step 3: Verify Deployment

Check CloudFormation outputs:
```powershell
aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Auth-prod `
    --query "Stacks[0].Outputs"
```

Expected outputs:
- `UserPoolId`: Cognito User Pool ID
- `UserPoolClientId`: App client ID
- `UserPoolDomain`: Hosted UI domain
- `HostedUIUrl`: Full Hosted UI URL
- `JwtIssuer`: JWT token issuer URL

## Creating Additional Users

### Using PowerShell Script

```powershell
# Create Admin user
.\scripts\create-cognito-user.ps1 `
    -Email john.doe@company.com `
    -Group Admin `
    -FullName "John Doe"

# Create DBA user
.\scripts\create-cognito-user.ps1 `
    -Email jane.smith@company.com `
    -Group DBA `
    -FullName "Jane Smith"

# Create ReadOnly user
.\scripts\create-cognito-user.ps1 `
    -Email viewer@company.com `
    -Group ReadOnly
```

### Using AWS CLI

```bash
# Get User Pool ID
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name RDSDashboard-Auth-prod \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text)

# Create user
aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username user@company.com \
    --user-attributes Name=email,Value=user@company.com Name=email_verified,Value=true \
    --temporary-password "TempPass123!" \
    --message-action SUPPRESS

# Add to group
aws cognito-idp admin-add-user-to-group \
    --user-pool-id $USER_POOL_ID \
    --username user@company.com \
    --group-name DBA
```

### Using AWS Console

1. Go to AWS Console → Cognito → User Pools
2. Select `rds-dashboard-users-prod`
3. Click "Create user"
4. Enter email and temporary password
5. Go to "Groups" tab
6. Select group and click "Add user to group"

## User Login Flow

### First-Time Login

1. User navigates to dashboard URL
2. Redirected to Cognito Hosted UI
3. Enters email and temporary password
4. Prompted to set new password
5. Redirected back to dashboard with JWT token

### Subsequent Logins

1. User navigates to dashboard URL
2. Redirected to Cognito Hosted UI (if not authenticated)
3. Enters email and password
4. Redirected back to dashboard with JWT token

### Session Management

- **Access Token**: Valid for 1 hour
- **Refresh Token**: Valid for 30 days
- **Auto-refresh**: Token automatically refreshed when expired
- **Session timeout**: 8 hours of inactivity
- **Multi-tab**: Session shared across browser tabs

## Managing User Roles

### Add User to Group

```powershell
aws cognito-idp admin-add-user-to-group `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com `
    --group-name DBA
```

### Remove User from Group

```powershell
aws cognito-idp admin-remove-user-from-group `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com `
    --group-name ReadOnly
```

### List User's Groups

```powershell
aws cognito-idp admin-list-groups-for-user `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com
```

## Password Management

### Reset User Password

```powershell
aws cognito-idp admin-set-user-password `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com `
    --password "NewTempPass123!" `
    --permanent false
```

### Force Password Change

```powershell
aws cognito-idp admin-reset-user-password `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com
```

## Multi-Factor Authentication (MFA)

MFA is optional and can be enabled per user.

### Enable MFA for User

Users can enable MFA through the Hosted UI:
1. Login to dashboard
2. Go to user profile
3. Click "Enable MFA"
4. Scan QR code with authenticator app
5. Enter verification code

### Require MFA for All Users

Update `auth-stack.ts`:
```typescript
mfa: cognito.Mfa.REQUIRED,
```

Then redeploy:
```powershell
.\scripts\deploy-auth.ps1 -Environment prod
```

## Troubleshooting

### User Cannot Login

**Check user status**:
```powershell
aws cognito-idp admin-get-user `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com
```

**Possible statuses**:
- `FORCE_CHANGE_PASSWORD`: User needs to change temporary password
- `CONFIRMED`: User is active
- `UNCONFIRMED`: Email not verified
- `RESET_REQUIRED`: Password reset required

**Enable user**:
```powershell
aws cognito-idp admin-enable-user `
    --user-pool-id <USER_POOL_ID> `
    --username user@company.com
```

### Token Validation Errors

**Check JWT issuer**:
```powershell
# Get issuer from stack
aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Auth-prod `
    --query "Stacks[0].Outputs[?OutputKey=='JwtIssuer'].OutputValue" `
    --output text

# Verify BFF has correct issuer configured
```

**Verify token**:
- Go to https://jwt.io
- Paste token
- Check issuer matches User Pool
- Check groups are included in token

### Hosted UI Not Loading

**Check callback URLs**:
```powershell
aws cognito-idp describe-user-pool-client `
    --user-pool-id <USER_POOL_ID> `
    --client-id <CLIENT_ID> `
    --query "UserPoolClient.CallbackURLs"
```

**Update callback URLs**:
```powershell
aws cognito-idp update-user-pool-client `
    --user-pool-id <USER_POOL_ID> `
    --client-id <CLIENT_ID> `
    --callback-urls "https://dashboard.company.com/callback" "http://localhost:3000/callback"
```

## Security Best Practices

### Password Policy

Current policy (configured in `auth-stack.ts`):
- Minimum 8 characters
- Requires uppercase letter
- Requires lowercase letter
- Requires number
- Requires symbol
- Temporary password valid for 7 days

### Account Recovery

- Recovery method: Email only
- Users can reset password via "Forgot password" link
- Verification code sent to registered email

### Token Security

- Tokens stored in memory only (not localStorage)
- Refresh tokens in httpOnly cookies
- Short-lived access tokens (1 hour)
- Token rotation on refresh

### Audit Logging

All authentication events are logged:
- Successful logins
- Failed login attempts
- Password changes
- MFA events
- Group membership changes

View logs in CloudWatch:
```powershell
aws logs tail /aws/cognito/userpools/<USER_POOL_ID> --follow
```

## Cost Optimization

### Cognito Pricing

- **Free tier**: 50,000 MAUs (Monthly Active Users)
- **Beyond free tier**: $0.0055 per MAU
- **MFA SMS**: $0.00645 per SMS (TOTP is free)

### Recommendations

- Use TOTP (authenticator apps) instead of SMS for MFA
- Clean up inactive users periodically
- Monitor MAU count in CloudWatch

## Integration with Corporate SSO

To integrate with corporate identity provider (Okta, Azure AD, etc.):

1. Update `auth-stack.ts` to add identity provider
2. Configure SAML or OIDC federation
3. Map corporate groups to Cognito groups
4. Update callback URLs

See AWS documentation for detailed federation setup.

## Next Steps

After Cognito is set up:

1. ✅ Deploy BFF with authentication middleware
2. ✅ Deploy frontend with authentication enabled
3. ✅ Test login with admin user
4. ✅ Create additional users for team
5. ✅ Configure MFA (optional)
6. ✅ Set up corporate SSO (optional)
