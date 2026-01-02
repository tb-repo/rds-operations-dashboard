# Test CORS Configuration Fix
# This script tests if the BFF Lambda function correctly handles CORS requests

param(
    [Parameter(Mandatory=$false)]
    [string]$BffUrl = "https://xxxxxxxx.execute-api.ap-southeast-1.amazonaws.com/prod",
    
    [Parameter(Mandatory=$false)]
    [string]$Origin = "https://d2qvaswtmn22om.cloudfront.net"
)

Write-Host "Testing CORS Configuration..." -ForegroundColor Green
Write-Host "BFF URL: $BffUrl" -ForegroundColor Cyan
Write-Host "Origin: $Origin" -ForegroundColor Cyan

# Test 1: OPTIONS preflight request
Write-Host "`nTest 1: OPTIONS preflight request" -ForegroundColor Yellow
try {
    $optionsResponse = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method OPTIONS -Headers @{
        "Origin" = $Origin
        "Access-Control-Request-Method" = "GET"
        "Access-Control-Request-Headers" = "Content-Type,Authorization"
    } -UseBasicParsing
    
    Write-Host "✅ OPTIONS request successful" -ForegroundColor Green
    Write-Host "Status Code: $($optionsResponse.StatusCode)" -ForegroundColor White
    
    # Check CORS headers
    $corsHeaders = @(
        "Access-Control-Allow-Origin",
        "Access-Control-Allow-Methods", 
        "Access-Control-Allow-Headers",
        "Access-Control-Allow-Credentials"
    )
    
    foreach ($header in $corsHeaders) {
        $headerValue = $optionsResponse.Headers[$header]
        if ($headerValue) {
            Write-Host "✅ $header`: $headerValue" -ForegroundColor Green
        } else {
            Write-Host "❌ Missing header: $header" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "❌ OPTIONS request failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: GET request with Origin header
Write-Host "`nTest 2: GET request with Origin header" -ForegroundColor Yellow
try {
    $getResponse = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method GET -Headers @{
        "Origin" = $Origin
    } -UseBasicParsing
    
    Write-Host "✅ GET request successful" -ForegroundColor Green
    Write-Host "Status Code: $($getResponse.StatusCode)" -ForegroundColor White
    Write-Host "Response: $($getResponse.Content)" -ForegroundColor White
    
    # Check CORS headers in response
    $allowOrigin = $getResponse.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -eq $Origin) {
        Write-Host "✅ Access-Control-Allow-Origin: $allowOrigin" -ForegroundColor Green
    } else {
        Write-Host "❌ Incorrect Access-Control-Allow-Origin. Expected: $Origin, Got: $allowOrigin" -ForegroundColor Red
    }
    
} catch {
    Write-Host "❌ GET request failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Request from invalid origin
Write-Host "`nTest 3: Request from invalid origin" -ForegroundColor Yellow
try {
    $invalidResponse = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method GET -Headers @{
        "Origin" = "https://malicious-site.com"
    } -UseBasicParsing
    
    $allowOrigin = $invalidResponse.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -eq "https://malicious-site.com") {
        Write-Host "❌ Security issue: Invalid origin was allowed!" -ForegroundColor Red
    } else {
        Write-Host "✅ Invalid origin correctly rejected or no CORS headers sent" -ForegroundColor Green
    }
    
} catch {
    Write-Host "✅ Invalid origin request properly handled (expected behavior)" -ForegroundColor Green
}

Write-Host "`nCORS Test Summary:" -ForegroundColor Cyan
Write-Host "- Tested BFF endpoint: $BffUrl/api/health" -ForegroundColor White
Write-Host "- Valid origin: $Origin" -ForegroundColor White
Write-Host "- Check the results above to verify CORS is working correctly" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. If tests pass, try accessing the dashboard from: $Origin" -ForegroundColor White
Write-Host "2. Check browser developer tools for any remaining CORS errors" -ForegroundColor White
Write-Host "3. Verify all API endpoints work correctly" -ForegroundColor White