# Simple Dashboard 500 Error Fix
# Basic script to fix the error statistics endpoint

Write-Host "=== DASHBOARD 500 ERROR FIX ===" -ForegroundColor Cyan
Write-Host "Applying fix for production dashboard errors" -ForegroundColor Yellow

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff"
$REGION = "ap-southeast-1"
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"
$WORKING_BACKEND = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$API_KEY = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"

Write-Host ""
Write-Host "Step 1: Testing current error statistics endpoint..." -ForegroundColor Green
try {
    $statsTest = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 10
    Write-Host "SUCCESS: Error statistics already working!" -ForegroundColor Green
    Write-Host "Response: $($statsTest | ConvertTo-Json -Compress)" -ForegroundColor White
    Write-Host "No fix needed - dashboard should be working" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "FAILED: Error statistics failing - proceeding with fix" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 2: Updating BFF environment variables..." -ForegroundColor Green
try {
    Write-Host "Updating Lambda environment variables..." -ForegroundColor Yellow
    
    $envVarsJson = '{"BACKEND_API_URL":"' + $WORKING_BACKEND + '","API_KEY":"' + $API_KEY + '","CORS_ORIGIN":"' + $CLOUDFRONT_URL + '","NODE_ENV":"production","LOG_LEVEL":"info"}'
    
    $updateResult = aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "Variables=$envVarsJson" --region $REGION
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Environment variables updated" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Could not update environment variables" -ForegroundColor Red
    }
    
    Write-Host "Waiting 15 seconds for configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
} catch {
    Write-Host "ERROR: Exception during environment update: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 3: Testing BFF after configuration update..." -ForegroundColor Green

Write-Host "Testing Health Check..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Health Check working" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Health Check failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Testing Instances..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_API_URL/api/instances" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Instances working" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Instances failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Testing Error Statistics..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Error Statistics working" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor White
} catch {
    Write-Host "FAILED: Error Statistics failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 4: Testing CloudFront dashboard..." -ForegroundColor Green
try {
    $cloudfrontTest = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 20
    Write-Host "SUCCESS: CloudFront dashboard working!" -ForegroundColor Green
    Write-Host "Response: $($cloudfrontTest | ConvertTo-Json -Compress)" -ForegroundColor White
    Write-Host ""
    Write-Host "DASHBOARD SHOULD NOW BE WORKING!" -ForegroundColor Green
    Write-Host "Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor Cyan
} catch {
    Write-Host "FAILED: CloudFront dashboard still failing" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Check Lambda logs: /aws/lambda/$BFF_FUNCTION_NAME" -ForegroundColor White
    Write-Host "2. Run comprehensive fix script" -ForegroundColor White
    Write-Host "3. Consider BFF code deployment" -ForegroundColor White
}

Write-Host ""
Write-Host "=== FIX COMPLETE ===" -ForegroundColor Cyan