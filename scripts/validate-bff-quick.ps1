#!/usr/bin/env pwsh
# Quick BFF validation script

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Quick BFF Validation ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check function exists
Write-Host "Checking Lambda function..." -ForegroundColor Yellow
$function = aws lambda get-function --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json

if ($function.Configuration) {
    Write-Host "✓ Function exists: $($function.Configuration.FunctionName)" -ForegroundColor Green
    Write-Host "  Runtime: $($function.Configuration.Runtime)" -ForegroundColor Cyan
    Write-Host "  Memory: $($function.Configuration.MemorySize) MB" -ForegroundColor Cyan
    Write-Host "  Timeout: $($function.Configuration.Timeout) seconds" -ForegroundColor Cyan
    Write-Host "  Last Modified: $($function.Configuration.LastModified)" -ForegroundColor Cyan
} else {
    Write-Host "✗ Function not found!" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 2: Check environment variables
Write-Host "Checking environment variables..." -ForegroundColor Yellow
$config = aws lambda get-function-configuration --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json

$requiredVars = @("COGNITO_USER_POOL_ID", "COGNITO_CLIENT_ID", "COGNITO_REGION", "INTERNAL_API_URL")
$allPresent = $true

foreach ($var in $requiredVars) {
    if ($config.Environment.Variables.$var) {
        Write-Host "  ✓ $var" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $var is missing" -ForegroundColor Red
        $allPresent = $false
    }
}

if (-not $allPresent) {
    Write-Host ""
    Write-Host "✗ Some environment variables are missing" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✓ BFF deployment looks good!" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Test via API Gateway and frontend" -ForegroundColor Cyan
