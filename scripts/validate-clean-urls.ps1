# Validate Clean URL Patterns
# This script validates that all API Gateway URLs work without /prod suffix

param(
    [Parameter(Mandatory=$false)]
    [switch]$Verbose = $false
)

Write-Host "=== API Gateway Clean URL Validation ===" -ForegroundColor Cyan
Write-Host "Testing API endpoints without /prod suffix" -ForegroundColor Yellow
Write-Host ""

# Configuration - Clean URLs without /prod
$BFF_API_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$INTERNAL_API_URL = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$CLOUDFRONT_URL = "https://d2qvaswtmn22om.cloudfront.net"

# Test endpoints
$testEndpoints = @(
    @{ 
        name = "BFF Health Check"
        url = "$BFF_API_URL/health"
        method = "GET"
        requiresAuth = $false
        expectedStatus = 200
    },
    @{ 
        name = "BFF API Instances (should require auth)"
        url = "$BFF_API_URL/api/instances"
        method = "GET"
        requiresAuth = $true
        expectedStatus = 401
    },
    @{ 
        name = "Frontend (CloudFront)"
        url = $CLOUDFRONT_URL
        method = "GET"
        requiresAuth = $false
        expectedStatus = 200
    }
)

$allPassed = $true

foreach ($endpoint in $testEndpoints) {
    Write-Host "Testing: $($endpoint.name)" -ForegroundColor Yellow
    Write-Host "  URL: $($endpoint.url)" -ForegroundColor Gray
    
    try {
        $response = Invoke-WebRequest -Uri $endpoint.url -Method $endpoint.method -UseBasicParsing -TimeoutSec 10
        
        if ($response.StatusCode -eq $endpoint.expectedStatus) {
            Write-Host "  ✅ PASS - Status: $($response.StatusCode)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  UNEXPECTED - Status: $($response.StatusCode), Expected: $($endpoint.expectedStatus)" -ForegroundColor Yellow
        }
        
        if ($Verbose) {
            Write-Host "  Response Headers:" -ForegroundColor Gray
            $response.Headers.GetEnumerator() | ForEach-Object {
                Write-Host "    $($_.Key): $($_.Value)" -ForegroundColor DarkGray
            }
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq $endpoint.expectedStatus) {
            Write-Host "  ✅ PASS - Status: $statusCode (expected for auth-required endpoint)" -ForegroundColor Green
        } else {
            Write-Host "  ❌ FAIL - Status: $statusCode, Error: $($_.Exception.Message)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    
    Write-Host ""
}

# URL Pattern Validation
Write-Host "=== URL Pattern Validation ===" -ForegroundColor Cyan

$urlsToCheck = @($BFF_API_URL, $INTERNAL_API_URL)
$invalidPatterns = @('/prod', '/staging', '/dev')

foreach ($url in $urlsToCheck) {
    $hasInvalidPattern = $false
    foreach ($pattern in $invalidPatterns) {
        if ($url.Contains($pattern)) {
            Write-Host "❌ INVALID URL PATTERN: $url contains $pattern" -ForegroundColor Red
            $hasInvalidPattern = $true
            $allPassed = $false
        }
    }
    
    if (-not $hasInvalidPattern) {
        Write-Host "✅ CLEAN URL: $url" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan

if ($allPassed) {
    Write-Host "✅ ALL TESTS PASSED - Clean URL patterns are working correctly!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Deploy infrastructure changes (CDK deploy)" -ForegroundColor White
    Write-Host "2. Update remaining scripts with clean URLs" -ForegroundColor White
    Write-Host "3. Test full application functionality" -ForegroundColor White
} else {
    Write-Host "❌ SOME TESTS FAILED - Please check the issues above" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "1. Infrastructure not yet deployed with $default stage" -ForegroundColor White
    Write-Host "2. DNS propagation delay" -ForegroundColor White
    Write-Host "3. API Gateway configuration issues" -ForegroundColor White
}

Write-Host ""
Write-Host "Current URL Configuration:" -ForegroundColor Cyan
Write-Host "  BFF API: $BFF_API_URL" -ForegroundColor White
Write-Host "  Internal API: $INTERNAL_API_URL" -ForegroundColor White
Write-Host "  Frontend: $CLOUDFRONT_URL" -ForegroundColor White