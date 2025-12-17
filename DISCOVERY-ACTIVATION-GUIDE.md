# Discovery Activation Guide - Make Your Dashboard Aware of RDS Instances

## Your Current Setup
- ✅ 2 AWS Accounts
- ✅ 3 Regions with RDS instances
- ✅ 3 Different database engines

## 4-Step Discovery Process

### Step 1: Update Configuration with Your Account IDs

First, let's update the configuration to include your second account:

```powershell
# Get your second account ID
$secondAccountId = Read-Host "Enter your second AWS account ID"

# Update configuration
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json

# Add or update the second account
$config.cross_account.target_accounts = @(
    @{
        account_id = "876595225096"  # Your main account
        account_name = "Main-Account"
        enabled = $true
    },
    @{
        account_id = $secondAccountId
        account_name = "Second-Account"
        enabled = $true
    }
)

# Save configuration
$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"

Write-Host "✓ Configuration updated with account: $secondAccountId" -ForegroundColor Green
```

### Step 2: Ensure Cross-Account Role Exists

The dashboard needs a cross-account IAM role in your second account to discover RDS instances.

**Check if role exists:**
```powershell
# Switch to your second account (if using AWS CLI profiles)
aws iam get-role `
  --role-name RDSDashboardCrossAccountRole `
  --profile second-account
```

**If role doesn't exist, create it:**

```powershell
# Deploy cross-account role in second account
aws cloudformation create-stack `
  --stack-name RDSDashboard-CrossAccount `
  --template-body file://infrastructure/cross-account-role.yaml `
  --parameters `
    ParameterKey=ManagementAccountId,ParameterValue=876595225096 `
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 `
  --capabilities CAPABILITY_NAMED_IAM `
  --region ap-southeast-1 `
  --profile second-account

# Wait for stack creation
aws cloudformation wait stack-create-complete `
  --stack-name RDSDashboard-CrossAccount `
  --region ap-southeast-1 `
  --profile second-account

Write-Host "✓ Cross-account role created successfully" -ForegroundColor Green
```

### Step 3: Verify Regions Are Enabled

Check which regions are currently enabled in your configuration:

```powershell
# View enabled regions
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
$enabledRegions = $config.cross_account.target_regions | Where-Object { $_.enabled -eq $true }

Write-Host "`nEnabled Regions:" -ForegroundColor Cyan
$enabledRegions | ForEach-Object {
    Write-Host "  - $($_.region) ($($_.region_name))" -ForegroundColor Green
}
```

**If your regions aren't in the list, add them:**

```powershell
# Example: Add a new region
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json

# Add your region (e.g., us-west-2)
$newRegion = @{
    region = "us-west-2"
    region_name = "Oregon"
    enabled = $true
    priority = 5
}

$config.cross_account.target_regions += $newRegion
$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"

Write-Host "✓ Region added to configuration" -ForegroundColor Green
```

### Step 4: Trigger Discovery

Now trigger the discovery process to scan all accounts and regions:

```powershell
# Run discovery
.\run-discovery.ps1
```

**Or trigger via AWS CLI:**

```powershell
# Invoke discovery Lambda directly
aws lambda invoke `
  --function-name rds-discovery `
  --payload '{}' `
  --region ap-southeast-1 `
  response.json

# Check response
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10

Write-Host "`n✓ Discovery triggered successfully" -ForegroundColor Green
```

## Verification Steps

### 1. Check Discovery Logs

```powershell
# View discovery logs
aws logs tail /aws/lambda/rds-discovery --since 5m --follow
```

**What to look for:**
- ✅ "Scanning account: <ACCOUNT_ID>"
- ✅ "Scanning region: <REGION>"
- ✅ "Found X RDS instances"
- ✅ "Successfully persisted X instances"
- ❌ "AccessDenied" errors (means cross-account role issue)

### 2. Check DynamoDB Table

```powershell
# List discovered instances
aws dynamodb scan `
  --table-name rds-inventory `
  --region ap-southeast-1 `
  --query 'Items[].{ID:instance_id.S,Account:account_id.S,Region:region.S,Engine:engine.S}' `
  --output table
