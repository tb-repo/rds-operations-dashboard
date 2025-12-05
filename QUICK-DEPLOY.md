# 🚀 Quick Deploy Reference

## One-Command Deployment

```powershell
cd rds-operations-dashboard
.\scripts\deploy-latest-changes.ps1 -Environment dev
```

## Manual Deployment (3 Steps)

### 1. Infrastructure (5 minutes)
```powershell
cd infrastructure
cdk deploy RDSDashboard-Data-dev --require-approval never
cdk deploy RDSDashboard-IAM-dev --require-approval never
cdk deploy RDSDashboard-Compute-dev --require-approval never
cdk deploy RDSDashboard-API-dev --require-approval never
```

### 2. BFF (2 minutes)
```powershell
cd ../bff
npm install && npm run build
# Deploy to your hosting service
```

### 3. Frontend (2 minutes)
```powershell
cd ../frontend
npm install && npm run build
# Deploy to S3/CloudFront or hosting service
```

## Quick Verification

```powershell
# Test Lambda
aws lambda invoke --function-name rds-approval-workflow-dev response.json

# Test DynamoDB
aws dynamodb describe-table --table-name rds-approvals-dev

# Test Frontend
curl https://YOUR_FRONTEND_URL
```

## What You Get

✅ **Monitoring Dashboards**
- Real-time compute metrics
- Connection analytics
- Auto-refresh every 30s

✅ **Approval Workflow**
- Risk-based approvals
- Dual approval for high-risk ops
- Full audit trail

## Rollback (If Needed)

```powershell
cd infrastructure
cdk deploy RDSDashboard-Compute-dev --rollback
```

## Documentation

- Full Guide: `DEPLOYMENT-GUIDE-LATEST.md`
- Ready Check: `DEPLOYMENT-READY.md`
- Session Summary: `SESSION-SUMMARY-COMPLETE.md`

## Support

Issues? Check CloudWatch logs:
```powershell
aws logs tail /aws/lambda/rds-approval-workflow-dev --follow
```

---

**That's it! Deploy and enjoy your enhanced RDS Operations Dashboard! 🎉**
