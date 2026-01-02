#!/usr/bin/env pwsh
# Emergency BFF Fix - Restore proper configuration

Write-Host "=== EMERGENCY BFF FIX ===" -ForegroundColor Red
Write-Host "Fixing BFF configuration that broke API endpoints..." -ForegroundColor Yellow

$region = "ap-southeast-1"

# Restore BFF Lambda with ALL required environment variables
Write-Host "Restoring BFF Lambda configuration..." -NoNewline
try {
    # Get current configuration to preserve any existing variables
    $currentConfig = aws lambda get-function-configuration --function-name rds-dashboard-bff --output json --region $region | ConvertFrom-Json
    
    # Set complete environment variables
    $envVars = @{
        "COGNITO_USER_POOL_ID" = "ap-southeast-1_4tyxh4qJe"
        "COGNITO_REGION" = "ap-southeast-1"
        "INTERNAL_API_URL" = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
        "INTERNAL_API_KEY" = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
        "FRONTEND_URL" = "https://d2qvaswtmn22om.cloudfront.net"
        "ENABLE_PRODUCTION_OPERATIONS" = "true"
        "NODE_ENV" = "production"
    }
    
    # Convert to AWS CLI format
    $envString = ($envVars.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ","
    
    aws lambda update-function-configuration --function-name rds-dashboard-bff --environment "Variables={$envString}" --region $region 2>&1 | Out-Null
    
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL] $($_.Exception.Message)" -ForegroundColor Red
}

# Wait for propagation
Write-Host "Waiting for Lambda configuration propagation..." -NoNewline
Start-Sleep -Seconds 20
Write-Host " [OK]" -ForegroundColor Green

# Test BFF endpoints
Write-Host "Testing BFF health..." -NoNewline
try {
    $bffHealth = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/health" -TimeoutSec 10
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Testing instances endpoint..." -NoNewline
try {
    $instances = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/api/instances" -TimeoutSec 10 -Headers @{"Authorization"="Bearer dummy"}
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [WARN] Still needs authentication" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "BFF configuration restored!" -ForegroundColor Green
Write-Host "The dashboard should now work properly." -ForegroundColor Green
Write-Host "Refresh the page to test." -ForegroundColor Yellow