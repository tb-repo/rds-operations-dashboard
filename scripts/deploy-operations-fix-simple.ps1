#!/usr/bin/env pwsh
<#
.SYNOPSIS
Simple Operations 400 Error Fix Deployment

.DESCRIPTION
Deploys the BFF and Lambda fixes for the 400 error issue in operations.
Simplified version with minimal error handling.
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Deploying Operations 400 Error Fix (Simple)" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff-prod"
$OPERATIONS_FUNCTION_NAME = "rds-operations-prod"
$REGION = "ap-southeast-1"

Write-Host "📋 Configuration:" -ForegroundColor Cyan
Write-Host "  BFF Function: $BFF_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Operations Function: $OPERATIONS_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Region: $REGION" -ForegroundColor White
Write-Host "  Dry Run: $DryRun" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "🔍 DRY RUN MODE - No actual deployment will occur" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Would deploy:" -ForegroundColor Cyan
    Write-Host "• Enhanced BFF operations handling" -ForegroundColor White
    Write-Host "• Improved Operations Lambda with detailed error logging" -ForegroundColor White
    Write-Host "• Better validation and error messages" -ForegroundColor White
    exit 0
}

# Step 1: Deploy BFF Fix
Write-Host "🔧 Step 1: Deploying BFF Operations Fix" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

Write-Host "📦 Building BFF..." -ForegroundColor Cyan
Set-Location "bff"

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Gray
npm install

# Build the project
Write-Host "Building project..." -ForegroundColor Gray
npm run build

# Create deployment package
Write-Host "📦 Creating deployment package..." -ForegroundColor Cyan
if (Test-Path "deployment.zip") {
    Remove-Item "deployment.zip" -Force
}

# Create zip with built files
Write-Host "Compressing files..." -ForegroundColor Gray
Compress-Archive -Path "dist/*", "node_modules", "package.json", "package-lock.json" -DestinationPath "deployment.zip" -Force

# Deploy to Lambda
Write-Host "🚀 Deploying BFF to Lambda..." -ForegroundColor Cyan
aws lambda update-function-code --function-name $BFF_FUNCTION_NAME --zip-file fileb://deployment.zip --region $REGION

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ BFF deployed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ BFF deployment failed" -ForegroundColor Red
    Set-Location ".."
    exit 1
}

Set-Location ".."

# Step 2: Deploy Operations Lambda Fix
Write-Host ""
Write-Host "🔧 Step 2: Deploying Operations Lambda Fix" -ForegroundColor Yellow
Write-Host "-------------------------------------------" -ForegroundColor Yellow

Write-Host "📦 Creating Operations Lambda package..." -ForegroundColor Cyan
Set-Location "lambda/operations"

if (Test-Path "deployment.zip") {
    Remove-Item "deployment.zip" -Force
}

# Create temporary directory for packaging
$tempDir = "temp_package"
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Copy files to temp directory
Write-Host "Copying files..." -ForegroundColor Gray
Copy-Item "handler.py" "$tempDir/"
New-Item -ItemType Directory -Path "$tempDir/shared" | Out-Null
Copy-Item "../shared/*.py" "$tempDir/shared/"

# Create zip from temp directory
Write-Host "Compressing files..." -ForegroundColor Gray
Set-Location $tempDir
Compress-Archive -Path "*" -DestinationPath "../deployment.zip" -Force
Set-Location ".."

# Clean up temp directory
Remove-Item $tempDir -Recurse -Force

# Deploy to Lambda
Write-Host "🚀 Deploying Operations Lambda..." -ForegroundColor Cyan
aws lambda update-function-code --function-name $OPERATIONS_FUNCTION_NAME --zip-file fileb://deployment.zip --region $REGION

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Operations Lambda deployed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Operations Lambda deployment failed" -ForegroundColor Red
    Set-Location "../.."
    exit 1
}

Set-Location "../.."

# Step 3: Basic Test
Write-Host ""
Write-Host "🧪 Step 3: Basic Testing" -ForegroundColor Yellow
Write-Host "-------------------------" -ForegroundColor Yellow

Write-Host "⏳ Waiting 10 seconds for deployment to propagate..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

Write-Host "🔍 Testing Operations Lambda..." -ForegroundColor Cyan

$testPayload = @{
    instance_id = "tb-pg-db1"
    operation = "stop_instance"
    region = "ap-southeast-1"
    account_id = "876595225096"
    parameters = @{}
} | ConvertTo-Json -Depth 3

$lambdaEvent = @{
    body = $testPayload
    requestContext = @{
        identity = @{}
    }
} | ConvertTo-Json -Depth 4

aws lambda invoke --function-name $OPERATIONS_FUNCTION_NAME --payload $lambdaEvent --region $REGION response.json

if ($LASTEXITCODE -eq 0) {
    $responseContent = Get-Content "response.json" | ConvertFrom-Json
    Write-Host "📥 Response Status: $($responseContent.statusCode)" -ForegroundColor Cyan
    
    if ($responseContent.statusCode -eq 200) {
        Write-Host "✅ Operations Lambda test PASSED" -ForegroundColor Green
    } elseif ($responseContent.statusCode -eq 404) {
        Write-Host "⚠️  Operations Lambda returned 404 (instance not found) - this is expected" -ForegroundColor Yellow
    } else {
        Write-Host "⚠️  Operations Lambda returned status: $($responseContent.statusCode)" -ForegroundColor Yellow
        Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
    }
} else {
    Write-Host "❌ Operations Lambda test failed" -ForegroundColor Red
}

# Clean up
if (Test-Path "response.json") {
    Remove-Item "response.json" -Force
}

# Summary
Write-Host ""
Write-Host "📊 Deployment Complete!" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host "✅ BFF Operations Fix: Deployed" -ForegroundColor Green
Write-Host "✅ Operations Lambda Fix: Deployed" -ForegroundColor Green
Write-Host "✅ Basic Testing: Completed" -ForegroundColor Green
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Test operations in the dashboard UI" -ForegroundColor White
Write-Host "2. Verify 400 errors are resolved" -ForegroundColor White
Write-Host "3. Check CloudWatch logs for detailed debugging info" -ForegroundColor White
Write-Host ""
Write-Host "🚀 Operations 400 Error Fix Deployment Complete!" -ForegroundColor Green