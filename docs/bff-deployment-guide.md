# BFF Deployment Guide

## Overview

This guide covers the complete process for building and deploying the Backend-for-Frontend (BFF) service to AWS Lambda.

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured with appropriate credentials
- PowerShell 7+ (for deployment scripts)
- Access to the target AWS account

## Quick Start

### 1. Build and Deploy

```powershell
# Navigate to project root
cd rds-operations-dashboard

# Deploy BFF to production
./scripts/deploy-bff-production.ps1
```

### 2. Validate Deployment

```powershell
# Run validation tests
./scripts/validate-bff-deployment.ps1
```

## Detailed Deployment Process

### Step 1: Verify Build Environment

```powershell
# Check Node.js version
node --version  # Should be 18+

# Check npm version
npm --version

# Navigate to BFF directory
cd bff

# Install dependencies
npm install
```

### Step 2: Build TypeScript

```powershell
# Build the project
npm run build

# Verify dist directory was created
ls dist/
```

Expected output:
```
dist/
├── config/
├── middleware/
├── routes/
├── services/
├── utils/
├── index.js
├── index.d.ts
├── lambda.js
└── lambda.d.ts
```

### Step 3: Deploy to Lambda

```powershell
# From project root
./scripts/deploy-bff-production.ps1

# Or with custom parameters
./scripts/deploy-bff-production.ps1 -FunctionName my-bff -Region us-east-1

# Skip build if already built
./scripts/deploy-bff-production.ps1 -SkipBuild
```

The deployment script will:
1. Build TypeScript (unless -SkipBuild is used)
2. Clean previous deployment artifacts
3. Create deployment package directory
4. Copy compiled code and package files
5. Install production dependencies
6. Create deployment zip
7. Deploy to Lambda
8. Test health endpoint

### Step 4: Validate Deployment

```powershell
# Run validation tests
./scripts/validate-bff-deployment.ps1
```

The validation script checks:
- Lambda function exists
- Health endpoint responds
- CORS headers are configured
- Environment variables are set
- CloudWatch logs are accessible

## Environment Variables

The BFF requires these environment variables to be set in Lambda:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `COGNITO_USER_POOL_ID` | Cognito User Pool ID | `ap-southeast-1_abc123` |
| `COGNITO_CLIENT_ID` | Cognito App Client ID | `1234567890abcdef` |
| `COGNITO_REGION` | AWS region for Cognito | `ap-southeast-1` |
| `INTERNAL_API_URL` | Backend API Gateway URL | `https://api.execute-api.region.amazonaws.com/prod` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_ENV` | Environment mode | `production` |
| `LOG_LEVEL` | Logging level | `info` |
| `API_SECRET_ARN` | Secrets Manager ARN for API key | (uses INTERNAL_API_KEY if not set) |
| `INTERNAL_API_KEY` | Direct API key (if not using Secrets Manager) | - |

### Setting Environment Variables

```powershell
# Update Lambda environment variables
aws lambda update-function-configuration `
  --function-name rds-dashboard-bff-prod `
  --environment Variables="{
    COGNITO_USER_POOL_ID=ap-southeast-1_abc123,
    COGNITO_CLIENT_ID=1234567890abcdef,
    COGNITO_REGION=ap-southeast-1,
    INTERNAL_API_URL=https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod,
    NODE_ENV=production
  }" `
  --region ap-southeast-1
```

## Testing

### Test Health Endpoint

```powershell
# Via Lambda
aws lambda invoke `
  --function-name rds-dashboard-bff-prod `
  --payload '{"httpMethod":"GET","path":"/health","headers":{}}' `
  --region ap-southeast-1 `
  response.json

# View response
cat response.json
```

Expected response:
```json
{
  "statusCode": 200,
  "body": "{\"status\":\"healthy\",\"service\":\"rds-dashboard-bff\",\"timestamp\":\"2025-01-14T10:30:00.000Z\"}"
}
```

### Test CORS

```powershell
# Test OPTIONS request
aws lambda invoke `
  --function-name rds-dashboard-bff-prod `
  --payload '{"httpMethod":"OPTIONS","path":"/api/instances","headers":{"Origin":"https://your-domain.cloudfront.net"}}' `
  --region ap-southeast-1 `
  response.json

# View response
cat response.json
```

Expected response should include CORS headers:
```json
{
  "statusCode": 204,
  "headers": {
    "Access-Control-Allow-Origin": "https://your-domain.cloudfront.net",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization"
  }
}
```

### Test via API Gateway

```powershell
# Test health endpoint
curl https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod/health

# Test with authentication
curl https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Monitoring

### View CloudWatch Logs

```powershell
# Tail logs in real-time
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow

# View recent logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --since 1h

# Filter for errors
aws logs tail /aws/lambda/rds-dashboard-bff-prod --filter-pattern "ERROR"
```

