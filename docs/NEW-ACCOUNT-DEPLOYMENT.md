# Deploying to a New AWS Account

This guide explains how to deploy the RDS Operations Dashboard to a new AWS account with proper configuration.

## Prerequisites

- AWS CLI configured with credentials for the target account
- Node.js 18+ and npm
- Python 3.11+
- AWS CDK CLI (`npm install -g aws-cdk`)

## Step 1: Update CDK Infrastructure

The CDK stacks should automatically detect the account ID, but you need to update the Lambda environment variables.

### Option A: Update CDK to Auto-Inject Account ID (Recommended)

Edit `infrastructure/lib/compute-stack.ts` and add `AWS_ACCOUNT_ID` to each Lambda's environment:

```typescript
environment: {
  AWS_ACCOUNT_ID: cdk.Stack.of(this).account,  // Auto-detects account
  INVENTORY_TABLE: rdsInventoryTable.tableName,
  // ... other vars
}
```

### Option B: Manual Configuration

If not using CDK, set the environment variable manually after deployment:

```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update all Lambda functions
for func in rds-discovery-prod rds-health-monitor-prod rds-operations-prod \
            rds-query-handler-prod rds-cloudops-generator-prod \
            rds-compliance-checker-prod rds-cost-analyzer-prod; do
  aws lambda update-function-configuration \
    --function-name $func \
    --environment "Variables={AWS_ACCOUNT_ID=$ACCOUNT_ID}" \
    --query 'FunctionName' \
    --output text
done
```

## Step 2: Configure Cognito

### Create Cognito User Pool

```bash
# Create user pool
aws cognito-idp create-user-pool \
  --pool-name rds-dashboard-users \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true}" \
  --auto-verified-attributes email \
  --mfa-configuration OPTIONAL \
  --user-attribute-update-settings "AttributesRequireVerificationBeforeUpdate=[email]" \
  --query 'UserPool.Id' \
  --output text
```

Save the User Pool ID (e.g., `ap-southeast-1_XXXXXXXXX`)

### Create App Client

```bash
USER_POOL_ID="<your-pool-id>"
CLOUDFRONT_URL="<your-cloudfront-url>"  # e.g., https://d1234567890.cloudfront.net

aws cognito-idp create-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-name rds-dashboard-client \
  --generate-secret \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid email profile \
  --callback-urls "$CLOUDFRONT_URL/callback" "$CLOUDFRONT_URL" \
  --logout-urls "$CLOUDFRONT_URL" \
  --supported-identity-providers COGNITO \
  --allowed-o-auth-flows-user-pool-client \
  --query 'UserPoolClient.ClientId' \
  --output text
```

Save the Client ID

### Create Cognito Domain

```bash
aws cognito-idp create-user-pool-domain \
  --domain rds-dashboard-$(date +%s) \
  --user-pool-id $USER_POOL_ID
```

## Step 3: Update BFF Configuration

Update the BFF Lambda environment variables:

```bash
CLIENT_ID="<your-client-id>"
USER_POOL_ID="<your-pool-id>"
COGNITO_DOMAIN="<your-domain>.auth.ap-southeast-1.amazoncognito.com"

aws lambda update-function-configuration \
  --function-name rds-dashboard-bff-prod \
  --environment "Variables={
    COGNITO_USER_POOL_ID=$USER_POOL_ID,
    COGNITO_CLIENT_ID=$CLIENT_ID,
    COGNITO_DOMAIN=$COGNITO_DOMAIN,
    COGNITO_REGION=ap-southeast-1,
    FRONTEND_URL=$CLOUDFRONT_URL
  }"
```

## Step 4: Update Frontend Configuration

Create/update `frontend/.env.production`:

```env
VITE_API_URL=https://<api-gateway-id>.execute-api.ap-southeast-1.amazonaws.com/prod
VITE_COGNITO_USER_POOL_ID=<your-pool-id>
VITE_COGNITO_CLIENT_ID=<your-client-id>
VITE_COGNITO_DOMAIN=<your-domain>.auth.ap-southeast-1.amazoncognito.com
VITE_COGNITO_REGION=ap-southeast-1
```

## Step 5: Automated Deployment Script

Create a deployment script that handles everything:

