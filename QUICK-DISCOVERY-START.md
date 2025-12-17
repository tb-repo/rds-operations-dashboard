# Quick Start - Discover Your RDS Instances NOW!

## You Have:
- ✅ 2 AWS Accounts
- ✅ 3 Regions with RDS
- ✅ 3 Database Engines

## Make Dashboard Discover Them in 3 Steps:

### Option 1: Automated Script (Recommended) ⚡

```powershell
# Run the automated discovery activation script
cd rds-operations-dashboard
.\scripts\activate-discovery.ps1
```

**The script will:**
1. Ask for your second account ID
2. Ask which regions have RDS instances
3. Update configuration automatically
4. Verify cross-account access
5. Trigger discovery
6. Show you the results

**Time**: 2-3 minutes

### Option 2: Manual Steps 🔧

```powershell
# 1. Update configuration with second account
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
$config.cross_account.target_accounts += @{
    account_id = "<YOUR_SECOND_ACCOUNT_ID>"
    account_name = "Second-Account"
    enabled = $true
}
$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"

# 2. Ensure cross-account role exists in second account
# (See DISCOVERY-ACTIVATION-GUIDE.md for details)

# 3. Trigger discovery
.\run-discovery.ps1

# 4. Check results
aws dynamodb scan --table-name rds-inventory --region ap-southeast-1
```

**Time**: 5-10 minutes

## Verify Discovery Worked

### Check 1: View Logs
```powershell
aws logs tail /aws/lambda/rds-discovery --since 5m
```

**Look for:**
- ✅ "Scanning account: <ACCOUNT_ID>"
- ✅ "Found X RDS instances"
- ✅ "Successfully persisted X instances"

### Check 2: Query DynamoDB
```powershell
aws dynamodb scan `
  --table-name rds-inventory `
  --region ap-southeast-1 `
  --query 'Items[].{ID:instance_id.S,Account:account_id.S,Region:region.S,Engine:engine.S}' `
  --output table
```

**Expected:** Table showing all your RDS instances

### Check 3: Dashboard UI
1. Open: https://d2iqvvvqxqvqxq.cloudfront.net
2. Login
3. Go to "Instances"
4. See all your RDS instances!

## Troubleshooting

### Problem: "Access Denied" errors

**Solution:** Create cross-account role in second account

```powershell
# In second account
aws cloudformation create-stack `
  --stack-name RDSDashboard-CrossAccount `
  --template-body file://infrastructure/cross-account-role.yaml `
  --parameters ParameterKey=ManagementAccountId,ParameterValue=876595225096 `
  --capabilities CAPABILITY_NAMED_IAM `
  --profile second-account
```

### Problem: No instances found

**Solution:** Check if regions are enabled

```powershell
# View enabled regions
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
$config.cross_account.target_regions | Where-Object { $_.enabled -eq $true }
```

### Problem: Instances not in dashboard

**Solution:** Clear browser cache and refresh

```
Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
```

## What Happens During Discovery?

1. **Discovery Lambda** scans all enabled accounts and regions
2. **Finds RDS instances** using AWS RDS API
3. **Stores in DynamoDB** (rds-inventory table)
4. **Dashboard reads** from DynamoDB and displays

**Discovery runs automatically every hour**, but you can trigger it manually anytime!

## Files You Need

- `config/dashboard-config.json` - Configuration file
- `scripts/activate-discovery.ps1` - Automated setup script
- `run-discovery.ps1` - Manual discovery trigger
- `infrastructure/cross-account-role.yaml` - Cross-account role template

## Quick Commands Reference

```powershell
# Activate discovery (interactive)
.\scripts\activate-discovery.ps1

# Trigger discovery manually
.\run-discovery.ps1

# View discovery logs
aws logs tail /aws/lambda/rds-discovery --follow

# List discovered instances
aws dynamodb scan --table-name rds-inventory --region ap-southeast-1

# Test cross-account access
aws sts assume-role `
  --role-arn "arn:aws:iam::<ACCOUNT_ID>:role/RDSDashboardCrossAccountRole" `
  --role-session-name test `
  --external-id "rds-dashboard-unique-id-12345"
```

## Summary

**To discover your RDS instances:**

1. Run: `.\scripts\activate-discovery.ps1`
2. Enter your second account ID when prompted
3. Enter your regions when prompted
4. Wait 2-3 minutes
5. Open dashboard and see your instances!

**That's it!** 🚀

For detailed troubleshooting, see: `DISCOVERY-ACTIVATION-GUIDE.md`
