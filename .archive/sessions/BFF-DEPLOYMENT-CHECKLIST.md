# BFF Deployment Checklist

Use this checklist to ensure a smooth BFF deployment.

## Pre-Deployment

### Prerequisites
- [ ] AWS CLI installed and configured
- [ ] AWS CDK installed (`npm install -g aws-cdk`)
- [ ] Node.js 18+ installed
- [ ] PowerShell 5.1+ (Windows) or PowerShell Core (cross-platform)
- [ ] Internal API stack deployed (`RDSDashboard-API-prod`)
- [ ] AWS credentials configured with appropriate permissions

### Permissions Required
- [ ] CloudFormation: Create/Update stacks
- [ ] Lambda: Create/Update functions
- [ ] API Gateway: Create/Update APIs
- [ ] Secrets Manager: Create/Update secrets
- [ ] IAM: Create/Update roles and policies
- [ ] CloudWatch: Create log groups

## Deployment Steps

### Step 1: Deploy BFF Infrastructure

```powershell
# Option A: Automated (Recommended)
./rds-operations-dashboard/scripts/deploy-bff.ps1

# Option B: Manual
cd rds-operations-dashboard/infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod
```

**Verification**:
- [ ] CloudFormation stack created successfully
- [ ] Stack status: `CREATE_COMPLETE` or `UPDATE_COMPLETE`
- [ ] No errors in deployment output

### Step 2: Populate Secrets Manager

```powershell
./rds-operations-dashboard/scripts/setup-bff-secrets.ps1
```

**Verification**:
- [ ] Secret created: `rds-dashboard-api-key-prod`
- [ ] Secret contains `apiUrl` and `apiKey`
- [ ] No errors in script output

### Step 3: Test BFF Deployment

```powershell
./rds-operations-dashboard/scripts/test-bff.ps1
```

**Verification**:
- [ ] All 10 tests pass
- [ ] BFF URL displayed in output
- [ ] No failed tests

### Step 4: Get BFF URL

```powershell
aws cloudformation describe-stacks `
  --stack-name RDSDashboard-BFF-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
  --output text
```

**Record BFF URL**: _________________________________

### Step 5: Update Frontend Configuration

Edit `rds-operations-dashboard/frontend/.env`:

```env
VITE_BFF_API_URL=<YOUR_BFF_URL_HERE>
```

**Verification**:
- [ ] `.env` file updated with BFF URL
- [ ] BFF URL starts with `https://`
- [ ] BFF URL ends with `/prod`

### Step 6: Test Frontend Locally

```powershell
cd rds-operations-dashboard/frontend
npm install
npm run dev
```

Open http://localhost:5173

**Verification**:
- [ ] Dashboard loads without errors
- [ ] Instance list displays
- [ ] No API key errors in browser console
- [ ] Network tab shows requests to BFF URL (not direct API)
- [ ] No `x-api-key` header in requests

### Step 7: Deploy Frontend to Production

```powershell
git add .
git commit -m "Add BFF security layer"
git push
```

**Verification**:
- [ ] GitHub Actions workflow triggered
- [ ] Workflow completes successfully
- [ ] Frontend deployed to S3
- [ ] Production site loads correctly

## Post-Deployment

### Monitoring Setup

#### CloudWatch Logs
```powershell
# View BFF Lambda logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow
```

**Verification**:
- [ ] Log group exists: `/aws/lambda/rds-dashboard-bff-prod`
- [ ] Logs show successful requests
- [ ] No error messages in logs

#### CloudWatch Metrics

Navigate to AWS Console → CloudWatch → Metrics

**Verification**:
- [ ] Lambda invocations metric exists
- [ ] Lambda duration metric exists
- [ ] Lambda errors metric exists
- [ ] API Gateway requests metric exists

#### CloudWatch Alarms (Optional)

Create alarms for:
- [ ] High error rate (> 5%)
- [ ] High latency (> 3 seconds)
- [ ] Throttling events

### Security Validation

#### Test 1: No API Key in Browser
1. Open browser DevTools (F12)
2. Go to Network tab
3. Load dashboard
4. Check request headers

**Verification**:
- [ ] No `x-api-key` header in requests
- [ ] Requests go to BFF URL
- [ ] Responses have CORS headers

