# Deploy Cross-Account Role to Secondary Account
# This script deploys the IAM role needed for cross-account RDS discovery

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetAccount,
    
    [string]$ManagementAccount = "876595225096",
    [string]$ExternalId = "rds-dashboard-unique-external-id",
    [string]$RoleName = "RDSDashboardCrossAccountRole",
    [string]$Region = "ap-southeast-1",
    [string]$ProfileName = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploy Cross-Account Role" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Target Account: $TargetAccount" -ForegroundColor White
Write-Host "  Management Account: $ManagementAccount" -ForegroundColor White
Write-Host "  Role Name: $RoleName" -ForegroundColor White
Write-Host "  External ID: $ExternalId" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
if ($ProfileName) {
    Write-Host "  AWS Profile: $ProfileName" -ForegroundColor White
}
Write-Host ""

# Build AWS CLI command with optional profile
$awsCmd = "aws"
$profileArg = if ($ProfileName) { "--profile $ProfileName" } else { "" }

Write-Host "⚠️  IMPORTANT: You must have credentials configured for account $TargetAccount" -ForegroundColor Yellow
Write-Host ""
Write-Host "Options to configure credentials:" -ForegroundColor Yellow
Write-Host "1. Use AWS CLI profile: --profile <profile-name>" -ForegroundColor White
Write-Host "2. Set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY" -ForegroundColor White
Write-Host "3. Use AWS SSO: aws sso login --profile <profile-name>" -ForegroundColor White
Write-Host ""

$continue = Read-Host "Do you have credentials configured for account $TargetAccount? (yes/no)"
if ($continue -ne "yes") {
    Write-Host "Please configure credentials and run this script again." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Verifying credentials..." -ForegroundColor Yellow

# Verify we're in the correct account
$currentAccount = if ($ProfileName) {
    aws sts get-caller-identity --profile $ProfileName --query 'Account' --output text
} else {
    aws sts get-caller-identity --query 'Account' --output text
}

if ($currentAccount -ne $TargetAccount) {
    Write-Host "❌ ERROR: Current credentials are for account $currentAccount, not $TargetAccount" -ForegroundColor Red
    Write-Host "Please configure credentials for account $TargetAccount and try again." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Verified credentials for account $TargetAccount" -ForegroundColor Green
Write-Host ""

# Deploy CloudFormation stack
Write-Host "Deploying CloudFormation stack..." -ForegroundColor Yellow

$stackName = "rds-dashboard-cross-account-role"
$templateFile = "infrastructure/cross-account-role.yaml"

$deployCmd = @"
aws cloudformation deploy ``
    --template-file $templateFile ``
    --stack-name $stackName ``
    --parameter-overrides ``
        ManagementAccountId=$ManagementAccount ``
        ExternalId=$ExternalId ``
        RoleName=$RoleName ``
    --capabilities CAPABILITY_NAMED_IAM ``
    --region $Region
"@

if ($ProfileName) {
    $deployCmd += " --profile $ProfileName"
}

Write-Host "Executing:" -ForegroundColor Cyan
Write-Host $deployCmd -ForegroundColor Gray
Write-Host ""

Invoke-Expression $deployCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ CloudFormation deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ CloudFormation stack deployed successfully!" -ForegroundColor Green
Write-Host ""

# Get stack outputs
Write-Host "Retrieving stack outputs..." -ForegroundColor Yellow

$outputs = if ($ProfileName) {
    aws cloudformation describe-stacks `
        --stack-name $stackName `
        --region $Region `
        --profile $ProfileName `
        --query 'Stacks[0].Outputs' `
        --output json | ConvertFrom-Json
} else {
    aws cloudformation describe-stacks `
        --stack-name $stackName `
        --region $Region `
        --query 'Stacks[0].Outputs' `
        --output json | ConvertFrom-Json
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($output in $outputs) {
    Write-Host "$($output.OutputKey): $($output.OutputValue)" -ForegroundColor White
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Test role assumption from management account:" -ForegroundColor White
Write-Host "   aws sts assume-role --role-arn arn:aws:iam::${TargetAccount}:role/${RoleName} --role-session-name test --external-id $ExternalId" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Run discovery diagnostic:" -ForegroundColor White
Write-Host "   ./scripts/diagnose-cross-account-discovery.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Trigger discovery Lambda:" -ForegroundColor White
Write-Host "   aws lambda invoke --function-name rds-discovery-prod --region $Region response.json" -ForegroundColor Gray
Write-Host ""
