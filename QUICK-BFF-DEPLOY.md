# Quick BFF Deployment Reference

## One-Command Deployment

```powershell
# Deploy BFF to production
cd rds-operations-dashboard
./scripts/deploy-bff-production.ps1
```

## Validation

```powershell
# Validate deployment
./scripts/validate-bff-deployment.ps1
```

## Common Commands

### Build Only
```powershell
cd bff
npm run build
```

### Deploy Without Building
```powershell
./scripts/deploy-bff-production.ps1 -SkipBuild
```

### Custom Function/Region
```powershell
./scripts/deploy-bff-production.ps1 -FunctionName my-bff -Region us-east-1
```

### View Logs
```powershell
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow
```

### Test Health Endpoint
```powershell
curl https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod/health
```

## Troubleshooting

### Build Fails
```powershell
cd bff
rm -rf node_modules dist
npm install
npm run build
```

### Deployment Fails
```powershell
# Check AWS credentials
aws sts get-caller-identity

# Verify function exists
aws lambda get-function --function-name rds-dashboard-bff-prod --region ap-southeast-1
```

### Health Check Fails
```powershell
# Check logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow

# Check environment variables
aws lambda get-function-configuration --function-name rds-dashboard-bff-prod --region ap-southeast-1
```

## Rollback

```powershell
aws lambda update-function-code `
  --function-name rds-dashboard-bff-prod `
  --zip-file fileb://deployment.zip.backup `
  --region ap-southeast-1
```

## Full Documentation

See `docs/BFF-DEPLOYMENT-GUIDE.md` for complete documentation.