#### Test 2: Secrets Manager Access
```powershell
# Verify secret is accessible
aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod
```

**Verification**:
- [ ] Secret retrieved successfully
- [ ] Contains `apiUrl` and `apiKey`
- [ ] `apiKey` is not empty

#### Test 3: Lambda IAM Permissions
```powershell
# Get Lambda role
$role = aws lambda get-function `
  --function-name rds-dashboard-bff-prod `
  --query 'Configuration.Role' `
  --output text

# Check policies
aws iam list-attached-role-policies --role-name $role.Split('/')[-1]
```

**Verification**:
- [ ] Role has Secrets Manager read permission
- [ ] Role has CloudWatch Logs write permission
- [ ] No excessive permissions

### Performance Testing

#### Test 1: Latency
```powershell
# Measure response time
Measure-Command {
  Invoke-WebRequest -Uri "https://your-bff-url/instances" -UseBasicParsing
}
```

**Verification**:
- [ ] Response time < 2 seconds
- [ ] No timeouts
- [ ] Consistent response times

#### Test 2: Throughput
```powershell
# Run multiple requests
1..10 | ForEach-Object -Parallel {
  Invoke-WebRequest -Uri "https://your-bff-url/instances" -UseBasicParsing
}
```

**Verification**:
- [ ] All requests succeed
- [ ] No throttling errors
- [ ] No 429 responses

### Cost Monitoring

Navigate to AWS Console → Cost Explorer

**Verification**:
- [ ] Lambda costs visible
- [ ] API Gateway costs visible
- [ ] Secrets Manager costs visible
- [ ] Total cost < $20/month (for moderate traffic)

## Rollback Plan

If issues occur, rollback using:

### Option 1: Revert Frontend
```powershell
# Update .env to use direct API
VITE_API_BASE_URL=https://your-direct-api-url/prod
VITE_API_KEY=your-api-key

# Redeploy
git add .
git commit -m "Rollback to direct API"
git push
```

### Option 2: Delete BFF Stack
```powershell
# Delete BFF stack (keeps data)
aws cloudformation delete-stack --stack-name RDSDashboard-BFF-prod

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name RDSDashboard-BFF-prod
```

**Note**: Deleting the stack will also delete the Secrets Manager secret after 7-30 days (recovery window).

## Troubleshooting

### Issue: Stack deployment fails

**Check**:
- [ ] AWS credentials valid
- [ ] Sufficient IAM permissions
- [ ] No resource limits reached
- [ ] Internal API stack exists

**Fix**:
```powershell
# View stack events
aws cloudformation describe-stack-events --stack-name RDSDashboard-BFF-prod

# Delete and retry
aws cloudformation delete-stack --stack-name RDSDashboard-BFF-prod
./scripts/deploy-bff.ps1
```

### Issue: Secret not found

**Check**:
- [ ] Secret name correct: `rds-dashboard-api-key-prod`
- [ ] Secret in correct region
- [ ] Lambda has permission to read secret

**Fix**:
```powershell
# Re-run secrets setup
./scripts/setup-bff-secrets.ps1
```

### Issue: CORS errors

**Check**:
- [ ] BFF API has CORS enabled
- [ ] Origin header present in request
- [ ] OPTIONS method allowed

**Fix**:
```powershell
# Redeploy BFF stack
npx aws-cdk deploy RDSDashboard-BFF-prod --force
```

### Issue: 403 from internal API

**Check**:
- [ ] API key in secret is correct
- [ ] Internal API key not expired
- [ ] Usage plan has quota remaining

**Fix**:
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

# Update secret
./scripts/setup-bff-secrets.ps1
```

## Sign-Off

### Deployment Team
- [ ] Deployed by: _________________ Date: _________
- [ ] Tested by: _________________ Date: _________
- [ ] Approved by: _________________ Date: _________

### Verification
- [ ] All tests passed
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Team notified

### Notes
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________

---

**Deployment Status**: ⬜ Not Started | ⬜ In Progress | ⬜ Complete  
**Issues Encountered**: ⬜ None | ⬜ Minor | ⬜ Major  
**Rollback Required**: ⬜ Yes | ⬜ No
