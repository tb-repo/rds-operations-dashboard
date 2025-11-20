# BFF Deployment Quick Start

## What is BFF?

The Backend-for-Frontend (BFF) layer is a secure proxy that sits between your frontend and the internal API. It eliminates the need to expose API keys in the browser by storing them securely in AWS Secrets Manager.

## Why Use BFF?

✅ **Security**: API keys never exposed to browser  
✅ **Flexibility**: Rotate credentials without frontend changes  
✅ **Control**: Add authentication, validation, rate limiting  
✅ **Monitoring**: Centralized logging and metrics  

## Quick Deployment

### Option 1: Automated Script (Recommended)

```powershell
# Deploy everything in one command
./rds-operations-dashboard/scripts/deploy-bff.ps1
```

This will:
1. Deploy BFF stack (Lambda + API Gateway + Secrets Manager)
2. Retrieve API key from internal API
3. Store credentials in Secrets Manager
4. Output the BFF URL

### Option 2: Manual Steps

```powershell
# 1. Deploy BFF infrastructure
cd rds-operations-dashboard/infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod

# 2. Setup secrets
cd ..
./scripts/setup-bff-secrets.ps1

# 3. Get BFF URL
aws cloudformation describe-stacks `
  --stack-name RDSDashboard-BFF-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
  --output text
```

## Update Frontend

### 1. Update `.env` file

```env
# Replace YOUR_BFF_URL_HERE with the actual BFF URL from deployment
VITE_BFF_API_URL=https://xxx.execute-api.ap-southeast-1.amazonaws.com/prod

# Keep these for fallback (optional)
VITE_API_BASE_URL=https://yyy.execute-api.ap-southeast-1.amazonaws.com/prod
VITE_API_KEY=your-api-key-here
```

### 2. Test Locally

```powershell
cd frontend
npm run dev
```

Open http://localhost:5173 and verify:
- Dashboard loads
- Instance list appears
- No API key errors in console

### 3. Deploy to Production

```powershell
# Commit changes
git add .
git commit -m "Add BFF security layer"
git push

# GitHub Actions will automatically:
# - Build frontend with BFF URL
# - Deploy to S3
```

## Verify Deployment

### 1. Check BFF Stack

```powershell
aws cloudformation describe-stacks --stack-name RDSDashboard-BFF-prod
```

Expected outputs:
- `BffApiUrl`: Public BFF endpoint
- `BffApiId`: API Gateway ID
- `ApiSecretArn`: Secrets Manager ARN

### 2. Test BFF Endpoint

```powershell
# Test health endpoint
$bffUrl = "https://xxx.execute-api.ap-southeast-1.amazonaws.com/prod"
curl "$bffUrl/instances"
```

Expected response: JSON with instance list (no API key needed!)

### 3. Check Secrets Manager

```powershell
# Verify secret exists
aws secretsmanager describe-secret --secret-id rds-dashboard-api-key-prod

# View secret value (for debugging)
aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod
```

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────────┐
│   Browser   │────────▶│  BFF API     │────────▶│  BFF Lambda     │
│  (Frontend) │  HTTPS  │  Gateway     │         │  (Proxy)        │
│             │         │  (Public)    │         │                 │
└─────────────┘         └──────────────┘         └─────────────────┘
                              │                           │
                              │                           ▼
                              │                  ┌─────────────────┐
                              │                  │  AWS Secrets    │
                              │                  │  Manager        │
                              │                  │  (API Key)      │
                              │                  └─────────────────┘
                              │                           │
                              ▼                           ▼
                        ┌──────────────┐         ┌─────────────────┐
                        │  Internal    │◀────────│  Retrieves Key  │
                        │  API Gateway │         │  & Forwards     │
                        │  (Protected) │         │  Request        │
                        └──────────────┘         └─────────────────┘
```

## Monitoring

### CloudWatch Logs

```powershell
# View BFF Lambda logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow
```

### CloudWatch Metrics

Check in AWS Console:
- Lambda → Functions → rds-dashboard-bff-prod → Monitoring
- API Gateway → APIs → rds-dashboard-bff-prod → Dashboard

Key metrics:
- **Invocations**: Request count
- **Duration**: Response time (should be < 1 second)
- **Errors**: Failed requests (should be < 1%)
- **Throttles**: Rate-limited requests

## Troubleshooting

### Issue: "Unable to retrieve API credentials"

**Cause**: Secret not found or Lambda doesn't have permission

**Solution**:
```powershell
# Re-run secrets setup
./rds-operations-dashboard/scripts/setup-bff-secrets.ps1

# Check Lambda IAM role has secretsmanager:GetSecretValue permission
aws iam get-role-policy --role-name <lambda-role-name> --policy-name <policy-name>
```

### Issue: CORS errors in browser

**Cause**: CORS not properly configured

**Solution**:
```powershell
# Redeploy BFF stack
npx aws-cdk deploy RDSDashboard-BFF-prod --force
```

### Issue: 403 Forbidden from internal API

**Cause**: Invalid API key in Secrets Manager

**Solution**:
```powershell
# Get correct API key
$apiKeyId = aws cloudformation describe-stacks `
  --stack-name RDSDashboard-API-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' `
  --output text

$apiKey = aws apigateway get-api-key `
  --api-key $apiKeyId `
  --include-value `
  --query 'value' `
  --output text

# Update secret manually
aws secretsmanager update-secret `
  --secret-id rds-dashboard-api-key-prod `
  --secret-string "{\"apiUrl\":\"https://xxx.execute-api.ap-southeast-1.amazonaws.com/prod\",\"apiKey\":\"$apiKey\"}"
```

### Issue: High latency (> 2 seconds)

**Cause**: Cold start or slow internal API

**Solution**:
```typescript
// Enable provisioned concurrency (in bff-stack.ts)
const alias = this.bffFunction.addAlias('live', {
  provisionedConcurrentExecutions: 2
});
```

## Cost Estimate

| Service | Usage | Monthly Cost |
|---------|-------|--------------|
| Lambda | 1M requests, 512MB, 500ms avg | ~$5 |
| API Gateway | 1M requests | ~$3.50 |
| Secrets Manager | 1 secret, 100K API calls | ~$1 |
| **Total** | | **~$10/month** |

## Security Best Practices

1. ✅ **Rotate API keys regularly** (every 90 days)
2. ✅ **Enable CloudWatch alarms** for errors and throttling
3. ✅ **Review CloudWatch logs** weekly
4. ✅ **Add authentication** to BFF (Cognito, OAuth) for production
5. ✅ **Enable WAF** on BFF API Gateway for DDoS protection

## Next Steps

1. **Add Authentication**: Integrate AWS Cognito or OAuth
2. **Enable WAF**: Protect against common attacks
3. **Setup Alarms**: Get notified of issues
4. **Implement Caching**: Add CloudFront for better performance
5. **Rotate Credentials**: Setup automatic key rotation

## Resources

- [BFF Security Guide](./docs/bff-security-guide.md) - Detailed security documentation
- [API Documentation](./docs/api-documentation.md) - API endpoint reference
- [Deployment Guide](./docs/deployment.md) - Full deployment instructions

## Support

For issues or questions:
1. Check CloudWatch logs: `/aws/lambda/rds-dashboard-bff-prod`
2. Review [Troubleshooting](#troubleshooting) section
3. Contact DevOps team

---

**Deployment Status**: ✅ Ready for production  
**Security Level**: High (API keys in Secrets Manager)  
**Maintenance**: Low (automated credential caching)
