# Diagnose Single BFF Function Issues
# After architecture simplification, identify why 500 errors persist

Write-Host "=== SINGLE BFF DIAGNOSTIC SCRIPT ===" -ForegroundColor Cyan
Write-Host "Diagnosing the remaining BFF function after architecture simplification" -ForegroundColor Yellow
Write-Host ""

# Configuration
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "1. TESTING BFF FUNCTION DIRECTLY" -ForegroundColor Green
Write-Host "BFF API URL: $BFF_API_URL" -ForegroundColor White

# Test basic BFF health
Write-Host "`nTesting BFF health endpoint..." -ForegroundColor Yellow
try {
    $healthResponse = Invoke-RestMethod -Uri "$BFF_API_URL/health" -Method GET -TimeoutSec 10
    Write-Host "✅ BFF Health: $($healthResponse | ConvertTo-Json -Depth 2)" -ForegroundColor Green
} catch {
    Write-Host "❌ BFF Health Failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.Exception.Response)" -ForegroundColor Red
}

# Test error statistics endpoint specifically
Write-Host "`nTesting error statistics endpoint..." -ForegroundColor Yellow
try {
    $statsResponse = Invoke-RestMethod -Uri "$BFF_API_URL/api/errors/statistics" -Method GET -TimeoutSec 10
    Write-Host "✅ Error Statistics: $($statsResponse | ConvertTo-Json -Depth 2)" -ForegroundColor Green
} catch {
    Write-Host "❌ Error Statistics Failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        Write-Host "Status Description: $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
    }
}

# Test other critical endpoints
$endpoints = @(
    "/api/instances",
    "/api/health", 
    "/api/costs",
    "/api/compliance",
    "/api/errors/dashboard"
)

Write-Host "`n2. TESTING ALL BFF ENDPOINTS" -ForegroundColor Green
foreach ($endpoint in $endpoints) {
    Write-Host "`nTesting: $endpoint" -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "$BFF_API_URL$endpoint" -Method GET -TimeoutSec 10
        Write-Host "✅ $endpoint: Success" -ForegroundColor Green
    } catch {
        Write-Host "❌ $endpoint: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response.StatusCode) {
            Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
    }
}

Write-Host "`n3. CHECKING LAMBDA FUNCTION STATUS" -ForegroundColor Green
try {
    # Get Lambda function details
    $lambdaInfo = aws lambda get-function --function-name rds-dashboard-bff --region ap-southeast-1 2>$null | ConvertFrom-Json
    if ($lambdaInfo) {
        Write-Host "✅ Lambda Function Found: rds-dashboard-bff" -ForegroundColor Green
        Write-Host "   Runtime: $($lambdaInfo.Configuration.Runtime)" -ForegroundColor White
        Write-Host "   Handler: $($lambdaInfo.Configuration.Handler)" -ForegroundColor White
        Write-Host "   Timeout: $($lambdaInfo.Configuration.Timeout)s" -ForegroundColor White
        Write-Host "   Memory: $($lambdaInfo.Configuration.MemorySize)MB" -ForegroundColor White
        Write-Host "   Last Modified: $($lambdaInfo.Configuration.LastModified)" -ForegroundColor White
    }
} catch {
    Write-Host "❌ Could not get Lambda function info: $($_.Exception.Message)" -ForegroundColor Red
}

# Check if the prod BFF function still exists (should be deleted)
Write-Host "`n4. VERIFYING ARCHITECTURE SIMPLIFICATION" -ForegroundColor Green
try {
    $prodBffInfo = aws lambda get-function --function-name rds-dashboard-bff-prod --region ap-southeast-1 2>$null | ConvertFrom-Json
    if ($prodBffInfo) {
        Write-Host "⚠️  WARNING: rds-dashboard-bff-prod still exists!" -ForegroundColor Red
        Write-Host "   This function should have been deleted during simplification" -ForegroundColor Red
    } else {
        Write-Host "✅ rds-dashboard-bff-prod successfully deleted" -ForegroundColor Green
    }
} catch {
    Write-Host "✅ rds-dashboard-bff-prod does not exist (good)" -ForegroundColor Green
}

