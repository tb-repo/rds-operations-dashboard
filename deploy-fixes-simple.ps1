#!/usr/bin/env pwsh
# Simple deployment script for critical fixes

Write-Host "=== DEPLOYING CRITICAL FIXES ===" -ForegroundColor Green

$region = "ap-southeast-1"
$accountId = "876595225096"

# Step 1: Configure multi-account discovery
Write-Host "Configuring multi-account discovery..." -NoNewline
try {
    aws lambda update-function-configuration --function-name rds-discovery --environment "Variables={TARGET_ACCOUNTS='[\"876595225096\"]',TARGET_REGIONS='[\"ap-southeast-1\"]',EXTERNAL_ID='rds-dashboard-unique-id-12345',CROSS_ACCOUNT_ROLE_NAME='RDSDashboardCrossAccountRole',INVENTORY_TABLE='rds-inventory-prod',AUDIT_LOG_TABLE='audit-log-prod'}" --region $region 2>&1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL]" -ForegroundColor Red
}

# Step 2: Enable production operations
Write-Host "Enabling production operations..." -NoNewline
try {
    aws lambda update-function-configuration --function-name rds-dashboard-bff --environment "Variables={COGNITO_USER_POOL_ID='ap-southeast-1_4tyxh4qJe',COGNITO_REGION='ap-southeast-1',INTERNAL_API_URL='https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com',ENABLE_PRODUCTION_OPERATIONS='true'}" --region $region 2>&1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAIL]" -ForegroundColor Red
}

# Step 3: Trigger discovery
Write-Host "Triggering discovery..." -NoNewline
Start-Sleep -Seconds 10
try {
    aws lambda invoke --function-name rds-discovery --payload '{}' response.json --region $region 2>&1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    if (Test-Path "response.json") { Remove-Item "response.json" -Force }
} catch {
    Write-Host " [FAIL]" -ForegroundColor Red
}

Write-Host ""
Write-Host "Fixes deployed! Clear browser cache and test." -ForegroundColor Green