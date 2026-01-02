#!/usr/bin/env pwsh

<#
.SYNOPSIS
Create Lambda function for BFF with production-only CORS
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Creating Lambda Function for Production-Only BFF ===" -ForegroundColor Cyan

# Production-only CORS configuration
$ProductionOrigin = "https://d2qvaswtmn22om.cloudfront.net"

# First, build and package the code
Write-Host "Building BFF code..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build BFF code"
    exit 1
}

# Create deployment package
Write-Host "Creating deployment package..." -ForegroundColor Yellow

# Clean up
if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" -Force }

# Create a temporary directory structure
$tempDir = "temp-deploy"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy essential files
Copy-Item "dist/index.js" "$tempDir/" -Force
Copy-Item "package.json" "$tempDir/" -Force

# Create a minimal package.json for Lambda
$minimalPackage = @{
    name = "rds-dashboard-bff"
    version = "1.0.0"
    main = "index.js"
    dependencies = @{
        express = "^4.18.2"
        cors = "^2.8.5"
        "aws-sdk" = "^2.1490.0"
        jsonwebtoken = "^9.0.2"
        "jwks-client" = "^3.0.1"
    }
} | ConvertTo-Json -Depth 3

$minimalPackage | Out-File "$tempDir/package.json" -Encoding UTF8

# Install minimal dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
Push-Location $tempDir
npm install --production --no-audit --no-fund --silent
Pop-Location

# Create zip file
Write-Host "Creating zip file..." -ForegroundColor Yellow
try {
    python -c "
import zipfile
import os

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
    Write-Host "Deployment package created" -ForegroundColor Green
} catch {
    Write-Error "Failed to create deployment package"
    exit 1
}

# Check if zip was created
if (-not (Test-Path "deployment.zip")) {
    Write-Error "Failed to create deployment.zip"
    exit 1
}

# Create Lambda function
Write-Host "Creating Lambda function..." -ForegroundColor Yellow

try {
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime nodejs18.x `
        --role "arn:aws:iam::876595225096:role/RDSDashboardLambdaRole-prod" `
        --handler index.handler `
        --zip-file fileb://deployment.zip `
        --timeout 30 `
        --memory-size 512 `
        --region $Region `
        --description "RDS Dashboard BFF with production-only CORS"
        
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Lambda function created successfully" -ForegroundColor Green
    } else {
        throw "Failed to create Lambda function"
    }
} catch {
    Write-Error "Failed to create Lambda function: $($_.Exception.Message)"
    exit 1
}

# Configure production-only environment variables
Write-Host "Configuring production-only environment variables..." -ForegroundColor Yellow

$envConfig = @{
    Variables = @{
        CORS_ORIGINS = $ProductionOrigin
        NODE_ENV = "production"
    }
} | ConvertTo-Json -Depth 2

$envConfig | Out-File "production-env.json" -Encoding UTF8

try {
    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --environment file://production-env.json `
        --region $Region
        
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Production-only environment variables configured" -ForegroundColor Green
    } else {
        throw "Failed to update environment variables"
    }
} catch {
    Write-Error "Failed to configure environment variables: $($_.Exception.Message)"
    exit 1
}

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "deployment.zip" -Force -ErrorAction SilentlyContinue
Remove-Item "production-env.json" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Lambda Function Created Successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Function: $FunctionName" -ForegroundColor White
Write-Host "  CORS Origin: $ProductionOrigin (ONLY)" -ForegroundColor Green
Write-Host "  Environment: production" -ForegroundColor Green
Write-Host "  Security: Production-only (no dev/staging origins)" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Test your dashboard at $ProductionOrigin" -ForegroundColor Yellow