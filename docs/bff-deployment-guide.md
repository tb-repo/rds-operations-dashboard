# BFF (Backend-for-Frontend) Deployment Guide

## Overview

The BFF layer provides a secure proxy between the frontend and the internal API Gateway, eliminating the need to expose API keys in the browser. This solution uses AWS Secrets Manager to securely store API credentials.

## Architecture

```
Frontend (Browser)
    ↓ (No API Key)
BFF API Gateway (Public)
    ↓
BFF Lambda Function
    ↓ (Fetches API Key from Secrets Manager)
Internal API Gateway (Protected)
    ↓
Backend Lambda Functions
```

## Security Benefits

✅ **No API key in frontend code** - Completely eliminated from browser  
✅ **Secrets in AWS Secrets Manager** - Encrypted and rotatable  
✅ **Cached credentials** - BFF caches secrets for 5 minutes to reduce API calls  
✅ **CORS enabled** - Proper cross-origin support  
✅ **Error handling** - Graceful fallbacks  

## Prerequisites

- AWS CLI configured with appropriate credentials
- CDK deployed (API stack must be deployed first)
- PowerShell (for Windows) or Bash (for Linux/Mac)

## Deployment Steps

### Step 1: Deploy the BFF Stack

```powershell
# Navigate to project root
cd rds-operations-dashboard

# Deploy BFF stack
./scripts/deploy-bff.ps1
```

This script will:
1. Deploy the BFF CloudFormation stack
2. Create Secrets Manager secret
3. Populate the secret with API credentials
4. Display the BFF API URL

### Step 2: Update Frontend Configuration

After deployment, update your frontend `.env` file:

```bash
# Get BFF URL
aws cloudformation describe-stacks \
  --stack-name RDSDashboard-BFF-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' \
  --output text
```

Update `frontend/.env`:
```env
VITE_BFF_API_URL=https://your-bff-url.execute-api.ap-southeast-1.amazonaws.com/prod
```

### Step 3: Test Locally

```bash
cd frontend
npm run dev
```

Open http://localhost:5173 and verify:
- Dashboard loads without errors
- API calls work (check browser console)
- No API key visible in network requests

### Step 4: Deploy to Production

```bash
git add .
git commit -m "Add BFF security layer"
git push
```

GitHub Actions will automatically:
1. Detect BFF stack
2. Use BFF URL for frontend build
3. Deploy to S3

## Manual Deployment Steps

If you prefer manual deployment:

### 1. Deploy BFF Stack

```bash
cd rds-operations-dashboard/infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod --require-approval never
```

### 2. Setup Secrets Manager

```powershell
./scripts/setup-bff-secrets.ps1
```

Or manually:

```bash
# Get API Key ID
API_KEY_ID=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboard-API-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
  --output text)

# Get API URL
API_URL=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboard-API-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text)

# Get API Key value
API_KEY=$(aws apigateway get-api-key \
  --api-key $API_KEY_ID \
  --include-value \
  --query 'value' \
  --output text)

# Update secret
aws secretsmanager update-secret \
  --secret-id rds-dashboard-api-key-prod \
  --secret-string "{\"apiUrl\":\"$API_URL\",\"apiKey\":\"$API_KEY\",\"description\":\"RDS Dashboard API credentials\"}"
```

## Verification

### 1. Check BFF Stack Status

```bash
aws cloudformation describe-stacks \
  --stack-name RDSDashboard-BFF-prod \
  --query 'Stacks[0].StackStatus' \
  --output text
```

Expected: `CREATE_COMPLETE` or `UPDATE_COMPLETE`

### 2. Verify Secrets Manager

```bash
aws secretsmanager describe-secret \
  --secret-id rds-dashboard-api-key-prod
```

### 3. Test BFF Endpoint

```bash
# Get BFF URL
BFF_URL=$(aws cloudformation describe-stacks \
  --stack-name RDSDashboard-BFF-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' \
  --output text)

# Test health endpoint
curl "${BFF_URL}/health"
```

### 4. Check Lambda Logs

```bash
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow
```

## Troubleshooting

### Issue: BFF returns 500 error

**Cause:** Secret not populated or Lambda can't access it

**Solution:**
```powershell
./scripts/setup-bff-secrets.ps1
```

### Issue: CORS errors in browser

**Cause:** BFF API Gateway CORS not configured

**Solution:** Redeploy BFF stack:
```bash
npx aws-cdk deploy RDSDashboard-BFF-prod --force
```

### Issue: Frontend still using direct API

**Cause:** `VITE_BFF_API_URL` not set

**Solution:** 
1. Check `frontend/.env` has `VITE_BFF_API_URL` set
2. Rebuild frontend: `npm run build`
3. Clear browser cache

### Issue: Secret rotation needed

**Solution:**
```bash
# Rotate API key in API Gateway
aws apigateway update-api-key \
  --api-key <API_KEY_ID> \
  --patch-operations op=replace,path=/value,value=<NEW_KEY>

# Update secret
./scripts/setup-bff-secrets.ps1
```

## Cost Considerations

The BFF solution adds minimal cost:

- **Lambda invocations:** ~$0.20 per 1M requests
- **API Gateway:** ~$3.50 per 1M requests
- **Secrets Manager:** ~$0.40 per secret per month + $0.05 per 10,000 API calls
- **CloudWatch Logs:** ~$0.50 per GB

**Estimated monthly cost for 1M requests:** ~$5

## Security Best Practices

1. **Rotate secrets regularly** - Use AWS Secrets Manager rotation
2. **Monitor BFF logs** - Set up CloudWatch alarms for errors
3. **Limit BFF access** - Consider adding WAF rules if needed
4. **Use VPC endpoints** - For enhanced security (optional)
5. **Enable API Gateway throttling** - Already configured (1000 req/s)

## Rollback Plan

If issues occur, rollback to direct API access:

1. Update `frontend/.env`:
   ```env
   # Comment out BFF URL
   # VITE_BFF_API_URL=https://...
   
   # Use direct API
   VITE_API_BASE_URL=https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod
   VITE_API_KEY=<your-api-key>
   ```

2. Rebuild and redeploy frontend

3. Delete BFF stack (optional):
   ```bash
   aws cloudformation delete-stack --stack-name RDSDashboard-BFF-prod
   ```

## Monitoring

### CloudWatch Metrics

Monitor these metrics in CloudWatch:

- **BFF Lambda Duration** - Should be < 1000ms
- **BFF Lambda Errors** - Should be 0
- **BFF API Gateway 4XX/5XX** - Should be minimal
- **Secrets Manager API Calls** - Should be low (caching working)

### Set Up Alarms

```bash
# Lambda error alarm
aws cloudwatch put-metric-alarm \
  --alarm-name rds-dashboard-bff-errors \
  --alarm-description "BFF Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=rds-dashboard-bff-prod
```

## Next Steps

After successful BFF deployment:

1. ✅ Remove API key from frontend code completely
2. ✅ Update documentation to reference BFF URL
3. ✅ Set up monitoring and alarms
4. ✅ Configure secret rotation (optional)
5. ✅ Consider adding WAF for additional security (optional)

## Support

For issues or questions:
1. Check CloudWatch logs: `/aws/lambda/rds-dashboard-bff-prod`
2. Verify Secrets Manager secret is populated
3. Test BFF endpoint directly with curl
4. Review this guide's troubleshooting section
