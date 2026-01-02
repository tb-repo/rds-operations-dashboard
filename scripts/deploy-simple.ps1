# Simple deployment script for API Gateway clean URLs

Write-Host "=== API Gateway Clean URL Deployment ===" -ForegroundColor Cyan
Write-Host "Deploying infrastructure changes to remove /prod stage suffixes" -ForegroundColor Yellow
Write-Host ""

# Check if we're in the right directory
if (-not (Test-Path "infrastructure")) {
    Write-Host "❌ Error: infrastructure directory not found" -ForegroundColor Red
    Write-Host "Please run this script from the rds-operations-dashboard root directory" -ForegroundColor Yellow
    exit 1
}

# Check if CDK is available
try {
    $cdkVersion = cdk --version 2>$null
    Write-Host "✅ CDK Version: $cdkVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: AWS CDK not found" -ForegroundColor Red
    Write-Host "Please install AWS CDK: npm install -g aws-cdk" -ForegroundColor Yellow
    exit 1
}

# Change to infrastructure directory
Set-Location infrastructure

Write-Host "📋 Deployment Plan:" -ForegroundColor Cyan
Write-Host "1. Deploy API Stack (RDSDashboard-API) with `$default stage" -ForegroundColor White
Write-Host "2. Deploy BFF Stack (RDSDashboard-BFF) with `$default stage" -ForegroundColor White
Write-Host "3. Validate new clean URLs" -ForegroundColor White
Write-Host ""

# Confirm deployment
Write-Host "⚠️  This will deploy infrastructure changes to AWS" -ForegroundColor Yellow
$confirm = Read-Host "Continue with deployment? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Deployment cancelled" -ForegroundColor Yellow
    Set-Location ..
    exit 0
}

Write-Host ""
Write-Host "🚀 Starting deployment..." -ForegroundColor Green

# Deploy API Stack
Write-Host ""
Write-Host "--- Deploying API Stack ---" -ForegroundColor Cyan
try {
    cdk deploy RDSDashboard-API --require-approval never
    Write-Host "✅ API Stack deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ API Stack deployment failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Set-Location ..
    exit 1
}

# Deploy BFF Stack
Write-Host ""
Write-Host "--- Deploying BFF Stack ---" -ForegroundColor Cyan
try {
    cdk deploy RDSDashboard-BFF --require-approval never
    Write-Host "✅ BFF Stack deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ BFF Stack deployment failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Set-Location ..
    exit 1
}

# Return to root directory
Set-Location ..

Write-Host ""
Write-Host "🎉 Deployment Complete!" -ForegroundColor Green
Write-Host ""

# Validate deployment
Write-Host "--- Validating Clean URLs ---" -ForegroundColor Cyan
if (Test-Path "scripts\validate-clean-urls.ps1") {
    .\scripts\validate-clean-urls.ps1 -Verbose
} else {
    Write-Host "⚠️  Validation script not found. Please test endpoints manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ API Gateway stage simplification deployment complete!" -ForegroundColor Green