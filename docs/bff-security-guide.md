# BFF Security Architecture Guide

## Overview

The Backend-for-Frontend (BFF) layer provides a secure proxy between the frontend application and the internal API Gateway, eliminating the need to expose API keys in the browser.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────────┐         ┌──────────────┐
│   Browser   │────────▶│  BFF API     │────────▶│  BFF Lambda     │────────▶│  Internal    │
│  (Frontend) │         │  Gateway     │         │  (Proxy)        │         │  API Gateway │
│             │         │  (Public)    │         │                 │         │  (Protected) │
└─────────────┘         └──────────────┘         └─────────────────┘         └──────────────┘
                                                           │
                                                           ▼
                                                  ┌─────────────────┐
                                                  │  AWS Secrets    │
                                                  │  Manager        │
                                                  │  (API Key)      │
                                                  └─────────────────┘
```

## Security Benefits

### 1. **No API Key Exposure**
- API keys are never sent to the browser
- Keys are stored securely in AWS Secrets Manager
- Frontend only needs to know the BFF URL

### 2. **Credential Rotation**
- API keys can be rotated without frontend changes
- BFF Lambda caches credentials for 5 minutes
- Automatic refresh on cache expiry

### 3. **Additional Security Layer**
- BFF can implement additional authentication (Cognito, OAuth)
- Request validation and sanitization
- Rate limiting and throttling
- IP whitelisting (if needed)

### 4. **Audit Trail**
- All requests logged through BFF Lambda
- CloudWatch logs for monitoring
- Traceability of all API calls

## Components

### 1. BFF Lambda Function

**Purpose**: Proxy requests from frontend to internal API

**Key Features**:
- Retrieves API credentials from Secrets Manager
- Caches credentials for 5 minutes
- Forwards requests to internal API with API key
- Handles CORS automatically
- Error handling and logging

**Environment Variables**:
- `API_SECRET_ARN`: ARN of the secret in Secrets Manager
- `NODE_ENV`: Environment (production)

**IAM Permissions**:
- `secretsmanager:GetSecretValue` on the API secret

### 2. AWS Secrets Manager

**Purpose**: Securely store API credentials

**Secret Structure**:
```json
{
  "apiUrl": "https://xxx.execute-api.region.amazonaws.com/prod",
  "apiKey": "actual-api-key-value",
  "description": "RDS Dashboard API credentials",
  "lastUpdated": "2025-11-20T10:00:00Z"
}
```

**Security Features**:
- Encrypted at rest using AWS KMS
- Encrypted in transit
- Access controlled via IAM policies
- Automatic rotation support (optional)

### 3. BFF API Gateway

**Purpose**: Public endpoint for frontend

**Configuration**:
- No API key required
- CORS enabled for all origins
- Throttling: 1000 req/sec, burst 2000
- CloudWatch logging enabled
- Metrics enabled

## Deployment

### Prerequisites

1. Internal API stack must be deployed first
2. AWS CLI configured with appropriate credentials
3. CDK installed and bootstrapped

### Step 1: Deploy BFF Stack

```powershell
# Deploy the BFF infrastructure
./rds-operations-dashboard/scripts/deploy-bff.ps1
```

This script will:
1. Deploy the BFF stack (Lambda, API Gateway, Secrets Manager)
2. Retrieve the API key from the internal API
3. Store credentials in Secrets Manager
4. Output the BFF API URL

### Step 2: Update Frontend Configuration

Update `frontend/.env`:

```env
# Use BFF URL (no API key needed)
VITE_BFF_API_URL=https://xxx.execute-api.region.amazonaws.com/prod

# Fallback to direct API (requires API key)
VITE_API_BASE_URL=https://yyy.execute-api.region.amazonaws.com/prod
VITE_API_KEY=your-api-key-here
```

### Step 3: Deploy Frontend

```powershell
# Local testing
cd frontend
npm run dev

# Production deployment (via GitHub Actions)
git add .
git commit -m "Update to use BFF"
git push
```

## Manual Setup (Alternative)

If you prefer manual setup:

### 1. Deploy BFF Stack

```powershell
cd rds-operations-dashboard/infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod
```

### 2. Populate Secrets Manager

```powershell
./rds-operations-dashboard/scripts/setup-bff-secrets.ps1
```

### 3. Get BFF URL

```powershell
aws cloudformation describe-stacks `
  --stack-name RDSDashboard-BFF-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
  --output text
```

## Monitoring

### CloudWatch Logs

BFF Lambda logs are available in CloudWatch:

```
/aws/lambda/rds-dashboard-bff-prod
```

**Key Log Events**:
- Request details (path, method, headers)
- API credential retrieval
- Errors and exceptions

### CloudWatch Metrics

Monitor BFF performance:

- **Invocations**: Number of requests
- **Duration**: Response time
- **Errors**: Failed requests
- **Throttles**: Rate-limited requests

### Alarms

Consider setting up alarms for:
- High error rate (> 5%)
- High latency (> 3 seconds)
- Throttling events
- Secrets Manager access failures

## Security Best Practices

### 1. Restrict BFF Access

Add authentication to BFF API Gateway:

