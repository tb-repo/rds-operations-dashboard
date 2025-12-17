# Quick script to add your second AWS account to the dashboard

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Add Second Account to Dashboard" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Get second account ID
Write-Host "`nEnter your second AWS account ID:" -ForegroundColor Yellow
$secondAccountId = Read-Host "Account ID"

if (-not $secondAccountId -or $secondAccountId.Length -ne 12) {
    Write-Host "✗ Invalid account ID. Must be 12 digits." -ForegroundColor Red
    exit 1
}

# Get account name
Write-Host "`nEnter a friendly name for this account (e.g., 'Production', 'Test'):" -ForegroundColor Yellow
$accountName = Read-Host "Account Name"

if (-not $accountName) {
    $accountName = "Account-$secondAccountId"
}

# Update configuration
Write-Host "`nUpdating configuration..." -ForegroundColor Yellow

$configPath = "config/dashboard-config.json"
$config = Get-Content $configPath | ConvertFrom-Json

# Check if account already exists
$existingAccount = $config.cross_account.target_accounts | Where-Object { $_.account_id -eq $secondAccountId }

if ($existingAccount) {
    Write-Host "Account $secondAccountId already exists in configuration" -ForegroundColor Gray
    $existingAccount.enabled = $true
    $existingAccount.account_name = $accountName
    Write-Host "✓ Updated existing account" -ForegroundColor Green
} else {
    # Add new account
    $newAccount = [PSCustomObject]@{
        account_id = $secondAccountId
        account_name = $accountName
        enabled = $true
    }
    
    $config.cross_account.target_accounts += $newAccount
    Write-Host "✓ Added new account: $secondAccountId ($accountName)" -ForegroundColor Green
}

# Save configuration
$config | ConvertTo-Json -Depth 10 | Set-Content $configPath

Write-Host "`n✓ Configuration saved!" -ForegroundColor Green

# Show next steps
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n1. Create cross-account role in account $secondAccountId" -ForegroundColor Yellow
Write-Host "   Run this command in the second account:" -ForegroundColor Gray
Write-Host @"

aws cloudformation create-stack \
  --stack-name RDSDashboard-CrossAccount \
  --template-body file://infrastructure/cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=876595225096 \
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1

"@ -ForegroundColor White

Write-Host "2. Wait for stack creation (2-3 minutes)" -ForegroundColor Yellow

Write-Host "`n3. Verify cross-account access:" -ForegroundColor Yellow
Write-Host @"
aws sts assume-role \
  --role-arn "arn:aws:iam::${secondAccountId}:role/RDSDashboardCrossAccountRole" \
  --role-session-name test \
  --external-id "rds-dashboard-unique-id-12345"
"@ -ForegroundColor White

Write-Host "`n4. Trigger discovery:" -ForegroundColor Yellow
Write-Host "   .\run-discovery.ps1" -ForegroundColor White

Write-Host "`n5. Check dashboard:" -ForegroundColor Yellow
Write-Host "   https://d2iqvvvqxqvqxq.cloudfront.net" -ForegroundColor White

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Configuration updated successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
