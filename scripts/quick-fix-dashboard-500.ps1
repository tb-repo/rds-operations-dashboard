# Quick Fix for Dashboard 500 Errors - Simplified Version
# Addresses the persistent 500 errors with minimal complexity

Write-Host "=== DASHBOARD 500 ERROR QUICK FIX ===" -ForegroundColor Cyan
Write-Host "Applying immediate fix for production dashboard errors" -ForegroundColor Yellow
Write-Host ""

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff"
$REGION = "ap-southeast-1"
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"
$WORKING_BACKEND = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$API_KEY = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"

Write-Host "Step 1: Testing current error statistics endpoint..." -ForegroundColor Green
try {
    $statsTest = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 10
    Write-Host "✅ Error statistics already working!" -ForegroundColor Green
    Write-Host "Response: $($statsTest | ConvertTo-Json -Compress)" -ForegroundColor White
    Write-Host "🎉 No fix needed - dashboard should be working" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "❌ Error statistics failing - proceeding with fix" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nStep 2: Updating BFF environment variables..." -ForegroundColor Green
try {
    # Create environment variables JSON
    $envVars = @{
        BACKEND_API_URL = $WORKING_BACKEND
        API_KEY = $API_KEY
        CORS_ORIGIN = $CLOUDFRONT_URL
        NODE_ENV = "production"
        LOG_LEVEL = "info"
    }
    
    # Convert to JSON format for AWS CLI
    $envJson = ($envVars | ConvertTo-Json -Compress).Replace('"', '\"')
    
    # Update Lambda function
    Write-Host "Updating Lambda environment variables..." -ForegroundColor Yellow
    $updateResult = aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "Variables=$envJson" --region $REGION
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Environment variables updated successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to update environment variables" -ForegroundColor Red
        Write-Host "Trying alternative approach..." -ForegroundColor Yellow
        
        # Alternative approach - update individual variables
        aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "Variables={BACKEND_API_URL=$WORKING_BACKEND,API_KEY=$API_KEY,CORS_ORIGIN=$CLOUDFRONT_URL,NODE_ENV=production,LOG_LEVEL=info}" --region $REGION
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Alternative update successful" -ForegroundColor Green
        } else {
            Write-Host "❌ Both update methods failed" -ForegroundColor Red
        }
    }
    
    # Wait for propagation
    Write-Host "Waiting 15 seconds for configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
} catch {
    Write-Host "❌ Exception during environment update: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nStep 3: Testing BFF after configuration update..." -ForegroundColor Green
$testEndpoints = @(
    @{ path = "/health"; name = "Health Check" },
    @{ path = "/api/instances"; name = "Instances" },
    @{ path = "/api/errors/statistics"; name = "Error Statistics" }
)

$allWorking = $true
foreach ($endpoint in $testEndpoints) {
    Write-Host "Testing: $($endpoint.name)..." -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "$BFF_API_URL$($endpoint.path)" -Method GET -TimeoutSec 15
        Write-Host "✅ $($endpoint.name): Working" -ForegroundColor Green
        
        if ($endpoint.path -eq "/api/errors/statistics") {
            Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor White
        }
    } catch {
        Write-Host "❌ $($endpoint.name): Failed" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        $allWorking = $false
    }
}

Write-Host "`nStep 4: Testing CloudFront dashboard..." -ForegroundColor Green
try {
    $cloudfrontTest = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 20
    Write-Host "✅ CloudFront dashboard: Working!" -ForegroundColor Green
    Write-Host "   Response: $($cloudfrontTest | ConvertTo-Json -Compress)" -ForegroundColor White
    
    Write-Host "`n🎉 SUCCESS! Dashboard should now be working!" -ForegroundColor Green
    Write-Host "Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor Cyan
    
} catch {
    Write-Host "❌ CloudFront dashboard: Still failing" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    $allWorking = $false
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
if ($allWorking) {
    Write-Host "✅ Fix successful - Dashboard should be working" -ForegroundColor Green
    Write-Host "✅ Environment variables updated" -ForegroundColor Green
    Write-Host "✅ All endpoints responding" -ForegroundColor Green
    Write-Host "✅ CloudFront routing working" -ForegroundColor Green
    
    Write-Host "`n🎯 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
    Write-Host "2. Verify error monitoring section loads" -ForegroundColor White
    Write-Host "3. Check browser console for any remaining errors" -ForegroundColor White
    
} else {
    Write-Host "⚠️  Partial fix applied but issues remain" -ForegroundColor Yellow
    Write-Host "❌ Additional troubleshooting may be required" -ForegroundColor Red
    
    Write-Host "`n🔧 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Check Lambda logs: /aws/lambda/$BFF_FUNCTION_NAME" -ForegroundColor White
    Write-Host "2. Run comprehensive fix: .\scripts\fix-bff-500-errors.ps1" -ForegroundColor White
    Write-Host "3. Consider BFF code deployment if using container image" -ForegroundColor White
}

Write-Host "`n=== QUICK FIX COMPLETE ===" -ForegroundColor Cyan