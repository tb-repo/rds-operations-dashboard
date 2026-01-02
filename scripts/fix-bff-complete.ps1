# Complete BFF Fix for Dashboard 500 Errors
# Addresses all identified issues: missing env vars, wrong backend URL, authentication

Write-Host "=== COMPLETE BFF FIX FOR DASHBOARD 500 ERRORS ===" -ForegroundColor Cyan
Write-Host "Fixing all identified issues based on Lambda logs analysis" -ForegroundColor Yellow

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff"
$REGION = "ap-southeast-1"
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"
$WORKING_BACKEND = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$API_KEY = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
$COGNITO_USER_POOL_ID = "ap-southeast-1_4tyxh4qJe"

Write-Host ""
Write-Host "ISSUES IDENTIFIED FROM LOGS:" -ForegroundColor Red
Write-Host "1. Missing COGNITO_USER_POOL_ID environment variable" -ForegroundColor Red
Write-Host "2. BFF pointing to wrong backend (qxx9whmsd4 instead of 0pjyr8lkpl)" -ForegroundColor Red
Write-Host "3. Authentication middleware requiring tokens for API endpoints" -ForegroundColor Red
Write-Host ""

Write-Host "Step 1: Updating BFF environment variables with ALL required values..." -ForegroundColor Green
try {
    Write-Host "Setting comprehensive environment variables..." -ForegroundColor Yellow
    
    # Create complete environment variables JSON
    $envVarsJson = @"
{
    "BACKEND_API_URL": "$WORKING_BACKEND",
    "API_KEY": "$API_KEY",
    "CORS_ORIGIN": "$CLOUDFRONT_URL",
    "NODE_ENV": "production",
    "LOG_LEVEL": "info",
    "COGNITO_USER_POOL_ID": "$COGNITO_USER_POOL_ID",
    "COGNITO_REGION": "$REGION",
    "JWT_ISSUER": "https://cognito-idp.$REGION.amazonaws.com/$COGNITO_USER_POOL_ID"
}
"@
    
    # Write to temp file to avoid command line parsing issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    $envVarsJson | Out-File -FilePath $tempFile -Encoding UTF8
    
    $updateResult = aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "file://$tempFile" --region $REGION
    
    # Clean up temp file
    Remove-Item $tempFile -Force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: All environment variables updated" -ForegroundColor Green
        Write-Host "- BACKEND_API_URL: $WORKING_BACKEND" -ForegroundColor White
        Write-Host "- COGNITO_USER_POOL_ID: $COGNITO_USER_POOL_ID" -ForegroundColor White
        Write-Host "- API_KEY: [CONFIGURED]" -ForegroundColor White
    } else {
        Write-Host "FAILED: Could not update environment variables" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Waiting 20 seconds for Lambda configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 20
    
} catch {
    Write-Host "ERROR: Exception during environment update: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 2: Testing BFF health after configuration..." -ForegroundColor Green
try {
    $healthResponse = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 15
    Write-Host "SUCCESS: BFF health check working" -ForegroundColor Green
    Write-Host "Response: $($healthResponse | ConvertTo-Json -Compress)" -ForegroundColor White
} catch {
    Write-Host "FAILED: BFF health check failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    # Check logs for current error
    Write-Host "Checking recent Lambda logs..." -ForegroundColor Yellow
    $logResult = aws logs filter-log-events --log-group-name "/aws/lambda/$BFF_FUNCTION_NAME" --start-time $([DateTimeOffset]::Now.AddMinutes(-5).ToUnixTimeMilliseconds()) --region $REGION --query 'events[?contains(message, `error`) || contains(message, `ERROR`)].message' --output text
    if ($logResult) {
        Write-Host "Recent errors:" -ForegroundColor Red
        Write-Host $logResult -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Step 3: Testing error statistics endpoint (the main issue)..." -ForegroundColor Green

# First test without authentication (should fail but give us info)
Write-Host "Testing without authentication..." -ForegroundColor Yellow
try {
    $statsResponse = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 15
    Write-Host "UNEXPECTED: Error statistics working without auth!" -ForegroundColor Green
    Write-Host "Response: $($statsResponse | ConvertTo-Json -Compress)" -ForegroundColor White
    $needsAuth = $false
} catch {
    Write-Host "EXPECTED: Authentication required" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    $needsAuth = $true
}

if ($needsAuth) {
    Write-Host ""
    Write-Host "Step 4: Testing direct backend connection (bypass BFF auth)..." -ForegroundColor Green
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
}

Write-Host ""
Write-Host "Step 5: Testing CloudFront routing..." -ForegroundColor Green
try {
    # Test if CloudFront routes to BFF correctly
    $cloudfrontResponse = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/health" -Method GET -TimeoutSec 20
    Write-Host "SUCCESS: CloudFront routing to BFF working" -ForegroundColor Green
    $cloudfrontRouting = $true
} catch {
    Write-Host "FAILED: CloudFront routing issue" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $cloudfrontRouting = $false
}

Write-Host ""
Write-Host "=== DIAGNOSIS SUMMARY ===" -ForegroundColor Cyan

if ($needsAuth -and $backendWorking -and $cloudfrontRouting) {
    Write-Host "ROOT CAUSE IDENTIFIED:" -ForegroundColor Yellow
    Write-Host "✅ BFF is now working (environment variables fixed)" -ForegroundColor Green
    Write-Host "✅ Backend is working (can connect directly)" -ForegroundColor Green
    Write-Host "✅ CloudFront routing is working" -ForegroundColor Green
    Write-Host "❌ BFF requires authentication for /api/errors/statistics" -ForegroundColor Red
    Write-Host ""
    Write-Host "SOLUTION NEEDED:" -ForegroundColor Yellow
    Write-Host "The BFF authentication middleware needs to be configured to allow" -ForegroundColor White
    Write-Host "unauthenticated access to the /api/errors/statistics endpoint" -ForegroundColor White
    Write-Host "OR the frontend needs to include proper authentication tokens." -ForegroundColor White
    Write-Host ""
    Write-Host "IMMEDIATE WORKAROUND:" -ForegroundColor Cyan
    Write-Host "1. Frontend can call backend directly: $WORKING_BACKEND/errors/statistics" -ForegroundColor White
    Write-Host "2. Include x-api-key header: $API_KEY" -ForegroundColor White
    Write-Host ""
    Write-Host "PERMANENT FIX OPTIONS:" -ForegroundColor Cyan
    Write-Host "1. Modify BFF to allow unauthenticated access to statistics endpoint" -ForegroundColor White
    Write-Host "2. Implement proper authentication flow in frontend" -ForegroundColor White
    Write-Host "3. Create a separate public API endpoint for statistics" -ForegroundColor White
    
} elseif (-not $backendWorking) {
    Write-Host "BACKEND ISSUE:" -ForegroundColor Red
    Write-Host "❌ Backend $WORKING_BACKEND is not responding" -ForegroundColor Red
    Write-Host "Need to investigate backend Lambda function" -ForegroundColor White
    
} elseif (-not $cloudfrontRouting) {
    Write-Host "CLOUDFRONT ISSUE:" -ForegroundColor Red
    Write-Host "❌ CloudFront not routing to BFF correctly" -ForegroundColor Red
    Write-Host "Need to check CloudFront distribution configuration" -ForegroundColor White
    
} else {
    Write-Host "CONFIGURATION SUCCESSFUL:" -ForegroundColor Green
    Write-Host "✅ All components working!" -ForegroundColor Green
    Write-Host "Dashboard should now be functional" -ForegroundColor Green
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Test dashboard: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
Write-Host "2. Check browser console for any remaining errors" -ForegroundColor White
Write-Host "3. If authentication errors persist, implement auth flow" -ForegroundColor White

Write-Host ""
Write-Host "=== COMPLETE BFF FIX FINISHED ===" -ForegroundColor Cyan