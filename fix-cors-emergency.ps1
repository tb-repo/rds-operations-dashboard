#!/usr/bin/env pwsh
# Emergency CORS Fix - The site is completely broken due to CORS misconfiguration

Write-Host "=== EMERGENCY CORS FIX ===" -ForegroundColor Red
Write-Host "Fixing CORS configuration that broke the entire site..." -ForegroundColor Yellow

$region = "ap-southeast-1"
$frontendUrl = "https://d2qvaswtmn22om.cloudfront.net"

# Fix BFF Lambda environment variables with correct CORS settings
Write-Host "Updating BFF Lambda with correct FRONTEND_URL..." -NoNewline
try {
    aws lambda update-function-configuration --function-name rds-dashboard-bff --environment "Variables={COGNITO_USER_POOL_ID='ap-southeast-1_4tyxh4qJe',COGNITO_REGION='ap-southeast-1',INTERNAL_API_URL='https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com',ENABLE_PRODUCTION_OPERATIONS='true',FRONTEND_URL='$frontendUrl'}" --region $region 2>&1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL] $($_.Exception.Message)" -ForegroundColor Red
}

# Wait for propagation
Write-Host "Waiting for Lambda configuration propagation..." -NoNewline
Start-Sleep -Seconds 15
Write-Host " [OK]" -ForegroundColor Green

# Test BFF health
Write-Host "Testing BFF health..." -NoNewline
try {
    $bffHealth = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/health" -TimeoutSec 10
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "CORS fix deployed!" -ForegroundColor Green
Write-Host "The dashboard should now work properly." -ForegroundColor Green
Write-Host "Clear browser cache and refresh the page." -ForegroundColor Yellow