### Check Lambda Metrics

```powershell
# Get function configuration
aws lambda get-function-configuration `
  --function-name rds-dashboard-bff-prod `
  --region ap-southeast-1

# Get function metrics (via CloudWatch)
aws cloudwatch get-metric-statistics `
  --namespace AWS/Lambda `
  --metric-name Invocations `
  --dimensions Name=FunctionName,Value=rds-dashboard-bff-prod `
  --start-time 2025-01-14T00:00:00Z `
  --end-time 2025-01-14T23:59:59Z `
  --period 3600 `
  --statistics Sum `
  --region ap-southeast-1
```

## Troubleshooting

### Build Fails

**Issue**: TypeScript compilation errors

**Solution**:
```powershell
# Check for syntax errors
npm run lint

# Clean and rebuild
rm -rf dist node_modules
npm install
npm run build
```

### Deployment Fails

**Issue**: Lambda update fails

**Solution**:
```powershell
# Verify AWS credentials
aws sts get-caller-identity

# Check Lambda function exists
aws lambda get-function --function-name rds-dashboard-bff-prod --region ap-southeast-1

# Check IAM permissions (need lambda:UpdateFunctionCode)
```

### Health Check Fails

**Issue**: Health endpoint returns 500 error

**Solution**:
```powershell
# Check CloudWatch logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow

# Verify environment variables
aws lambda get-function-configuration --function-name rds-dashboard-bff-prod --region ap-southeast-1

# Test Lambda directly
aws lambda invoke --function-name rds-dashboard-bff-prod --payload '{"httpMethod":"GET","path":"/health","headers":{}}' response.json
```

### CORS Errors

**Issue**: Frontend gets CORS errors

**Solution**:
1. Verify CloudFront domain is in allowed origins
2. Check API Gateway CORS configuration
3. Test OPTIONS requests directly
4. Review BFF CORS middleware configuration

```powershell
# Check CORS configuration in code
cat bff/src/config/cors.ts

# Test OPTIONS request
curl -X OPTIONS https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances \
  -H "Origin: https://your-domain.cloudfront.net" \
  -H "Access-Control-Request-Method: GET" \
  -v
```

### Large Package Size

**Issue**: Deployment package exceeds Lambda limits

**Solution**:
```powershell
# Check package size
ls -lh bff/deployment.zip

# Analyze dependencies
cd bff
npm ls --depth=0

# Remove unnecessary dependencies
npm prune --production

# Consider using Lambda layers for large dependencies
```

## Rollback

If deployment causes issues, rollback to previous version:

```powershell
# Option 1: Redeploy previous deployment.zip
aws lambda update-function-code `
  --function-name rds-dashboard-bff-prod `
  --zip-file fileb://deployment.zip.backup `
  --region ap-southeast-1

# Option 2: Use Lambda version/alias
aws lambda update-alias `
  --function-name rds-dashboard-bff-prod `
  --name prod `
  --function-version PREVIOUS_VERSION `
  --region ap-southeast-1
```

## Best Practices

### Before Deployment

1. **Test locally**: Run `npm test` to ensure all tests pass
2. **Review changes**: Check git diff to understand what's being deployed
3. **Backup current version**: Keep a copy of the current deployment.zip
4. **Check environment**: Verify environment variables are correct

### During Deployment

1. **Monitor logs**: Keep CloudWatch logs open during deployment
2. **Test incrementally**: Test each endpoint after deployment
3. **Watch metrics**: Monitor Lambda invocation metrics
4. **Be ready to rollback**: Have rollback command ready

### After Deployment

1. **Validate thoroughly**: Run full validation suite
2. **Test user flows**: Test critical user journeys
3. **Monitor for errors**: Watch CloudWatch logs for 15-30 minutes
4. **Document changes**: Update deployment log with what was deployed

## Deployment Checklist

- [ ] Code changes reviewed and tested locally
- [ ] All tests passing (`npm test`)
- [ ] TypeScript builds without errors (`npm run build`)
- [ ] Environment variables verified
- [ ] Backup of current deployment created
- [ ] Deployment script executed successfully
- [ ] Validation tests passed
- [ ] Health endpoint responding
- [ ] CORS configuration working
- [ ] CloudWatch logs showing no errors
- [ ] Frontend integration tested
- [ ] User flows validated
- [ ] Deployment documented

## Support

For issues or questions:
1. Check CloudWatch logs first
2. Review this guide's troubleshooting section
3. Check the main README.md for project overview
4. Review the BFF architecture documentation

## Related Documentation

- [BFF Architecture](./bff-architecture.md)
- [BFF Testing Guide](./bff-testing-guide.md)
- [API Documentation](./api-documentation.md)
- [Deployment Guide](./deployment.md)