```typescript
// Add Cognito authorizer
const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, 'BffAuthorizer', {
  cognitoUserPools: [userPool]
});

// Require authentication
this.bffApi.root.addMethod('ANY', integration, {
  authorizer: authorizer,
  authorizationType: apigateway.AuthorizationType.COGNITO
});
```

### 2. Enable API Gateway WAF

Protect against common attacks:

```typescript
// Add WAF Web ACL
const webAcl = new wafv2.CfnWebACL(this, 'BffWaf', {
  scope: 'REGIONAL',
  defaultAction: { allow: {} },
  rules: [
    // Rate limiting
    {
      name: 'RateLimit',
      priority: 1,
      statement: {
        rateBasedStatement: {
          limit: 2000,
          aggregateKeyType: 'IP'
        }
      },
      action: { block: {} }
    }
  ]
});
```

### 3. Enable VPC Endpoints

Keep traffic within AWS network:

```typescript
// Add VPC endpoint for Secrets Manager
const secretsEndpoint = vpc.addInterfaceEndpoint('SecretsEndpoint', {
  service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER
});

// Deploy Lambda in VPC
this.bffFunction = new lambda.Function(this, 'BffFunction', {
  vpc: vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }
  // ... other config
});
```

### 4. Implement Request Validation

Add validation in BFF Lambda:

```javascript
// Validate request
function validateRequest(event) {
  // Check required headers
  if (!event.headers['content-type']) {
    throw new Error('Content-Type header required');
  }
  
  // Validate path
  const allowedPaths = ['/instances', '/health', '/costs', '/compliance', '/operations'];
  if (!allowedPaths.some(path => event.path.startsWith(path))) {
    throw new Error('Invalid path');
  }
  
  // Validate method
  const allowedMethods = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'];
  if (!allowedMethods.includes(event.httpMethod)) {
    throw new Error('Invalid method');
  }
}
```

### 5. Enable Secrets Rotation

Automatically rotate API keys:

```typescript
// Add rotation schedule
this.apiSecret.addRotationSchedule('RotationSchedule', {
  automaticallyAfter: cdk.Duration.days(30),
  rotationLambda: rotationFunction
});
```

## Troubleshooting

### Issue: BFF returns 500 error

**Possible Causes**:
1. Secret not found in Secrets Manager
2. Invalid API key
3. Internal API unreachable

**Solution**:
```powershell
# Check CloudWatch logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow

# Verify secret exists
aws secretsmanager describe-secret --secret-id rds-dashboard-api-key-prod

# Test secret retrieval
aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod
```

### Issue: CORS errors in browser

**Possible Causes**:
1. CORS not configured on BFF API
2. Preflight OPTIONS request failing

**Solution**:
```powershell
# Test OPTIONS request
curl -X OPTIONS https://your-bff-url.com/instances \
  -H "Origin: http://localhost:5173" \
  -H "Access-Control-Request-Method: GET" \
  -v
```

### Issue: High latency

**Possible Causes**:
1. Cold start delays
2. Secrets Manager API calls
3. Internal API slow

**Solution**:
```typescript
// Enable provisioned concurrency
this.bffFunction.addAlias('live', {
  provisionedConcurrentExecutions: 5
});

// Increase cache duration
cacheExpiry = now + (15 * 60 * 1000); // 15 minutes
```

## Cost Considerations

### BFF Lambda
- **Requests**: $0.20 per 1M requests
- **Duration**: $0.0000166667 per GB-second
- **Typical cost**: ~$5-10/month for moderate traffic

### Secrets Manager
- **Secret storage**: $0.40 per secret per month
- **API calls**: $0.05 per 10,000 calls
- **Typical cost**: ~$1-2/month

### API Gateway
- **Requests**: $3.50 per 1M requests
- **Data transfer**: $0.09 per GB
- **Typical cost**: ~$10-20/month for moderate traffic

**Total estimated cost**: $15-30/month for the BFF layer

## Migration from Direct API

### Step 1: Deploy BFF (No Downtime)

Deploy BFF stack while keeping direct API access:

```powershell
./rds-operations-dashboard/scripts/deploy-bff.ps1
```

### Step 2: Test BFF

Test BFF with a subset of users:

```typescript
// Feature flag in frontend
const useBff = import.meta.env.VITE_USE_BFF === 'true';
const apiUrl = useBff ? import.meta.env.VITE_BFF_API_URL : import.meta.env.VITE_API_BASE_URL;
```

### Step 3: Gradual Rollout

Update environment variables for different environments:

1. **Dev**: Use BFF
2. **Staging**: Use BFF
3. **Production**: Gradual rollout (10% → 50% → 100%)

### Step 4: Remove Direct API Access

Once BFF is stable, remove API key from frontend:

```typescript
// Remove API key header
const api = axios.create({
  baseURL: import.meta.env.VITE_BFF_API_URL,
  // No API key needed!
});
```

## Conclusion

The BFF layer provides a secure, scalable, and maintainable solution for protecting API credentials. It adds minimal latency (~50-100ms) while significantly improving security posture.

For questions or issues, refer to the CloudWatch logs or contact the DevOps team.
