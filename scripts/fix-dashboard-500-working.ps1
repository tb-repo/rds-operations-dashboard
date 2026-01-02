# Working Dashboard 500 Error Fix
# Corrected script to fix the error statistics endpoint

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
    
    # Create properly formatted JSON for AWS CLI
    $envVarsJson = @"
{
    "BACKEND_API_URL": "$WORKING_BACKEND",
    "API_KEY": "$API_KEY",
    "CORS_ORIGIN": "$CLOUDFRONT_URL",
    "NODE_ENV": "production",
    "LOG_LEVEL": "info"
}
"@
    
    # Write to temp file to avoid command line parsing issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    $envVarsJson | Out-File -FilePath $tempFile -Encoding UTF8
    
    $updateResult = aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "file://$tempFile" --region $REGION
    
    # Clean up temp file
    Remove-Item $tempFile -Force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Environment variables updated" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Could not update environment variables" -ForegroundColor Red
        Write-Host "Trying alternative method..." -ForegroundColor Yellow
        
        # Alternative method using individual environment variable updates
        aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment Variables="{BACKEND_API_URL=$WORKING_BACKEND,API_KEY=$API_KEY,CORS_ORIGIN=$CLOUDFRONT_URL,NODE_ENV=production,LOG_LEVEL=info}" --region $REGION
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Alternative method worked" -ForegroundColor Green
        } else {
            Write-Host "FAILED: Both methods failed" -ForegroundColor Red
        }
    }
    
    Write-Host "Waiting 15 seconds for configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
} catch {
    Write-Host "ERROR: Exception during environment update: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 3: Testing BFF endpoints..." -ForegroundColor Green

Write-Host "Testing Health Check..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Health Check working" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Health Check failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Testing Error Statistics..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: Error Statistics working" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor White
    $errorStatsWorking = $true
} catch {
    Write-Host "FAILED: Error Statistics failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $errorStatsWorking = $false
}

Write-Host ""
Write-Host "Step 4: Testing CloudFront API routing..." -ForegroundColor Green
try {
    # Test the actual API endpoint through CloudFront
    $cloudfrontApiTest = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 20
    Write-Host "SUCCESS: CloudFront API routing working!" -ForegroundColor Green
    Write-Host "Response: $($cloudfrontApiTest | ConvertTo-Json -Compress)" -ForegroundColor White
    $cloudfrontWorking = $true
} catch {
    Write-Host "FAILED: CloudFront API routing failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $cloudfrontWorking = $false
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
if ($errorStatsWorking -and $cloudfrontWorking) {
    Write-Host "SUCCESS: Dashboard should now be working!" -ForegroundColor Green
    Write-Host "Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "VERIFICATION STEPS:" -ForegroundColor Yellow
    Write-Host "1. Open browser to: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
    Write-Host "2. Check that error monitoring section loads without 500 errors" -ForegroundColor White
    Write-Host "3. Verify error statistics display properly" -ForegroundColor White
} elseif ($errorStatsWorking -and -not $cloudfrontWorking) {
    Write-Host "PARTIAL SUCCESS: BFF working but CloudFront routing issue" -ForegroundColor Yellow
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Check CloudFront distribution configuration" -ForegroundColor White
    Write-Host "2. Verify API Gateway integration with CloudFront" -ForegroundColor White
    Write-Host "3. Test direct BFF URL: $BFF_API_URL/api/errors/statistics" -ForegroundColor White
} else {
    Write-Host "FAILED: Issues remain with BFF authentication" -ForegroundColor Red
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Check Lambda logs: /aws/lambda/$BFF_FUNCTION_NAME" -ForegroundColor White
    Write-Host "2. Verify API key configuration in backend" -ForegroundColor White
    Write-Host "3. Check BFF code for authentication middleware issues" -ForegroundColor White
    Write-Host "4. Consider redeploying BFF with updated code" -ForegroundColor White
}

Write-Host ""
Write-Host "=== FIX COMPLETE ===" -ForegroundColor Cyan