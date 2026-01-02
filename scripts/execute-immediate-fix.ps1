# Execute Immediate Fix for Production Dashboard 500 Errors
# Implements the critical path solution following the approved spec

Write-Host "=== PRODUCTION DASHBOARD 500 ERROR - IMMEDIATE FIX ===" -ForegroundColor Cyan
Write-Host "Executing critical path solution for persistent 500 errors" -ForegroundColor Yellow
Write-Host ""

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff"
$REGION = "ap-southeast-1"
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"
$WORKING_BACKEND = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$API_KEY = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"

Write-Host "PHASE 1: IMMEDIATE DIAGNOSTIC" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# Step 1: Quick diagnosis
Write-Host "`n1.1 Testing current BFF status..." -ForegroundColor Yellow
try {
    $bffTest = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✅ BFF function is responding" -ForegroundColor Green
} catch {
    Write-Host "❌ BFF function not responding: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 2: Test the problematic endpoint
Write-Host "`n1.2 Testing error statistics endpoint..." -ForegroundColor Yellow
try {
    $statsTest = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✅ Error statistics working: $($statsTest | ConvertTo-Json -Compress)" -ForegroundColor Green
    Write-Host "🎉 ISSUE ALREADY RESOLVED! No further action needed." -ForegroundColor Green
    exit 0
} catch {
    Write-Host "❌ Error statistics failing: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

Write-Host "`nPHASE 2: ENVIRONMENT CONFIGURATION FIX" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# Step 3: Update Lambda environment variables
Write-Host "`n2.1 Updating BFF environment variables..." -ForegroundColor Yellow
try {
    $envVars = @{
        "BACKEND_API_URL" = $WORKING_BACKEND
        "API_KEY" = $API_KEY
        "CORS_ORIGIN" = $CLOUDFRONT_URL
        "NODE_ENV" = "production"
        "LOG_LEVEL" = "info"
    }
    
    $envJson = ($envVars | ConvertTo-Json -Compress).Replace('"', '\"')
    
    $updateCmd = "aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment `"Variables=$envJson`" --region $REGION"
    $updateResult = Invoke-Expression $updateCmd
    
    Write-Host "✅ Environment variables updated successfully" -ForegroundColor Green
    Write-Host "   Backend URL: $WORKING_BACKEND" -ForegroundColor White
    Write-Host "   CORS Origin: $CLOUDFRONT_URL" -ForegroundColor White
    
    # Wait for propagation
    Write-Host "`n2.2 Waiting for configuration to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
} catch {
    Write-Host "❌ Failed to update environment variables: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Attempting manual configuration..." -ForegroundColor Yellow
    
    # Try individual variable updates
    try {
        aws lambda update-function-configuration --function-name $BFF_FUNCTION_NAME --environment "Variables={BACKEND_API_URL=$WORKING_BACKEND,API_KEY=$API_KEY,CORS_ORIGIN=$CLOUDFRONT_URL,NODE_ENV=production,LOG_LEVEL=info}" --region $REGION
        Write-Host "✅ Manual environment update successful" -ForegroundColor Green
        Start-Sleep -Seconds 15
    } catch {
        Write-Host "❌ Manual update also failed" -ForegroundColor Red
    }
}

Write-Host "`nPHASE 3: IMMEDIATE TESTING" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# Step 4: Test BFF after environment update
Write-Host "`n3.1 Testing BFF after environment update..." -ForegroundColor Yellow
$testEndpoints = @(
    @{ path = "/health"; name = "Health Check" },
    @{ path = "/api/instances"; name = "Instances" },
    @{ path = "/api/errors/statistics"; name = "Error Statistics" }
)

$allWorking = $true
foreach ($endpoint in $testEndpoints) {
    try {
        $response = Invoke-RestMethod -Uri "$BFF_API_URL$($endpoint.path)" -Method GET -TimeoutSec 15 -ErrorAction Stop
        Write-Host "✅ $($endpoint.name): Working" -ForegroundColor Green
        
        if ($endpoint.path -eq "/api/errors/statistics") {
            Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor White
        }
    } catch {
        Write-Host "❌ $($endpoint.name): $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
        $allWorking = $false
    }
}

# Step 5: Test CloudFront routing
Write-Host "`n3.2 Testing CloudFront to BFF routing..." -ForegroundColor Yellow
try {
    $cloudfrontTest = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 20 -ErrorAction Stop
    Write-Host "✅ CloudFront routing: Working" -ForegroundColor Green
    Write-Host "   Response: $($cloudfrontTest | ConvertTo-Json -Compress)" -ForegroundColor White
    
    Write-Host "`n🎉 SUCCESS! Dashboard should now be working!" -ForegroundColor Green
    Write-Host "Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor Cyan
    
} catch {
    Write-Host "❌ CloudFront routing: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    $allWorking = $false
}

if (-not $allWorking) {
    Write-Host "`nPHASE 4: ADVANCED TROUBLESHOOTING" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    
    # Step 6: Check Lambda logs for errors
    Write-Host "`n4.1 Checking Lambda logs for errors..." -ForegroundColor Yellow
    try {
        $logGroups = aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$BFF_FUNCTION_NAME" --region $REGION | ConvertFrom-Json
        
        if ($logGroups.logGroups.Count -gt 0) {
            $logGroupName = $logGroups.logGroups[0].logGroupName
            Write-Host "✅ Found log group: $logGroupName" -ForegroundColor Green
            
            # Get recent log streams
            $logStreams = aws logs describe-log-streams --log-group-name $logGroupName --order-by LastEventTime --descending --max-items 2 --region $REGION | ConvertFrom-Json
            
            if ($logStreams.logStreams.Count -gt 0) {
                $logStreamName = $logStreams.logStreams[0].logStreamName
                Write-Host "Getting recent logs from: $logStreamName" -ForegroundColor Yellow
                
                # Get recent log events (last 10 minutes)
                $startTime = [int64]((Get-Date).AddMinutes(-10).ToUniversalTime().Subtract((Get-Date "1970-01-01")).TotalMilliseconds)
                $logEvents = aws logs get-log-events --log-group-name $logGroupName --log-stream-name $logStreamName --start-time $startTime --region $REGION | ConvertFrom-Json
                
                $errorEvents = $logEvents.events | Where-Object { $_.message -match "ERROR|error|Error|500|Internal Server Error|Exception" } | Select-Object -First 5
                
                if ($errorEvents.Count -gt 0) {
                    Write-Host "❌ Recent errors found:" -ForegroundColor Red
                    foreach ($event in $errorEvents) {
                        $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($event.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
                        Write-Host "   [$timestamp] $($event.message)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "✅ No recent errors in logs" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "⚠️  Could not retrieve logs: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Step 7: Test backend connectivity directly
    Write-Host "`n4.2 Testing backend connectivity..." -ForegroundColor Yellow
    try {
        $headers = @{ "x-api-key" = $API_KEY }
        $backendTest = Invoke-RestMethod -Uri "$WORKING_BACKEND/api/instances" -Method GET -Headers $headers -TimeoutSec 10
        Write-Host "✅ Backend connectivity: Working" -ForegroundColor Green
        
        # Test error statistics on backend
        try {
            $backendStats = Invoke-RestMethod -Uri "$WORKING_BACKEND/api/errors/statistics" -Method GET -Headers $headers -TimeoutSec 10
            Write-Host "✅ Backend error statistics: Available" -ForegroundColor Green
        } catch {
            Write-Host "❌ Backend error statistics: Not available" -ForegroundColor Red
            Write-Host "   This explains the 500 error - backend doesn't have this endpoint" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "❌ Backend connectivity: Failed" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nPHASE 5: SUMMARY AND RECOMMENDATIONS" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Write-Host "`nFIX SUMMARY:" -ForegroundColor Cyan
if ($allWorking) {
    Write-Host "✅ Environment configuration fix successful" -ForegroundColor Green
    Write-Host "✅ All BFF endpoints working" -ForegroundColor Green
    Write-Host "✅ CloudFront routing working" -ForegroundColor Green
    Write-Host "✅ Dashboard should be fully functional" -ForegroundColor Green
    
    Write-Host "`n🎯 VERIFICATION STEPS:" -ForegroundColor Yellow
    Write-Host "1. Visit: $CLOUDFRONT_URL/dashboard" -ForegroundColor White
    Write-Host "2. Check that error monitoring section loads" -ForegroundColor White
    Write-Host "3. Verify no 500 errors in browser console" -ForegroundColor White
    Write-Host "4. Test navigation between dashboard sections" -ForegroundColor White
    
} else {
    Write-Host "⚠️  Environment configuration applied but issues remain" -ForegroundColor Yellow
    Write-Host "❌ Additional code-level fixes may be required" -ForegroundColor Red
    
    Write-Host "`n🔧 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. The backend may not have the error statistics endpoint" -ForegroundColor White
    Write-Host "2. BFF code may need error statistics fallback implementation" -ForegroundColor White
    Write-Host "3. Consider running the comprehensive BFF fix script" -ForegroundColor White
    Write-Host "4. Check Lambda function code for missing endpoint handlers" -ForegroundColor White
    
    Write-Host "`n📋 RECOMMENDED ACTIONS:" -ForegroundColor Yellow
    Write-Host "1. Run: .\scripts\fix-bff-500-errors.ps1" -ForegroundColor White
    Write-Host "2. Implement error statistics fallback in BFF code" -ForegroundColor White
    Write-Host "3. Deploy updated BFF function with missing endpoints" -ForegroundColor White
}

Write-Host "`n📊 MONITORING:" -ForegroundColor Yellow
Write-Host "- Lambda logs: /aws/lambda/$BFF_FUNCTION_NAME" -ForegroundColor White
Write-Host "- API Gateway: $BFF_API_URL" -ForegroundColor White
Write-Host "- CloudFront: $CLOUDFRONT_URL" -ForegroundColor White

Write-Host "`n=== IMMEDIATE FIX EXECUTION COMPLETE ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray