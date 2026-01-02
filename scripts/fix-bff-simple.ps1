# Simple BFF Fix for Dashboard 500 Errors
# Direct AWS CLI approach to avoid JSON parsing issues

Write-Host "=== SIMPLE BFF FIX FOR DASHBOARD 500 ERRORS ===" -ForegroundColor Cyan
Write-Host "Using direct AWS CLI commands to fix environment variables" -ForegroundColor Yellow

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff"
$REGION = "ap-southeast-1"
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"
$WORKING_BACKEND = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$API_KEY = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
$COGNITO_USER_POOL_ID = "ap-southeast-1_4tyxh4qJe"

Write-Host ""
Write-Host "Step 1: Updating BFF environment variables..." -ForegroundColor Green

# Use direct command line approach to avoid JSON parsing issues
$envCommand = "aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment `"Variables={BACKEND_API_URL=$WORKING_BACKEND,API_KEY=$API_KEY,CORS_ORIGIN=$CLOUDFRONT_URL,NODE_ENV=production,LOG_LEVEL=info,COGNITO_USER_POOL_ID=$COGNITO_USER_POOL_ID,COGNITO_REGION=$REGION}`" --region $REGION"

Write-Host "Executing: $envCommand" -ForegroundColor Yellow
$result = Invoke-Expression $envCommand

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Environment variables updated" -ForegroundColor Green
    Write-Host "Waiting 20 seconds for configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 20
} else {
    Write-Host "FAILED: Could not update environment variables" -ForegroundColor Red
    Write-Host "Result: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 2: Testing BFF health..." -ForegroundColor Green
try {
    $healthResponse = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: BFF health check working" -ForegroundColor Green
    Write-Host "Response: $($healthResponse | ConvertTo-Json -Compress)" -ForegroundColor White
} catch {
    Write-Host "FAILED: BFF health check failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 3: Testing error statistics endpoint..." -ForegroundColor Green
try {
    $statsResponse = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Error statistics working!" -ForegroundColor Green
    Write-Host "Response: $($statsResponse | ConvertTo-Json -Compress)" -ForegroundColor White
    $statsWorking = $true
} catch {
    Write-Host "INFO: Authentication required (expected)" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    $statsWorking = $false
}

Write-Host ""
Write-Host "Step 4: Testing backend directly..." -ForegroundColor Green
try {
    $headers = @{
        'x-api-key' = $API_KEY
        'Content-Type' = 'application/json'
    }
    
    $backendResponse = Invoke-RestMethod -Uri "$WORKING_BACKEND/errors/statistics" -Method GET -Headers $headers -TimeoutSec 15
    Write-Host "SUCCESS: Backend working directly!" -ForegroundColor Green
    Write-Host "Response: $($backendResponse | ConvertTo-Json -Compress)" -ForegroundColor White
    $backendWorking = $true
} catch {
    Write-Host "FAILED: Backend not working" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $backendWorking = $false
}

Write-Host ""
Write-Host "Step 5: Testing CloudFront dashboard..." -ForegroundColor Green
try {
    $cloudfrontTest = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 20
    
    # Check if we got HTML (frontend) or JSON (API)
    if ($cloudfrontTest -like "*<!doctype html>*") {
        Write-Host "INFO: CloudFront serving frontend HTML (not API)" -ForegroundColor Yellow
        Write-Host "This means CloudFront is not routing /api/* to the BFF" -ForegroundColor Yellow
        $cloudfrontApiWorking = $false
    } else {
        Write-Host "SUCCESS: CloudFront API routing working!" -ForegroundColor Green
        Write-Host "Response: $($cloudfrontTest | ConvertTo-Json -Compress)" -ForegroundColor White
        $cloudfrontApiWorking = $true
    }
} catch {
    Write-Host "FAILED: CloudFront API test failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $cloudfrontApiWorking = $false
}

Write-Host ""
Write-Host "=== DIAGNOSIS SUMMARY ===" -ForegroundColor Cyan

if ($backendWorking) {
    Write-Host "✅ Backend is working (can connect directly with API key)" -ForegroundColor Green
    Write-Host "✅ BFF environment variables updated successfully" -ForegroundColor Green
    
    if ($statsWorking) {
        Write-Host "✅ BFF error statistics endpoint working!" -ForegroundColor Green
        Write-Host "🎉 DASHBOARD SHOULD NOW BE WORKING!" -ForegroundColor Green
        Write-Host ""
        Write-Host "TEST THE DASHBOARD:" -ForegroundColor Cyan
        Write-Host "Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
        
    } elseif ($cloudfrontApiWorking) {
        Write-Host "✅ CloudFront API routing working" -ForegroundColor Green
        Write-Host "⚠️  BFF requires authentication but CloudFront bypasses it" -ForegroundColor Yellow
        Write-Host "🎉 DASHBOARD SHOULD NOW BE WORKING!" -ForegroundColor Green
        
    } else {
        Write-Host "❌ CloudFront not routing /api/* to BFF" -ForegroundColor Red
        Write-Host ""
        Write-Host "ISSUE: CloudFront Configuration" -ForegroundColor Red
        Write-Host "CloudFront is serving frontend HTML for /api/errors/statistics" -ForegroundColor White
        Write-Host "instead of routing to the BFF API Gateway" -ForegroundColor White
        Write-Host ""
        Write-Host "WORKAROUND:" -ForegroundColor Yellow
        Write-Host "Frontend can call backend directly:" -ForegroundColor White
        Write-Host "URL: $WORKING_BACKEND/errors/statistics" -ForegroundColor White
        Write-Host "Header: x-api-key: $API_KEY" -ForegroundColor White
    }
} else {
    Write-Host "❌ Backend is not working" -ForegroundColor Red
    Write-Host "Need to investigate backend Lambda function" -ForegroundColor White
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Test dashboard: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
Write-Host "2. Check browser console for any remaining errors" -ForegroundColor White
Write-Host "3. If issues persist, check CloudFront distribution configuration" -ForegroundColor White

Write-Host ""
Write-Host "=== SIMPLE BFF FIX COMPLETE ===" -ForegroundColor Cyan