```bash
#!/bin/bash
# deploy-new-account.sh

set -e

echo "🚀 Deploying RDS Operations Dashboard to new account..."

# Get account ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=${AWS_REGION:-ap-southeast-1}

echo "📋 Account ID: $ACCOUNT_ID"
echo "📋 Region: $AWS_REGION"

# Deploy CDK stacks
echo "📦 Deploying infrastructure..."
cd infrastructure
npm install
cdk bootstrap aws://$ACCOUNT_ID/$AWS_REGION
cdk deploy --all --require-approval never

# Get outputs
export API_URL=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboardApiStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text)

export CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboardFrontendStack \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
  --output text)

# Update Lambda environment variables with account ID
echo "🔧 Configuring Lambda functions..."
for func in $(aws lambda list-functions \
  --query "Functions[?starts_with(FunctionName, 'rds-')].FunctionName" \
  --output text); do
  
  echo "  Updating $func..."
  aws lambda update-function-configuration \
    --function-name $func \
    --environment Variables="{AWS_ACCOUNT_ID=$ACCOUNT_ID}" \
    --output text > /dev/null
done

# Build and deploy frontend
echo "🎨 Building frontend..."
cd ../frontend
npm install
npm run build

# Upload to S3
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboardFrontendStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

aws s3 sync dist/ s3://$BUCKET_NAME/ --delete

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboardFrontendStack \
  --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].OutputValue' \
  --output text)

aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"

echo "✅ Deployment complete!"
echo ""
echo "📝 Next steps:"
echo "1. Configure Cognito (see docs/NEW-ACCOUNT-DEPLOYMENT.md)"
echo "2. Create initial admin user"
echo "3. Access dashboard at: $CLOUDFRONT_URL"
```

## Step 6: Create Initial Admin User

```bash
USER_POOL_ID="<your-pool-id>"
ADMIN_EMAIL="admin@example.com"

# Create user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username $ADMIN_EMAIL \
  --user-attributes Name=email,Value=$ADMIN_EMAIL Name=email_verified,Value=true \
  --message-action SUPPRESS

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username $ADMIN_EMAIL \
  --password 'TempPassword123!' \
  --permanent

# Add to admin group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id $USER_POOL_ID \
  --username $ADMIN_EMAIL \
  --group-name Admins
```

## Step 7: Run Discovery

Populate the inventory with your RDS instances:

```bash
aws lambda invoke \
  --function-name rds-discovery-prod \
  --payload '{"operation":"discover"}' \
  response.json

cat response.json
```

## Configuration Files Summary

### Files to Update for New Account

1. **infrastructure/cdk.json** - CDK context (optional)
2. **frontend/.env.production** - Cognito and API URLs
3. **Lambda environment variables** - AWS_ACCOUNT_ID (auto or manual)

### Files That Auto-Configure

- Lambda IAM roles (uses CDK account detection)
- DynamoDB tables (created by CDK)
- S3 buckets (created by CDK)
- API Gateway (created by CDK)

## Troubleshooting

### Issue: 500 errors on health/operations endpoints

**Cause**: AWS_ACCOUNT_ID not set on Lambda functions

**Fix**:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws lambda update-function-configuration \
  --function-name rds-health-monitor-prod \
  --environment "Variables={AWS_ACCOUNT_ID=$ACCOUNT_ID}"
```

### Issue: Cognito redirect errors

**Cause**: Callback URLs not configured correctly

**Fix**:
```bash
aws cognito-idp update-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-id $CLIENT_ID \
  --callback-urls "https://your-cloudfront-url.com/callback" \
  --logout-urls "https://your-cloudfront-url.com"
```

### Issue: Cross-account access errors

**Cause**: Trying to access RDS in different account without proper role

**Fix**: Either:
1. Ensure AWS_ACCOUNT_ID matches the RDS account (same account)
2. Set up cross-account IAM role (see docs/cross-account-setup.md)

## Best Practices

1. **Use CDK for deployment** - Automatically handles account detection
2. **Store secrets in AWS Secrets Manager** - Don't hardcode credentials
3. **Use Parameter Store for config** - Centralize configuration
4. **Enable CloudTrail** - Audit all API calls
5. **Set up CloudWatch alarms** - Monitor Lambda errors
6. **Use separate accounts** - Dev, staging, production

## Multi-Region Deployment

To deploy to multiple regions:

```bash
for region in us-east-1 eu-west-1 ap-southeast-1; do
  export AWS_REGION=$region
  ./deploy-new-account.sh
done
```

## Cleanup

To remove all resources:

```bash
cd infrastructure
cdk destroy --all
```

## Support

For issues or questions:
- Check logs: `aws logs tail /aws/lambda/rds-<function-name> --follow`
- Review CloudFormation events
- Check IAM permissions
