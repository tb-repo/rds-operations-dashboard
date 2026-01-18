# Diagnose Cross-Account Discovery Issues
# This script checks if cross-account discovery is properly configured

param(
    [string]$SecondaryAccount = "817214535871",
    [string]$RoleName = "RDSDashboardCrossAccountRole",
    [string]$ExternalId = "rds-dashboard-unique-external-id",
    [string]$Region = "ap-southeast-1"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cross-Account Discovery Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get current account
Write-Host "1. Checking current account..." -ForegroundColor Yellow
$currentAccount = aws sts get-caller-identity --query 'Account' --output text
Write-Host "   Current Account: $currentAccount" -ForegroundColor Green
Write-Host ""

# Check discovery Lambda configuration
Write-Host "2. Checking discovery Lambda configuration..." -ForegroundColor Yellow
$discoveryEnv = aws lambda get-function-configuration `
    --function-name rds-discovery-prod `
    --region $Region `
    --query 'Environment.Variables' `
    --output json | ConvertFrom-Json

Write-Host "   TARGET_ACCOUNTS: $($discoveryEnv.TARGET_ACCOUNTS)" -ForegroundColor Green
Write-Host "   TARGET_REGIONS: $($discoveryEnv.TARGET_REGIONS)" -ForegroundColor Green
Write-Host "   CROSS_ACCOUNT_ROLE_NAME: $($discoveryEnv.CROSS_ACCOUNT_ROLE_NAME)" -ForegroundColor Green
Write-Host "   EXTERNAL_ID: $($discoveryEnv.EXTERNAL_ID)" -ForegroundColor Green
Write-Host ""

# Try to assume cross-account role
Write-Host "3. Testing cross-account role assumption..." -ForegroundColor Yellow
$roleArn = "arn:aws:iam::${SecondaryAccount}:role/${RoleName}"
Write-Host "   Role ARN: $roleArn" -ForegroundColor Cyan

try {
    $assumeRole = aws sts assume-role `
        --role-arn $roleArn `
        --role-session-name "cross-account-test" `
        --external-id $ExternalId `
        --duration-seconds 900 `
        --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Successfully assumed cross-account role!" -ForegroundColor Green
        
        # Parse credentials
        $credentials = $assumeRole | ConvertFrom-Json
        $accessKey = $credentials.Credentials.AccessKeyId
        $secretKey = $credentials.Credentials.SecretAccessKey
        $sessionToken = $credentials.Credentials.SessionToken
        
        # Test RDS access with assumed role
        Write-Host ""
        Write-Host "4. Testing RDS access in secondary account..." -ForegroundColor Yellow
        
        $env:AWS_ACCESS_KEY_ID = $accessKey
        $env:AWS_SECRET_ACCESS_KEY = $secretKey
        $env:AWS_SESSION_TOKEN = $sessionToken
        
        $rdsInstances = aws rds describe-db-instances `
            --region $Region `
            --query 'DBInstances[].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine}' `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $instances = $rdsInstances | ConvertFrom-Json
            Write-Host "   ✅ Successfully accessed RDS in secondary account!" -ForegroundColor Green
            Write-Host "   Found $($instances.Count) RDS instance(s):" -ForegroundColor Green
            foreach ($instance in $instances) {
                Write-Host "      - $($instance.ID) ($($instance.Engine), $($instance.Status))" -ForegroundColor White
            }
        } else {
            Write-Host "   ❌ Failed to access RDS in secondary account" -ForegroundColor Red
            Write-Host "   Error: $rdsInstances" -ForegroundColor Red
        }
        
        # Clear temporary credentials
        Remove-Item Env:AWS_ACCESS_KEY_ID
        Remove-Item Env:AWS_SECRET_ACCESS_KEY
        Remove-Item Env:AWS_SESSION_TOKEN
        
    } else {
        Write-Host "   ❌ Failed to assume cross-account role" -ForegroundColor Red
        Write-Host "   Error: $assumeRole" -ForegroundColor Red
        Write-Host ""
        Write-Host "   Possible causes:" -ForegroundColor Yellow
        Write-Host "   1. Role does not exist in account $SecondaryAccount" -ForegroundColor White
        Write-Host "   2. Trust policy does not allow account $currentAccount" -ForegroundColor White
        Write-Host "   3. External ID mismatch" -ForegroundColor White
        Write-Host "   4. Role lacks necessary permissions" -ForegroundColor White
    }
} catch {
    Write-Host "   ❌ Error during role assumption: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "5. Checking inventory table for cross-account instances..." -ForegroundColor Yellow
$inventoryItems = aws dynamodb scan `
    --table-name rds-inventory-prod `
    --region $Region `
    --query 'Items[].{ID:instance_id.S,Account:account_id.S,Region:region.S}' `
    --output json | ConvertFrom-Json

Write-Host "   Total instances in inventory: $($inventoryItems.Count)" -ForegroundColor Green
$secondaryAccountInstances = $inventoryItems | Where-Object { $_.Account -eq $SecondaryAccount }
Write-Host "   Instances from secondary account ($SecondaryAccount): $($secondaryAccountInstances.Count)" -ForegroundColor $(if ($secondaryAccountInstances.Count -gt 0) { "Green" } else { "Red" })

if ($secondaryAccountInstances.Count -gt 0) {
    foreach ($instance in $secondaryAccountInstances) {
        Write-Host "      - $($instance.ID) in $($instance.Region)" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Diagnostic Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($LASTEXITCODE -eq 0 -and $secondaryAccountInstances.Count -gt 0) {
    Write-Host "✅ Cross-account discovery appears to be working!" -ForegroundColor Green
    Write-Host "   - Role assumption successful" -ForegroundColor Green
    Write-Host "   - RDS access successful" -ForegroundColor Green
    Write-Host "   - Instances found in inventory" -ForegroundColor Green
} else {
    Write-Host "❌ Cross-account discovery has issues:" -ForegroundColor Red
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   - Cannot assume cross-account role" -ForegroundColor Red
    }
    if ($secondaryAccountInstances.Count -eq 0) {
        Write-Host "   - No instances from secondary account in inventory" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Deploy cross-account role in account $SecondaryAccount" -ForegroundColor White
    Write-Host "2. Run discovery Lambda manually to test" -ForegroundColor White
    Write-Host "3. Check CloudWatch logs for detailed errors" -ForegroundColor White
}

Write-Host ""
