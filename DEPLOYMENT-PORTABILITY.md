# Deployment Portability Guide

## Overview

This document explains how the RDS Operations Dashboard handles deployment to different AWS accounts and how configuration is managed.

## Current Issues & Solutions

### Issue 1: Hardcoded Account ID

**Problem**: Lambda functions had hardcoded account ID (876595225096) in environment variables.

**Solution**: 
- **Automatic (CDK)**: Use `cdk.Stack.of(this).account` to auto-detect
- **Manual**: Set `AWS_ACCOUNT_ID` environment variable per account

**Files Affected**:
- All Lambda functions in `infrastructure/lib/compute-stack.ts`
- Manual updates via AWS CLI if not using CDK

### Issue 2: Cognito Configuration

**Problem**: Cognito User Pool ID, Client ID, and Domain are account-specific.

**Solution**: Configuration stored in multiple places:
1. **Frontend**: `frontend/.env.production` (build-time)
2. **BFF Lambda**: Environment variables (runtime)
3. **CDK**: Can be parameterized via context

**Files Affected**:
- `frontend/.env.production`
- `frontend/.env` (local development)
- BFF Lambda environment variables

## Configuration Matrix

| Component | Config Type | Location | How to Update |
|-----------|-------------|----------|---------------|
| Account ID | Environment Var | Lambda functions | CDK auto-detect or manual CLI |
| Cognito Pool ID | Environment Var | Frontend .env + BFF Lambda | Manual per account |
| Cognito Client ID | Environment Var | Frontend .env + BFF Lambda | Manual per account |
| Cognito Domain | Environment Var | Frontend .env + BFF Lambda | Manual per account |
| API Gateway URL | Environment Var | Frontend .env | From CDK outputs |
| CloudFront URL | Environment Var | BFF Lambda | From CDK outputs |
| Region | CDK Context | cdk.json | Manual or CLI flag |

## Deployment Approaches

### Approach 1: Fully Automated (Recommended)

Use CDK with automatic account detection:

```typescript
// infrastructure/lib/compute-stack.ts
environment: {
  AWS_ACCOUNT_ID: cdk.Stack.of(this).account,  // Auto-detect
  AWS_REGION: cdk.Stack.of(this).region,       // Auto-detect
  // ... other vars
}
```

**Pros**:
- No manual configuration needed
- Works across any account
- Reduces human error

**Cons**:
- Still need to configure Cognito manually
- Requires CDK deployment

### Approach 2: Parameter Store

Store configuration in AWS Systems Manager Parameter Store:

```bash
# Store config
aws ssm put-parameter \
  --name /rds-dashboard/cognito/user-pool-id \
  --value "ap-southeast-1_XXXXXXXXX" \
  --type String

# Lambda reads at runtime
import boto3
ssm = boto3.client('ssm')
pool_id = ssm.get_parameter(Name='/rds-dashboard/cognito/user-pool-id')['Parameter']['Value']
```

**Pros**:
- Centralized configuration
- Easy to update without redeployment
- Supports encryption

**Cons**:
- Additional API calls (latency)
- Requires IAM permissions
- More complex

### Approach 3: CDK Context

Pass configuration via CDK context:

```bash
# Deploy with context
cdk deploy --context cognitoPoolId=ap-southeast-1_XXXXXXXXX \
           --context cognitoClientId=abc123 \
           --all
```

```typescript
// In CDK stack
const cognitoPoolId = this.node.tryGetContext('cognitoPoolId');
```

**Pros**:
- Configuration in one place
- Version controlled
- Type-safe

**Cons**:
- Requires redeployment for changes
- Context can be forgotten

## Recommended Setup

### For Production

1. **Use CDK with auto-detection** for account ID and region
2. **Use Parameter Store** for Cognito configuration
3. **Use Secrets Manager** for sensitive data (API keys, etc.)
4. **Use CDK outputs** for URLs (API Gateway, CloudFront)

### For Development

1. **Use .env files** for local development
2. **Use separate AWS accounts** for dev/staging/prod
3. **Use CDK context** for environment-specific config

## Migration Steps

### From Current Setup to Portable Setup

1. **Update CDK to auto-detect account**:
   ```bash
   ./scripts/add-account-id-to-cdk.ps1
   ```

2. **Move Cognito config to Parameter Store**:
   ```bash
   aws ssm put-parameter --name /rds-dashboard/cognito/user-pool-id --value "<pool-id>"
   aws ssm put-parameter --name /rds-dashboard/cognito/client-id --value "<client-id>"
   aws ssm put-parameter --name /rds-dashboard/cognito/domain --value "<domain>"
   ```

