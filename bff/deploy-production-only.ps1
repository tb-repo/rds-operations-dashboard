#!/usr/bin/env pwsh

<#
.SYNOPSIS
Production-only BFF deployment with CORS configuration
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Production-Only BFF Deployment ===" -ForegroundColor Cyan

# Production-only CORS configuration
$ProductionOrigin = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "Deploying with production-only CORS configuration:" -ForegroundColor Yellow
Write-Host "  Origin: $ProductionOrigin" -ForegroundColor Green
Write-Host "  Environment: production" -ForegroundColor Green
Write-Host "  Security: HTTPS only, no development origins" -ForegroundColor Green

# Check if function exists, create if it doesn't
Write-Host "Checking if Lambda function exists..." -ForegroundColor Yellow
try {
    aws lambda get-function --function-name $FunctionName --region $Region | Out-Null
    Write-Host "Function exists, will update code and configuration" -ForegroundColor Green
    $FunctionExists = $true
} catch {
    Write-Host "Function does not exist, will create it" -ForegroundColor Yellow
    $FunctionExists = $false
}

# Build and package
Write-Host "Building and packaging BFF..." -ForegroundColor Yellow
./simple-deploy.ps1 -FunctionName $FunctionName -Region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to deploy BFF code"
    exit 1
}

# If function didn't exist before, it was just created, so we need to update environment variables
Write-Host "Configuring production-only environment variables..." -ForegroundColor Yellow

$envConfig = @{
    Variables = @{
        CORS_ORIGINS = $ProductionOrigin
        NODE_ENV = "production"
        COGNITO_USER_POOL_ID = "ap-southeast-1_example"
        COGNITO_REGION = "ap-southeast-1"
        INTERNAL_API_URL = "https://api.example.com"
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

# Verify configuration
Write-Host "Verifying production-only configuration..." -ForegroundColor Yellow
try {
    $config = aws lambda get-function-configuration --function-name $FunctionName --region $Region | ConvertFrom-Json
    
    Write-Host "Function Configuration:" -ForegroundColor Green
    Write-Host "  Name: $($config.FunctionName)" -ForegroundColor Cyan
    Write-Host "  Runtime: $($config.Runtime)" -ForegroundColor Cyan
    Write-Host "  Last Modified: $($config.LastModified)" -ForegroundColor Cyan
    
    if ($config.Environment.Variables.CORS_ORIGINS) {
        Write-Host "  CORS Origins: $($config.Environment.Variables.CORS_ORIGINS)" -ForegroundColor Green
    }
    
    if ($config.Environment.Variables.NODE_ENV) {
        Write-Host "  Environment: $($config.Environment.Variables.NODE_ENV)" -ForegroundColor Green
    }
    
} catch {
    Write-Warning "Could not verify configuration, but deployment likely successful"
}

# Test function
Write-Host "Testing function..." -ForegroundColor Yellow
$testPayload = @{
    httpMethod = "GET"
    path = "/health"
    headers = @{ 
        Origin = $ProductionOrigin
        "Content-Type" = "application/json"
    }
} | ConvertTo-Json -Depth 3

$testPayload | Out-File "test-payload.json" -Encoding UTF8

try {
    aws lambda invoke `
        --function-name $FunctionName `
        --payload "file://test-payload.json" `
        --region $Region `
        "test-response.json"
        
    if (Test-Path "test-response.json") {
        $response = Get-Content "test-response.json" | ConvertFrom-Json
        Write-Host "Function Test:" -ForegroundColor Green
        Write-Host "  Status: $($response.statusCode)" -ForegroundColor Cyan
        
        if ($response.headers -and $response.headers.'Access-Control-Allow-Origin') {
            Write-Host "  CORS Header: $($response.headers.'Access-Control-Allow-Origin')" -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "Function test had issues, but deployment likely successful"
}

# Cleanup
Remove-Item "production-env.json" -Force -ErrorAction SilentlyContinue
Remove-Item "test-payload.json" -Force -ErrorAction SilentlyContinue
Remove-Item "test-response.json" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Production-Only BFF Deployment Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Function: $FunctionName" -ForegroundColor White
Write-Host "  CORS Origin: $ProductionOrigin (ONLY)" -ForegroundColor Green
Write-Host "  Environment: production" -ForegroundColor Green
Write-Host "  Security: Production-only (no dev/staging origins)" -ForegroundColor Green
Write-Host ""
Write-Host "Test Your Dashboard:" -ForegroundColor Cyan
Write-Host "  URL: $ProductionOrigin" -ForegroundColor White
Write-Host "  Expected: No CORS errors" -ForegroundColor Green
Write-Host "  Expected: Full dashboard functionality" -ForegroundColor Green
Write-Host ""
Write-Host "Production-only CORS deployment ready!" -ForegroundColor Green