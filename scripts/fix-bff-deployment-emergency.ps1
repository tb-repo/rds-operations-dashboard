#!/usr/bin/env pwsh

<#
.SYNOPSIS
Emergency BFF Deployment Fix

.DESCRIPTION
The BFF Lambda is failing with "Cannot find module 'express'" error.
This script will properly rebuild and redeploy the BFF with all dependencies.
#>

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Emergency BFF Deployment Fix ===" -ForegroundColor Cyan
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Step 1: Navigate to BFF directory and check current state
Write-Host "`n--- Step 1: Checking BFF Directory ---" -ForegroundColor Yellow

if (-not (Test-Path "bff")) {
    Write-Error "BFF directory not found!"
    exit 1
}

Set-Location "bff"

# Check if package.json exists
if (-not (Test-Path "package.json")) {
    Write-Error "package.json not found in BFF directory!"
    exit 1
}

Write-Success "BFF directory found"

# Step 2: Clean and reinstall dependencies
Write-Host "`n--- Step 2: Installing Dependencies ---" -ForegroundColor Yellow

# Remove existing node_modules and package-lock.json
if (Test-Path "node_modules") {
    Write-Info "Removing existing node_modules..."
    Remove-Item -Recurse -Force "node_modules" -ErrorAction SilentlyContinue
}

if (Test-Path "package-lock.json") {
    Write-Info "Removing existing package-lock.json..."
    Remove-Item -Force "package-lock.json" -ErrorAction SilentlyContinue
}

# Install dependencies
Write-Info "Installing fresh dependencies..."
npm install

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install dependencies"
    exit 1
}

Write-Success "Dependencies installed successfully"

# Step 3: Build TypeScript
Write-Host "`n--- Step 3: Building TypeScript ---" -ForegroundColor Yellow

Write-Info "Building TypeScript..."
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build TypeScript"
    exit 1
}

Write-Success "TypeScript built successfully"

# Step 4: Create deployment package
Write-Host "`n--- Step 4: Creating Deployment Package ---" -ForegroundColor Yellow

# Create deployment directory
$deployDir = "deploy"
if (Test-Path $deployDir) {
    Remove-Item -Recurse -Force $deployDir
}
New-Item -ItemType Directory -Path $deployDir | Out-Null

# Copy built files
Write-Info "Copying built files..."
Copy-Item -Path "dist/*" -Destination $deployDir -Recurse -Force

# Copy package.json and install production dependencies
Write-Info "Copying package.json..."
Copy-Item -Path "package.json" -Destination $deployDir -Force

# Install production dependencies in deploy directory
Write-Info "Installing production dependencies..."
Set-Location $deployDir
npm install --production --no-optional

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install production dependencies"
    Set-Location ..
    exit 1
}

Set-Location ..

# Step 5: Create ZIP package
Write-Host "`n--- Step 5: Creating ZIP Package ---" -ForegroundColor Yellow

$zipFile = "bff-deployment.zip"
if (Test-Path $zipFile) {
    Remove-Item -Force $zipFile
}

Write-Info "Creating ZIP package..."
Compress-Archive -Path "$deployDir/*" -DestinationPath $zipFile -Force

if (-not (Test-Path $zipFile)) {
    Write-Error "Failed to create ZIP package"
    exit 1
}

$zipSize = (Get-Item $zipFile).Length / 1MB
Write-Success "ZIP package created: $zipFile ($($zipSize.ToString('F2')) MB)"

# Step 6: Deploy to Lambda
Write-Host "`n--- Step 6: Deploying to Lambda ---" -ForegroundColor Yellow

Write-Info "Updating Lambda function code..."
$updateResult = aws lambda update-function-code `
    --function-name "rds-dashboard-bff-prod" `
    --zip-file "fileb://$zipFile" `
    --region ap-southeast-1 `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update Lambda function"
    Write-Error $updateResult
    exit 1
}

Write-Success "Lambda function updated successfully"

# Step 7: Wait for deployment to complete
Write-Host "`n--- Step 7: Waiting for Deployment ---" -ForegroundColor Yellow

Write-Info "Waiting for deployment to complete..."
Start-Sleep -Seconds 10

# Check function status
$functionInfo = aws lambda get-function --function-name "rds-dashboard-bff-prod" --region ap-southeast-1 --output json | ConvertFrom-Json

if ($functionInfo) {
    Write-Success "Function Status: $($functionInfo.Configuration.State)"
    Write-Info "Last Modified: $($functionInfo.Configuration.LastModified)"
    Write-Info "Code Size: $($functionInfo.Configuration.CodeSize) bytes"
} else {
    Write-Warning "Could not retrieve function status"
}

# Step 8: Test the deployment
Write-Host "`n--- Step 8: Testing Deployment ---" -ForegroundColor Yellow

Write-Info "Testing error dashboard endpoint..."
$testPayload = @{
    httpMethod = "GET"
    path = "/api/errors/dashboard"
    headers = @{
        "Content-Type" = "application/json"
    }
    queryStringParameters = $null
} | ConvertTo-Json -Compress

$testResult = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload --region ap-southeast-1 test_response.json 2>&1

if (Test-Path "test_response.json") {
    $response = Get-Content "test_response.json" | ConvertFrom-Json
    Write-Info "Test Response Status: $($response.statusCode)"
    
    if ($response.statusCode -eq 200) {
        Write-Success "BFF is responding correctly!"
    } else {
        Write-Warning "BFF returned status: $($response.statusCode)"
        if ($response.body) {
            Write-Info "Response body: $($response.body)"
        }
    }
    
    Remove-Item "test_response.json" -Force
} else {
    Write-Warning "No test response received"
}

# Step 9: Test error statistics endpoint
Write-Info "Testing error statistics endpoint..."
$testPayload2 = @{
    httpMethod = "GET"
    path = "/api/errors/statistics"
    headers = @{
        "Content-Type" = "application/json"
    }
    queryStringParameters = $null
} | ConvertTo-Json -Compress

$testResult2 = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload2 --region ap-southeast-1 test_response2.json 2>&1

if (Test-Path "test_response2.json") {
    $response2 = Get-Content "test_response2.json" | ConvertFrom-Json
    Write-Info "Statistics Response Status: $($response2.statusCode)"
    
    if ($response2.statusCode -eq 200) {
        Write-Success "Statistics endpoint is working!"
    } else {
        Write-Warning "Statistics endpoint returned status: $($response2.statusCode)"
    }
    
    Remove-Item "test_response2.json" -Force
}

# Cleanup
Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow
if (Test-Path $deployDir) {
    Remove-Item -Recurse -Force $deployDir
}
if (Test-Path $zipFile) {
    Remove-Item -Force $zipFile
}

Write-Host "`n=== Emergency BFF Fix Complete ===" -ForegroundColor Cyan
Write-Success "The BFF has been redeployed with proper dependencies"
Write-Info "You can now test the dashboard at: https://d2qvaswtmn22om.cloudfront.net/dashboard"
Write-Info "The error statistics section should now work properly"