```

**Expected output:**
```
-----------------------------------------------------------------
|                          ScanTable                            |
+----------------+---------------+----------------+--------------+
|    Account     |    Engine     |       ID       |    Region    |
+----------------+---------------+----------------+--------------+
|  876595225096  |  postgres     |  my-db-1       |  us-east-1   |
|  876595225096  |  mysql        |  my-db-2       |  eu-west-1   |
|  123456789012  |  mariadb      |  test-db-1     |  ap-south-1  |
+----------------+---------------+----------------+--------------+
```

### 3. Check Dashboard UI

1. Open: https://d2iqvvvqxqvqxq.cloudfront.net
2. Login with your credentials
3. Go to "Instances" page
4. Verify you see:
   - ✅ Instances from both accounts
   - ✅ Instances from all 3 regions
   - ✅ All 3 database engines (postgres, mysql, mariadb)
   - ✅ Correct account IDs displayed
   - ✅ Correct region names displayed

## Troubleshooting

### Issue 1: No Instances Discovered

**Symptoms:**
- Discovery runs but finds 0 instances
- DynamoDB table is empty

**Solutions:**

```powershell
# 1. Verify RDS instances exist
aws rds describe-db-instances --region ap-southeast-1
aws rds describe-db-instances --region eu-west-2
aws rds describe-db-instances --region us-east-1

# 2. Check if regions are enabled in config
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
$config.cross_account.target_regions | Where-Object { $_.enabled -eq $true }

# 3. Check discovery Lambda environment variables
aws lambda get-function-configuration `
  --function-name rds-discovery `
  --query 'Environment.Variables' `
  --output json
```

### Issue 2: Access Denied Errors

**Symptoms:**
- Logs show "AccessDenied" or "AssumeRole" errors
- Only instances from main account are discovered

**Solutions:**

```powershell
# 1. Verify cross-account role exists
aws iam get-role `
  --role-name RDSDashboardCrossAccountRole `
  --profile second-account

# 2. Test assuming the role
aws sts assume-role `
  --role-arn "arn:aws:iam::<SECOND_ACCOUNT_ID>:role/RDSDashboardCrossAccountRole" `
  --role-session-name test `
  --external-id "rds-dashboard-unique-id-12345"

# 3. Check role trust policy
aws iam get-role `
  --role-name RDSDashboardCrossAccountRole `
  --query 'Role.AssumeRolePolicyDocument' `
  --profile second-account
```

**Expected trust policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::876595225096:root"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "rds-dashboard-unique-id-12345"
      }
    }
  }]
}
```

### Issue 3: Wrong Account ID Displayed

**Symptoms:**
- All instances show the same account ID
- Account ID is incorrect

**Solutions:**

```powershell
# 1. Check Lambda environment variable
aws lambda get-function-configuration `
  --function-name rds-discovery `
  --query 'Environment.Variables.AWS_ACCOUNT_ID' `
  --output text

# 2. Update if missing or incorrect
aws lambda update-function-configuration `
  --function-name rds-discovery `
  --environment "Variables={AWS_ACCOUNT_ID=876595225096,...}"

# 3. Re-run discovery
.\run-discovery.ps1
```

### Issue 4: Instances Not Showing in Dashboard

**Symptoms:**
- Instances in DynamoDB but not in dashboard UI
- Dashboard shows "No instances found"

**Solutions:**

```powershell
# 1. Check BFF API
Invoke-WebRequest -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances" `
  -Headers @{"Authorization"="Bearer <YOUR_TOKEN>"}

# 2. Check browser console for errors
# Open DevTools (F12) and look for API errors

# 3. Clear browser cache and refresh
# Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)

# 4. Check BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --since 5m --follow
```

## Complete Discovery Script

Here's a complete script that does everything:

```powershell
# complete-discovery-setup.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$SecondAccountId,
    
    [Parameter(Mandatory=$true)]
    [string[]]$Regions
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  RDS Dashboard Discovery Setup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Step 1: Update configuration
Write-Host "`n[1/4] Updating configuration..." -ForegroundColor Yellow
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json

