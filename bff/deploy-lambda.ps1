#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploy BFF to Lambda with all dependencies

.DESCRIPTION
Creates a proper deployment package with node_modules and deploys to Lambda
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== BFF Lambda Deployment ===" -ForegroundColor Cyan

# Clean and prepare
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
if (Test-Path "dist.zip") { Remove-Item "dist.zip" -Force }
if (Test-Path "lambda-package") { Remove-Item "lambda-package" -Recurse -Force }

# Create deployment package directory
Write-Host "Creating deployment package..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "lambda-package" -Force | Out-Null

# Copy built files
Write-Host "Copying built files..." -ForegroundColor Yellow
Copy-Item "dist/*" "lambda-package/" -Recurse -Force

# Copy package.json and install production dependencies
Write-Host "Installing production dependencies..." -ForegroundColor Yellow
Copy-Item "package.json" "lambda-package/" -Force
Copy-Item "package-lock.json" "lambda-package/" -Force -ErrorAction SilentlyContinue

# Install production dependencies in the package directory
Push-Location "lambda-package"
try {
    npm install --production --no-audit --no-fund
    Write-Host "Dependencies installed successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to install dependencies: $($_.Exception.Message)"
    Pop-Location
    exit 1
}
Pop-Location

# Create zip file
Write-Host "Creating deployment zip..." -ForegroundColor Yellow
Compress-Archive -Path "lambda-package/*" -DestinationPath "dist.zip" -Force

# Get zip file size
$zipSize = (Get-Item "dist.zip").Length / 1MB
Write-Host "Deployment package size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan

# Deploy to Lambda
Write-Host "Deploying to Lambda function: $FunctionName..." -ForegroundColor Yellow
try {
    $result = aws lambda update-function-code --function-name $FunctionName --zip-file fileb://dist.zip --region $Region --output json | ConvertFrom-Json
    
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host "Function: $($result.FunctionName)" -ForegroundColor Cyan
    Write-Host "Runtime: $($result.Runtime)" -ForegroundColor Cyan
    Write-Host "Last Modified: $($result.LastModified)" -ForegroundColor Cyan
    Write-Host "Code Size: $([math]::Round($result.CodeSize / 1MB, 2)) MB" -ForegroundColor Cyan
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}

# Wait for function to be ready
Write-Host "Waiting for function to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Test the function
Write-Host "Testing function..." -ForegroundColor Yellow
try {
    $testResult = aws lambda invoke --function-name $FunctionName --payload '{"httpMethod":"GET","path":"/health","headers":{}}' --region $Region response.json
    
    if (Test-Path "response.json") {
        $response = Get-Content "response.json" | ConvertFrom-Json
        Write-Host "Test response: $($response.statusCode)" -ForegroundColor Cyan
        Remove-Item "response.json" -Force
    }
} catch {
    Write-Warning "Test invocation failed, but deployment may still be successful"
}

# Cleanup
Write-Host "Cleaning up..." -ForegroundColor Yellow
Remove-Item "lambda-package" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Test the API Gateway endpoints" -ForegroundColor White
Write-Host "2. Check CloudWatch logs for any errors" -ForegroundColor White
Write-Host "3. Run validation script" -ForegroundColor White