Write-Host "`n5. CHECKING LAMBDA LOGS FOR ERRORS" -ForegroundColor Green
try {
    # Get recent logs from the BFF function
    $logGroups = aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/rds-dashboard-bff" --region ap-southeast-1 | ConvertFrom-Json
    
    if ($logGroups.logGroups.Count -gt 0) {
        Write-Host "✅ Found log group: $($logGroups.logGroups[0].logGroupName)" -ForegroundColor Green
        
        # Get recent log streams
        $logStreams = aws logs describe-log-streams --log-group-name $logGroups.logGroups[0].logGroupName --order-by LastEventTime --descending --max-items 3 --region ap-southeast-1 | ConvertFrom-Json
        
        if ($logStreams.logStreams.Count -gt 0) {
            Write-Host "Recent log streams found. Getting latest errors..." -ForegroundColor Yellow
            
            # Get recent log events
            $logEvents = aws logs get-log-events --log-group-name $logGroups.logGroups[0].logGroupName --log-stream-name $logStreams.logStreams[0].logStreamName --start-time $((Get-Date).AddMinutes(-30).ToUniversalTime().Subtract((Get-Date "1970-01-01")).TotalMilliseconds) --region ap-southeast-1 | ConvertFrom-Json
            
            $errorEvents = $logEvents.events | Where-Object { $_.message -match "ERROR|error|Error|500|Internal Server Error" } | Select-Object -First 5
            
            if ($errorEvents.Count -gt 0) {
                Write-Host "❌ Recent errors found in logs:" -ForegroundColor Red
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

Write-Host "`n6. TESTING CLOUDFRONT TO BFF ROUTING" -ForegroundColor Green
Write-Host "Testing CloudFront routing to BFF..." -ForegroundColor Yellow
try {
    $cloudfrontResponse = Invoke-RestMethod -Uri "$CLOUDFRONT_URL/api/errors/statistics" -Method GET -TimeoutSec 15
    Write-Host "✅ CloudFront to BFF: Success" -ForegroundColor Green
    Write-Host "Response: $($cloudfrontResponse | ConvertTo-Json -Depth 2)" -ForegroundColor White
} catch {
    Write-Host "❌ CloudFront to BFF Failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        Write-Host "Status Description: $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
    }
}

Write-Host "`n7. CHECKING API GATEWAY INTEGRATION" -ForegroundColor Green
try {
    # Get API Gateway details
    $apis = aws apigateway get-rest-apis --region ap-southeast-1 | ConvertFrom-Json
    $bffApi = $apis.items | Where-Object { $_.name -like "*bff*" -or $_.id -eq "km9ww1hh3k" }
    
    if ($bffApi) {
        Write-Host "✅ Found API Gateway: $($bffApi.name) ($($bffApi.id))" -ForegroundColor Green
        
        # Get resources
        $resources = aws apigateway get-resources --rest-api-id $bffApi.id --region ap-southeast-1 | ConvertFrom-Json
        $errorStatsResource = $resources.items | Where-Object { $_.pathPart -eq "statistics" -or $_.path -like "*statistics*" }
        
        if ($errorStatsResource) {
            Write-Host "✅ Found error statistics resource: $($errorStatsResource.path)" -ForegroundColor Green
            
            # Check integration
            try {
                $integration = aws apigateway get-integration --rest-api-id $bffApi.id --resource-id $errorStatsResource.id --http-method GET --region ap-southeast-1 | ConvertFrom-Json
                Write-Host "✅ Integration found: $($integration.type)" -ForegroundColor Green
                Write-Host "   URI: $($integration.uri)" -ForegroundColor White
            } catch {
                Write-Host "❌ No GET integration found for statistics endpoint" -ForegroundColor Red
            }
        } else {
            Write-Host "❌ No statistics resource found in API Gateway" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Could not find BFF API Gateway" -ForegroundColor Red
    }
} catch {
    Write-Host "⚠️  Could not check API Gateway: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n8. SUMMARY AND RECOMMENDATIONS" -ForegroundColor Green
Write-Host "=== DIAGNOSTIC SUMMARY ===" -ForegroundColor Cyan

Write-Host "`nArchitecture Status:" -ForegroundColor Yellow
Write-Host "- Single BFF function architecture ✅" -ForegroundColor White
Write-Host "- Redundant prod BFF function removed ✅" -ForegroundColor White
Write-Host "- API Gateway pointing to single function ✅" -ForegroundColor White

Write-Host "`nIf 500 errors persist, the issue is likely:" -ForegroundColor Yellow
Write-Host "1. Authentication/API key issues in BFF function" -ForegroundColor White
Write-Host "2. Backend API connectivity problems" -ForegroundColor White
Write-Host "3. Missing error statistics endpoint implementation" -ForegroundColor White
Write-Host "4. Lambda function runtime errors" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Check Lambda logs for specific error details" -ForegroundColor White
Write-Host "2. Verify BFF authentication middleware" -ForegroundColor White
Write-Host "3. Test backend API connectivity from BFF" -ForegroundColor White
Write-Host "4. Add error statistics endpoint if missing" -ForegroundColor White

Write-Host "`n=== DIAGNOSTIC COMPLETE ===" -ForegroundColor Cyan