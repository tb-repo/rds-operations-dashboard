# Activate Discovery for Multi-Account RDS Instances
# This script configures and triggers discovery for your RDS instances

param(
    [Parameter(Mandatory=$false)]
    [string]$SecondAccountId,
    
    [Parameter(Mandatory=$false)]
    [string[]]$AdditionalRegions,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipRoleCheck,
    
    [Parameter(Mandatory=$false)]
    [switch]$TriggerDiscovery = $true
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  RDS Dashboard - Discovery Activation" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Get current account
$currentAccount = aws sts get-caller-identity --query Account --output text
Write-Host "`nCurrent Account: $currentAccount" -ForegroundColor Green

# Step 1: Interactive account collection if not provided
if (-not $SecondAccountId) {
    Write-Host "`n[Step 1] Account Configuration" -ForegroundColor Yellow
    $hasSecondAccount = Read-Host "Do you have a second AWS account with RDS instances? (yes/no)"
    
    if ($hasSecondAccount -eq "yes") {
        $SecondAccountId = Read-Host "Enter the second account ID"
    }
}

# Step 2: Interactive region collection
if (-not $AdditionalRegions) {
    Write-Host "`n[Step 2] Region Configuration" -ForegroundColor Yellow
    Write-Host "Current enabled regions:" -ForegroundColor Gray
    
    $config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
    $config.cross_account.target_regions | Where-Object { $_.enabled -eq $true } | ForEach-Object {
        Write-Host "  - $($_.region) ($($_.region_name))" -ForegroundColor Gray
    }
    
    $addRegions = Read-Host "`nDo you want to add more regions? (yes/no)"
    if ($addRegions -eq "yes") {
        Write-Host "Enter regions separated by commas (e.g., us-west-2,eu-central-1):" -ForegroundColor Gray
        $regionsInput = Read-Host
        $AdditionalRegions = $regionsInput -split ',' | ForEach-Object { $_.Trim() }
    }
}

# Step 3: Update configuration
Write-Host "`n[Step 3] Updating Configuration" -ForegroundColor Yellow

$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json

# Update accounts
if ($SecondAccountId) {
    $existingAccount = $config.cross_account.target_accounts | Where-Object { $_.account_id -eq $SecondAccountId }
    
    if (-not $existingAccount) {
        Write-Host "Adding account: $SecondAccountId" -ForegroundColor Gray
        $newAccount = @{
            account_id = $SecondAccountId
            account_name = "Account-$SecondAccountId"
            enabled = $true
        }
        
        # Convert to array if needed
        if ($config.cross_account.target_accounts -isnot [Array]) {
            $config.cross_account.target_accounts = @($config.cross_account.target_accounts)
        }
        
        $config.cross_account.target_accounts += $newAccount
        Write-Host "✓ Account added to configuration" -ForegroundColor Green
    } else {
        $existingAccount.enabled = $true
        Write-Host "✓ Account already in configuration (enabled)" -ForegroundColor Green
    }
}

# Update regions
if ($AdditionalRegions) {
    foreach ($region in $AdditionalRegions) {
        $existingRegion = $config.cross_account.target_regions | Where-Object { $_.region -eq $region }
        
        if (-not $existingRegion) {
            Write-Host "Adding region: $region" -ForegroundColor Gray
            $priority = ($config.cross_account.target_regions | Measure-Object -Property priority -Maximum).Maximum + 1
            
            $newRegion = @{
                region = $region
                region_name = $region
                enabled = $true
                priority = $priority
            }
            
            if ($config.cross_account.target_regions -isnot [Array]) {
                $config.cross_account.target_regions = @($config.cross_account.target_regions)
            }
            
            $config.cross_account.target_regions += $newRegion
            Write-Host "✓ Region added: $region" -ForegroundColor Green
        } else {
            $existingRegion.enabled = $true
            Write-Host "✓ Region already configured: $region (enabled)" -ForegroundColor Green
        }
    }
}

# Save configuration
$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"
Write-Host "✓ Configuration saved" -ForegroundColor Green

# Step 4: Verify cross-account access
if ($SecondAccountId -and -not $SkipRoleCheck) {
    Write-Host "`n[Step 4] Verifying Cross-Account Access" -ForegroundColor Yellow
    
    $roleArn = "arn:aws:iam::${SecondAccountId}:role/RDSDashboardCrossAccountRole"
    
    try {
        $testResult = aws sts assume-role `
            --role-arn $roleArn `
            --role-session-name test-discovery `
            --external-id "rds-dashboard-unique-id-12345" `
            --query 'Credentials.AccessKeyId' `
            --output text 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Cross-account role accessible" -ForegroundColor Green
        } else {
            throw "Role not accessible"
        }
    } catch {
        Write-Host "✗ Cannot access cross-account role" -ForegroundColor Red
        Write-Host "`nThe role may not exist. Create it using:" -ForegroundColor Yellow
        Write-Host @"
aws cloudformation create-stack \
  --stack-name RDSDashboard-CrossAccount \
  --template-body file://infrastructure/cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=$currentAccount \
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1 \
  --profile <second-account-profile>
"@ -ForegroundColor Gray
        
        $continue = Read-Host "`nContinue anyway? (yes/no)"
        if ($continue -ne "yes") {
            exit 1
        }
    }
}

# Step 5: List RDS instances
Write-Host "`n[Step 5] Scanning for RDS Instances" -ForegroundColor Yellow

$enabledRegions = $config.cross_account.target_regions | Where-Object { $_.enabled -eq $true }
$totalInstances = 0

foreach ($region in $enabledRegions) {
    try {
        $instances = aws rds describe-db-instances `
            --region $region.region `
            --query 'DBInstances[].DBInstanceIdentifier' `
            --output text 2>$null
        
        if ($instances) {
            $count = ($instances -split '\s+' | Where-Object { $_ }).Count
            $totalInstances += $count
            Write-Host "  $($region.region): $count instances" -ForegroundColor Gray
        } else {
            Write-Host "  $($region.region): 0 instances" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  $($region.region): Unable to scan" -ForegroundColor Yellow
    }
}

Write-Host "✓ Found $totalInstances total instances in current account" -ForegroundColor Green

# Step 6: Trigger discovery
if ($TriggerDiscovery) {
    Write-Host "`n[Step 6] Triggering Discovery" -ForegroundColor Yellow
    
    try {
        aws lambda invoke `
            --function-name rds-discovery `
            --payload '{}' `
            --region ap-southeast-1 `
            response.json | Out-Null
        
        if (Test-Path response.json) {
            $response = Get-Content response.json | ConvertFrom-Json
            
            Write-Host "✓ Discovery completed successfully" -ForegroundColor Green
            Write-Host "`nDiscovery Results:" -ForegroundColor Cyan
            Write-Host "  Total Instances: $($response.total_instances)" -ForegroundColor Gray
            Write-Host "  Accounts Scanned: $($response.accounts_scanned)" -ForegroundColor Gray
            Write-Host "  Regions Scanned: $($response.regions_scanned)" -ForegroundColor Gray
            
            if ($response.errors -and $response.errors.Count -gt 0) {
                Write-Host "`nErrors encountered:" -ForegroundColor Yellow
                $response.errors | ForEach-Object {
                    Write-Host "  - Account $($_.account_id): $($_.type)" -ForegroundColor Yellow
                }
            }
            
            Remove-Item response.json -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "✗ Failed to trigger discovery" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Step 7: Verify in DynamoDB
Write-Host "`n[Step 7] Verifying Discovered Instances" -ForegroundColor Yellow

try {
    $dbCount = aws dynamodb scan `
        --table-name rds-inventory `
        --region ap-southeast-1 `
        --select COUNT `
        --query 'Count' `
        --output text
    
    Write-Host "✓ $dbCount instances stored in DynamoDB" -ForegroundColor Green
    
    if ($dbCount -gt 0) {
        Write-Host "`nSample instances:" -ForegroundColor Cyan
        aws dynamodb scan `
            --table-name rds-inventory `
            --region ap-southeast-1 `
            --max-items 5 `
            --query 'Items[].{ID:instance_id.S,Account:account_id.S,Region:region.S,Engine:engine.S,Status:status.S}' `
            --output table
    }
} catch {
    Write-Host "✗ Unable to query DynamoDB" -ForegroundColor Red
}

# Summary
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  Discovery Activation Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan

Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
Write-Host "  Enabled Accounts: $($config.cross_account.target_accounts.Count)" -ForegroundColor Gray
$config.cross_account.target_accounts | Where-Object { $_.enabled } | ForEach-Object {
    Write-Host "    - $($_.account_id) ($($_.account_name))" -ForegroundColor Gray
}

Write-Host "`n  Enabled Regions: $(($enabledRegions | Measure-Object).Count)" -ForegroundColor Gray
$enabledRegions | ForEach-Object {
    Write-Host "    - $($_.region) ($($_.region_name))" -ForegroundColor Gray
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Open dashboard: https://d2iqvvvqxqvqxq.cloudfront.net" -ForegroundColor White
Write-Host "2. Login with your credentials" -ForegroundColor White
Write-Host "3. Navigate to 'Instances' page" -ForegroundColor White
Write-Host "4. Verify all instances are visible" -ForegroundColor White

Write-Host "`nTroubleshooting:" -ForegroundColor Cyan
Write-Host "- View logs: aws logs tail /aws/lambda/rds-discovery --follow" -ForegroundColor White
Write-Host "- Re-run discovery: .\run-discovery.ps1" -ForegroundColor White
Write-Host "- Check guide: DISCOVERY-ACTIVATION-GUIDE.md" -ForegroundColor White

Write-Host "`n==================================================" -ForegroundColor Cyan
