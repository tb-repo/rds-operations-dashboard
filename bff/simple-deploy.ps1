#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple BFF deployment using 7zip or alternative method
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Simple BFF Deployment ===" -ForegroundColor Cyan

# Clean up
if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" -Force }

# Create a simple package with just the essential files
Write-Host "Creating minimal deployment package..." -ForegroundColor Yellow

# Create a temporary directory structure
$tempDir = "temp-deploy"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy essential files
Copy-Item "dist/index.js" "$tempDir/" -Force
Copy-Item "dist/lambda.js" "$tempDir/" -Force
Copy-Item "package.json" "$tempDir/" -Force

# Copy all dist subdirectories (config, middleware, routes, etc.)
$distDirs = @("config", "middleware", "routes", "security", "services", "utils")
foreach ($dir in $distDirs) {
    if (Test-Path "dist/$dir") {
        Copy-Item "dist/$dir" "$tempDir/" -Recurse -Force
    }
}

# Create a minimal package.json for Lambda
$minimalPackage = @{
    name = "rds-dashboard-bff"
    version = "1.0.0"
    main = "lambda.js"
    dependencies = @{
        "@aws-sdk/client-cognito-identity-provider" = "^3.490.0"
        "@aws-sdk/client-secrets-manager" = "^3.490.0"
        "@vendia/serverless-express" = "^4.12.6"
        axios = "^1.6.2"
        cors = "^2.8.5"
        dotenv = "^16.3.1"
        express = "^4.18.2"
        helmet = "^7.1.0"
        jsonwebtoken = "^9.0.2"
        "jwks-rsa" = "^3.1.0"
        winston = "^3.11.0"
    }
} | ConvertTo-Json -Depth 3

$minimalPackage | Out-File "$tempDir/package.json" -Encoding UTF8

# Install minimal dependencies
Write-Host "Installing minimal dependencies..." -ForegroundColor Yellow
Push-Location $tempDir
npm install --production --no-audit --no-fund --silent
Pop-Location

# Try using Python to create zip (more reliable than PowerShell)
Write-Host "Creating zip file..." -ForegroundColor Yellow
try {
    python -c "
import zipfile
import os
import shutil

def create_zip(source_dir, output_file):
    with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                file_path = os.path.join(root, file)
                arc_name = os.path.relpath(file_path, source_dir)
                zipf.write(file_path, arc_name)

create_zip('$tempDir', 'deployment.zip')
print('Zip created successfully')
"
    Write-Host "Zip created with Python" -ForegroundColor Green
} catch {
    Write-Host "Python not available, trying alternative method..." -ForegroundColor Yellow
    
    # Alternative: Use tar (available on Windows 10+)
    try {
        tar -czf deployment.zip -C $tempDir .
        Write-Host "Zip created with tar" -ForegroundColor Green
    } catch {
        Write-Error "Could not create deployment package. Please install Python or use a different method."
        exit 1
    }
}

# Check if zip was created
if (-not (Test-Path "deployment.zip")) {
    Write-Error "Failed to create deployment.zip"
    exit 1
}

$zipSize = (Get-Item "deployment.zip").Length / 1MB
Write-Host "Package size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan

# Deploy to Lambda
Write-Host "Deploying to Lambda..." -ForegroundColor Yellow
try {
    aws lambda update-function-code --function-name $FunctionName --zip-file fileb://deployment.zip --region $Region
    Write-Host "Deployment successful!" -ForegroundColor Green
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "deployment.zip" -Force -ErrorAction SilentlyContinue

Write-Host "=== Deployment Complete ===" -ForegroundColor Green