# BFF Quick Start Guide

## ✅ Fixed: PowerShell Syntax Error

The `deploy-bff.ps1` script has been fixed. The issue was using `&&` (bash syntax) instead of `;` (PowerShell syntax).

## 🚀 Deploy Now

```powershell
# Navigate to project root
cd rds-operations-dashboard

# Deploy BFF stack
./scripts/deploy-bff.ps1
```

## What Happens Next

The script will:

1. ✅ Deploy BFF CDK stack (~2-3 minutes)
2. ✅ Retrieve API key from internal API
3. ✅ Store credentials in Secrets Manager
4. ✅ Display BFF URL

## Expected Output

```
🚀 Deploying BFF Stack for environment: prod
📦 Deploying BFF stack...
✅ BFF stack deployed successfully
🔐 Setting up Secrets Manager...
📋 Getting API Key ID from CloudFormation...
✅ API Key ID: xxxxx
📋 Getting API URL from CloudFormation...
✅ API URL: https://xxxxx.execute-api.ap-southeast-1.amazonaws.com/prod
🔑 Getting API Key value from API Gateway...
✅ API Key retrieved successfully
🔐 Updating Secrets Manager...
✅ Secret updated successfully

🎉 BFF Secrets setup completed!
📋 Summary:
   Secret Name: rds-dashboard-api-key-prod
   API URL: https://xxxxx.execute-api.ap-southeast-1.amazonaws.com/prod
   API Key ID: xxxxx

🎉 BFF Deployment Complete!
📋 Configuration:
   BFF API URL: https://yyyyy.execute-api.ap-southeast-1.amazonaws.com/prod

📝 Next Steps:
   1. Update frontend/.env with: VITE_BFF_API_URL=https://yyyyy.execute-api.ap-southeast-1.amazonaws.com/prod
   2. Test the frontend: cd frontend; npm run dev
   3. Deploy frontend: git push (GitHub Actions will deploy)
```

## Next Steps

### 1. Update Frontend Configuration

Edit `frontend/.env`:

```env
VITE_BFF_API_URL=https://your-bff-url-from-output.execute-api.ap-southeast-1.amazonaws.com/prod
```

### 2. Test Locally

```powershell
cd frontend
npm install
npm run dev
```

Open http://localhost:5173 and verify:
- ✅ Dashboard loads
- ✅ No API key errors
- ✅ Requests go to BFF URL

### 3. Deploy to Production

```powershell
git add .
git commit -m "Add BFF security layer"
git push
```

GitHub Actions will automatically deploy the frontend with the BFF URL.

## Troubleshooting

### If deployment fails

```powershell
# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name RDSDashboard-BFF-prod

# Check if internal API exists
aws cloudformation describe-stacks --stack-name RDSDashboard-API-prod
```

### If secrets setup fails

```powershell
# Re-run secrets setup
./scripts/setup-bff-secrets.ps1
```

### Test deployment

```powershell
# Run validation tests
./scripts/test-bff.ps1
```

## Manual Deployment (Alternative)

If you prefer step-by-step:

```powershell
# 1. Deploy infrastructure
cd infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod

# 2. Setup secrets
cd ..
./scripts/setup-bff-secrets.ps1

# 3. Get BFF URL
aws cloudformation describe-stacks `
  --stack-name RDSDashboard-BFF-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
  --output text

# 4. Test
./scripts/test-bff.ps1
```

## What Was Fixed

**Before** (Error):
```powershell
Write-Host "2. Test the frontend: cd frontend && npm run dev"
```

**After** (Fixed):
```powershell
Write-Host "2. Test the frontend: cd frontend; npm run dev"
```

PowerShell uses `;` to separate commands, not `&&`.

## Support

- [Full Deployment Guide](./BFF-DEPLOYMENT.md)
- [Security Guide](./docs/bff-security-guide.md)
- [Implementation Summary](./BFF-IMPLEMENTATION-SUMMARY.md)
- [Deployment Checklist](./BFF-DEPLOYMENT-CHECKLIST.md)

---

**Status**: ✅ Ready to deploy  
**Estimated Time**: 5-10 minutes  
**Prerequisites**: Internal API stack deployed