3. **Update Lambda to read from Parameter Store**:
   ```python
   import boto3
   import os
   from functools import lru_cache
   
   @lru_cache(maxsize=1)
   def get_config():
       ssm = boto3.client('ssm')
       params = ssm.get_parameters(
           Names=[
               '/rds-dashboard/cognito/user-pool-id',
               '/rds-dashboard/cognito/client-id',
               '/rds-dashboard/cognito/domain'
           ]
       )
       return {p['Name']: p['Value'] for p in params['Parameters']}
   ```

4. **Update frontend build process**:
   ```bash
   # Fetch config from Parameter Store during build
   export VITE_COGNITO_USER_POOL_ID=$(aws ssm get-parameter --name /rds-dashboard/cognito/user-pool-id --query Parameter.Value --output text)
   npm run build
   ```

## Multi-Account Strategy

### Hub-and-Spoke Model

Deploy dashboard in one account (hub), monitor RDS in multiple accounts (spokes):

```
┌─────────────────┐
│  Hub Account    │
│  (Dashboard)    │
│  876595225096   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│Spoke 1│ │Spoke 2│
│(RDS)  │ │(RDS)  │
└───────┘ └───────┘
```

**Setup**:
1. Dashboard deployed in hub account
2. Cross-account IAM roles in spoke accounts
3. Discovery Lambda assumes roles to access spoke RDS
4. Single Cognito pool in hub account

### Multi-Region Deployment

Deploy separate dashboards per region:

```bash
for region in us-east-1 eu-west-1 ap-southeast-1; do
  export AWS_REGION=$region
  cdk deploy --all
done
```

## Environment Variables Reference

### Lambda Functions

| Variable | Required | Source | Example |
|----------|----------|--------|---------|
| AWS_ACCOUNT_ID | Yes | Auto-detect or manual | 876595225096 |
| AWS_REGION | No | Auto-set by Lambda | ap-southeast-1 |
| INVENTORY_TABLE | Yes | CDK | rds-inventory |
| COGNITO_USER_POOL_ID | Yes (BFF only) | Manual/Parameter Store | ap-southeast-1_ABC123 |
| COGNITO_CLIENT_ID | Yes (BFF only) | Manual/Parameter Store | 1234567890abcdef |
| COGNITO_DOMAIN | Yes (BFF only) | Manual/Parameter Store | rds-dashboard.auth.ap-southeast-1.amazoncognito.com |

### Frontend

| Variable | Required | Source | Example |
|----------|----------|--------|---------|
| VITE_API_URL | Yes | CDK output | https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod |
| VITE_COGNITO_USER_POOL_ID | Yes | Manual | ap-southeast-1_ABC123 |
| VITE_COGNITO_CLIENT_ID | Yes | Manual | 1234567890abcdef |
| VITE_COGNITO_DOMAIN | Yes | Manual | rds-dashboard.auth.ap-southeast-1.amazoncognito.com |
| VITE_COGNITO_REGION | Yes | Manual | ap-southeast-1 |

## Testing Portability

### Test Checklist

- [ ] Deploy to fresh AWS account
- [ ] Verify account ID auto-detection works
- [ ] Create new Cognito pool
- [ ] Update configuration
- [ ] Build and deploy frontend
- [ ] Test authentication
- [ ] Test RDS discovery
- [ ] Test operations (start/stop)
- [ ] Verify no hardcoded values remain

### Validation Script

```bash
#!/bin/bash
# validate-portability.sh

echo "Checking for hardcoded account IDs..."
grep -r "876595225096" --exclude-dir=node_modules --exclude-dir=.git .

echo "Checking for hardcoded Cognito IDs..."
grep -r "ap-southeast-1_" --exclude-dir=node_modules --exclude-dir=.git .

echo "Checking Lambda environment variables..."
for func in $(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'rds-')].FunctionName" --output text); do
  echo "Checking $func..."
  aws lambda get-function-configuration --function-name $func --query 'Environment.Variables.AWS_ACCOUNT_ID'
done
```

## Documentation

- **Full deployment guide**: `docs/NEW-ACCOUNT-DEPLOYMENT.md`
- **Deployment checklist**: `NEW-ACCOUNT-CHECKLIST.md`
- **Cross-account setup**: `docs/cross-account-setup.md`
- **Cognito setup**: `docs/cognito-setup.md`

## Support

For deployment issues:
1. Check CloudFormation events
2. Review Lambda logs
3. Verify IAM permissions
4. Consult deployment documentation
5. Run validation script

## Future Improvements

1. **Terraform support** - Alternative to CDK
2. **Automated Cognito setup** - Script to create pool/client
3. **Configuration UI** - Web interface for config management
4. **Multi-tenant support** - Single deployment, multiple organizations
5. **Backup/restore** - Configuration backup and restore
