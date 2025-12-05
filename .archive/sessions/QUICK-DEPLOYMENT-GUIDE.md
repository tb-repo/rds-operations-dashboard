# Quick Deployment Guide - Centralized Model

**Version:** 2.0.0  
**Model:** Centralized Deployment  
**Time:** 15-30 minutes

## Prerequisites

- AWS CLI configured
- Node.js 18+ installed
- AWS account with admin access

## Option 1: Automated Deployment (Fastest)

```powershell
# One command to deploy everything
cd rds-operations-dashboard/scripts
./deploy-all.ps1
```

## Option 2: Manual Deployment

### Step 1: Install Dependencies (2 min)

```powershell
cd rds-operations-dashboard/infrastructure
npm install
```

### Step 2: Bootstrap CDK (First Time Only - 3 min)

```powershell
npx cdk bootstrap
```

### Step 3: Deploy All Stacks (10-15 min)

```powershell
npx cdk deploy --all
```

### Step 4: Initialize S3 Bucket (2 min)

```powershell
cd ../scripts
./setup-s3-structure.ps1 -AccountId YOUR_ACCOUNT_ID
```

## Verify Deployment

```powershell
# List deployed stacks
npx cdk list

# Expected output:
# RDSDashboard-Data
# RDSDashboard-IAM
# RDSDashboard-Compute
# RDSDashboard-Orchestration
# RDSDashboard-API
# RDSDashboard-Monitoring
# RDSDashboard-Auth
# RDSDashboard-BFF
```

## Key Differences from Old Model

| Aspect | Old (Environment-Based) | New (Centralized) |
|--------|------------------------|-------------------|
| Deployments | 3+ (dev, staging, prod) | 1 (single) |
| Stack Names | `RDSDashboard-Data-prod` | `RDSDashboard-Data` |
| Resources | `rds-inventory-prod` | `rds-inventory` |
| Command | `./deploy-all.ps1 -Environment prod` | `./deploy-all.ps1` |
| Classification | Deployment environment | RDS instance tags |

## Troubleshooting

### CDK Not Found
```powershell
# Use npx instead
npx cdk deploy --all
```

### AWS Credentials Not Configured
```powershell
aws configure
```

### Stack Already Exists
```powershell
# Update existing stack
npx cdk deploy --all
```

## Next Steps

1. ✅ Deploy infrastructure
2. ⏭️ Set up cross-account roles (see docs/cross-account-setup.md)
3. ⏭️ Tag RDS instances with `Environment` tag
4. ⏭️ Test discovery and classification
5. ⏭️ Deploy frontend dashboard

## Documentation

- **Full Guide:** docs/deployment.md
- **Migration:** docs/migration-guide.md
- **Architecture:** INFRASTRUCTURE.md
- **Classification:** docs/environment-classification.md

## Support

For issues:
- Check CloudFormation events in AWS Console
- Review CDK logs: `npx cdk deploy --verbose`
- See docs/deployment.md for troubleshooting

---

**Ready to deploy?** Run `./deploy-all.ps1` and you're done! 🚀
