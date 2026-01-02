# CORS Configuration Comprehensive Testing Script
# Tests CORS functionality across different scenarios and origins
# Requirements: 3.1, 3.2, 3.3, 3.4

param(
    [string]$BffUrl = "https://api.rds-dashboard.example.com",
    [string]$AllowedOrigin = "https://d2qvaswtmn22om.cloudfront.net",
    [string]$TestOrigin = "https://malicious-site.com",
    [switch]$Verbose = $false
)

Write-Host "=== CORS Configuration Comprehensive Test ===" -ForegroundColor Cyan
Write-Host "BFF URL: $BffUrl" -ForegroundColor Yellow
Write-Host "Allowed Origin: $AllowedOrigin" -ForegroundColor Yellow
Write-Host "Test (Disallowed) Origin: $TestOrigin" -ForegroundColor Yellow
Write-Host ""

$testResults = @()
$totalTests = 0
$passedTests = 0

function Test-CorsRequest {
    param(
        [string]$Url,
        [string]$Origin,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$TestName,
        [bool]$ShouldSucceed = $true
    )
    
    $global:totalTests++
    Write-Host "Testing: $TestName" -ForegroundColor White
    
    try {
        # Add CORS headers
        $requestHeaders = $Headers.Clone()
        if ($Origin) {
            $requestHeaders["Origin"] = $Origin
        }
        
        if ($Method -eq "OPTIONS") {
            $requestHeaders["Access-Control-Request-Method"] = "GET"
            $requestHeaders["Access-Control-Request-Headers"] = "Content-Type,Authorization"
        }
        
        $response = Invoke-WebRequest -Uri $Url -Method $Method -Headers $requestHeaders -UseBasicParsing -ErrorAction Stop
        
        # Check CORS headers in response
        $corsOrigin = $response.Headers["Access-Control-Allow-Origin"]
        $corsCredentials = $response.Headers["Access-Control-Allow-Credentials"]
        $corsMethods = $response.Headers["Access-Control-Allow-Methods"]
        $corsHeaders = $response.Headers["Access-Control-Allow-Headers"]
        
        $result = @{
            TestName = $TestName
            Status = "PASS"
            StatusCode = $response.StatusCode
            Origin = $Origin
            CorsOrigin = $corsOrigin
            CorsCredentials = $corsCredentials
            CorsMethods = $corsMethods
            CorsHeaders = $corsHeaders
            Details = "Request succeeded with status $($response.StatusCode)"
        }
        
        # Validate CORS headers for allowed origins
        if ($ShouldSucceed -and $Origin) {
            if (-not $corsOrigin) {
                $result.Status = "FAIL"
                $result.Details = "Missing Access-Control-Allow-Origin header"
            } elseif ($corsOrigin -ne $Origin -and $corsOrigin -ne "*") {
                $result.Status = "FAIL"
                $result.Details = "Access-Control-Allow-Origin mismatch. Expected: $Origin, Got: $corsOrigin"
            }
        }
        
        if ($result.Status -eq "PASS") {
            $global:passedTests++
            Write-Host "  ✓ PASS" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAIL: $($result.Details)" -ForegroundColor Red
        }
        
        if ($Verbose) {
            Write-Host "    Status Code: $($response.StatusCode)" -ForegroundColor Gray
            Write-Host "    CORS Origin: $corsOrigin" -ForegroundColor Gray
            Write-Host "    CORS Credentials: $corsCredentials" -ForegroundColor Gray
            Write-Host "    CORS Methods: $corsMethods" -ForegroundColor Gray
        }
        
    } catch {
        $result = @{
            TestName = $TestName
            Status = if ($ShouldSucceed) { "FAIL" } else { "PASS" }
            StatusCode = $_.Exception.Response.StatusCode.value__
            Origin = $Origin
            Details = $_.Exception.Message
        }
        
        if ($result.Status -eq "PASS") {
            $global:passedTests++
            Write-Host "  ✓ PASS (Expected failure)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        if ($Verbose) {
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }
    
    $global:testResults += $result
    Write-Host ""
}

# Test 1: OPTIONS Preflight Request from Allowed Origin
Test-CorsRequest -Url "$BffUrl/api/health" -Origin $AllowedOrigin -Method "OPTIONS" -TestName "OPTIONS preflight from allowed origin" -ShouldSucceed $true

# Test 2: GET Request from Allowed Origin
Test-CorsRequest -Url "$BffUrl/api/health" -Origin $AllowedOrigin -Method "GET" -TestName "GET request from allowed origin" -ShouldSucceed $true

# Test 3: POST Request from Allowed Origin
Test-CorsRequest -Url "$BffUrl/api/instances" -Origin $AllowedOrigin -Method "POST" -Headers @{"Content-Type"="application/json"} -TestName "POST request from allowed origin" -ShouldSucceed $true

# Test 4: Request from Disallowed Origin (should fail)
Test-CorsRequest -Url "$BffUrl/api/health" -Origin $TestOrigin -Method "GET" -TestName "GET request from disallowed origin" -ShouldSucceed $false

# Test 5: OPTIONS Preflight from Disallowed Origin (should fail)
Test-CorsRequest -Url "$BffUrl/api/health" -Origin $TestOrigin -Method "OPTIONS" -TestName "OPTIONS preflight from disallowed origin" -ShouldSucceed $false

# Test 6: Request without Origin header (should succeed for same-origin)
Test-CorsRequest -Url "$BffUrl/api/health" -Origin $null -Method "GET" -TestName "GET request without Origin header" -ShouldSucceed $true

# Test 7: Complex CORS Request with Custom Headers
Test-CorsRequest -Url "$BffUrl/api/instances" -Origin $AllowedOrigin -Method "PUT" -Headers @{"Content-Type"="application/json"; "X-Api-Key"="test"} -TestName "PUT request with custom headers" -ShouldSucceed $true

# Test 8: Credentials Request
Test-CorsRequest -Url "$BffUrl/api/auth/user" -Origin $AllowedOrigin -Method "GET" -Headers @{"Authorization"="Bearer test-token"} -TestName "Authenticated request with credentials" -ShouldSucceed $true

Write-Host "=== Test Results Summary ===" -ForegroundColor Cyan
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $($totalTests - $passedTests)" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($passedTests / $totalTests) * 100, 2))%" -ForegroundColor Yellow
Write-Host ""

if ($passedTests -eq $totalTests) {
    Write-Host "🎉 All CORS tests passed! Configuration is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some CORS tests failed. Please review the configuration." -ForegroundColor Red
    
    Write-Host "`n=== Failed Tests Details ===" -ForegroundColor Yellow
    $testResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "- $($_.TestName): $($_.Details)" -ForegroundColor Red
    }
    
    Write-Host "`n=== Troubleshooting Tips ===" -ForegroundColor Yellow
    Write-Host "1. Verify BFF environment variables:" -ForegroundColor White
    Write-Host "   - CORS_ORIGINS should include: $AllowedOrigin" -ForegroundColor Gray
    Write-Host "   - FRONTEND_URL should be set correctly" -ForegroundColor Gray
    Write-Host "2. Check BFF Lambda function deployment status" -ForegroundColor White
    Write-Host "3. Verify API Gateway CORS configuration" -ForegroundColor White
    Write-Host "4. Check CloudWatch logs for CORS-related errors" -ForegroundColor White
    
    exit 1
}