# Update accounts
$config.cross_account.target_accounts = @(
    @{
        account_id = "876595225096"
        account_name = "Main-Account"
        enabled = $true
    },
    @{
        account_id = $SecondAccountId
        account_name = "Second-Account"
        enabled = $true
    }
)

# Ensure regions are enabled
foreach ($region in $Regions) {
    $existingRegion = $config.cross_account.target_regions | Where-Object { $_.region -eq $region }
    if ($existingRegion) {
        $existingRegion.enabled = $true
    }
}

$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"
Write-Host "✓ Configuration updated" -ForegroundColor Green

# Step 2: Verify cross-account role
Write-Host "`n[2/4] Verifying cross-account role..." -ForegroundColor Yellow
try {
    $roleArn = "arn:aws:iam::${SecondAccountId}:role/RDSDashboardCrossAccountRole"
    aws sts assume-role `
        --role-arn $roleArn `
        --role-session-name test `
        --external-id "rds-dashboard-unique-id-12345" `
        --query 'Credentials.AccessKeyId' `
        --output text | Out-Null
    Write-Host "✓ Cross-account role verified" -ForegroundColor Green
} catch {
    Write-Host "✗ Cross-account role not accessible" -ForegroundColor Red
    Write-Host "Please create the role using: infrastructure/cross-account-role.yaml" -ForegroundColor Yellow
    exit 1
}

# Step 3: Verify RDS instances exist
Write-Host "`n[3/4] Verifying RDS instances..." -ForegroundColor Yellow
$totalInstances = 0
foreach ($region in $Regions) {
    $instances = aws rds describe-db-instances --region $region --query 'DBInstances[].DBInstanceIdentifier' --output text
    $count = ($instances -split '\s+').Count
    $totalInstances += $count
    Write-Host "  $region: $count instances" -ForegroundColor Gray
}
Write-Host "✓ Found $totalInstances total instances" -ForegroundColor Green

# Step 4: Trigger discovery
Write-Host "`n[4/4] Triggering discovery..." -ForegroundColor Yellow
aws lambda invoke `
    --function-name rds-discovery `
    --payload '{}' `
    --region ap-southeast-1 `
    response.json | Out-Null

$response = Get-Content response.json | ConvertFrom-Json
Write-Host "✓ Discovery completed" -ForegroundColor Green
Write-Host "  Instances discovered: $($response.total_instances)" -ForegroundColor Gray
Write-Host "  Accounts scanned: $($response.accounts_scanned)" -ForegroundColor Gray
Write-Host "  Regions scanned: $($response.regions_scanned)" -ForegroundColor Gray

# Step 5: Verify in DynamoDB
Write-Host "`n[5/5] Verifying in DynamoDB..." -ForegroundColor Yellow
$dbInstances = aws dynamodb scan `
    --table-name rds-inventory `
    --region ap-southeast-1 `
    --query 'Count' `
    --output text

Write-Host "✓ $dbInstances instances in DynamoDB" -ForegroundColor Green

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  Discovery Setup Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Open dashboard: https://d2iqvvvqxqvqxq.cloudfront.net"
Write-Host "2. Login and verify all instances are visible"
Write-Host "3. Check that account IDs and regions are correct"
```

**Usage:**
```powershell
.\complete-discovery-setup.ps1 `
  -SecondAccountId "123456789012" `
  -Regions @("ap-southeast-1", "eu-west-2", "us-east-1")
```

## Summary

To make your dashboard discover your RDS instances:

1. **Update config** with your second account ID
2. **Create cross-account role** in second account
3. **Verify regions** are enabled in configuration
4. **Run discovery** using `.\run-discovery.ps1`
5. **Verify** in dashboard UI

The discovery process runs automatically every hour, but you can trigger it manually anytime.

Your instances should appear in the dashboard within 2-3 minutes after running discovery! 🚀
