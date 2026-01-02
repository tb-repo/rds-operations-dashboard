# Comprehensive CORS Verification Script
# Tests all aspects of CORS functionality for the RDS Dashboard BFF

param(
    [Parameter(Mandatory=$false)]
    [string]$BffUrl = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com",
    
    [Parameter(Mandatory=$false)]
    [string]$CloudFrontOrigin = "https://d2qvaswtmn22om.cloudfront.net"
)

Write-Host "Comprehensive CORS Verification" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "BFF URL: $BffUrl" -ForegroundColor Cyan
Write-Host "CloudFront Origin: $CloudFrontOrigin" -ForegroundColor Cyan

$testResults = @()

# Test 1: Health endpoint OPTIONS request
Write-Host "`nTest 1: Health endpoint OPTIONS request" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method OPTIONS -Headers @{
        "Origin" = $CloudFrontOrigin
        "Access-Control-Request-Method" = "GET"
        "Access-Control-Request-Headers" = "Content-Type,Authorization"
    } -UseBasicParsing
    
    $testResults += @{
        Test = "Health OPTIONS"
        Status = "PASS"
        Details = "Status: $($response.StatusCode)"
    }
    Write-Host "PASS - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    $testResults += @{
        Test = "Health OPTIONS"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
    Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Health endpoint GET request
Write-Host "`nTest 2: Health endpoint GET request" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method GET -Headers @{
        "Origin" = $CloudFrontOrigin
    } -UseBasicParsing
    
    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -eq $CloudFrontOrigin) {
        $testResults += @{
            Test = "Health GET"
            Status = "PASS"
            Details = "Status: $($response.StatusCode), CORS: $allowOrigin"
        }
        Write-Host "PASS - Status: $($response.StatusCode), CORS header correct" -ForegroundColor Green
    } else {
        $testResults += @{
            Test = "Health GET"
            Status = "FAIL"
            Details = "Wrong CORS header: $allowOrigin"
        }
        Write-Host "FAIL - Wrong CORS header: $allowOrigin" -ForegroundColor Red
    }
} catch {
    $testResults += @{
        Test = "Health GET"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
    Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Root health endpoint
Write-Host "`nTest 3: Root health endpoint" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/health" -Method GET -Headers @{
        "Origin" = $CloudFrontOrigin
    } -UseBasicParsing
    
    $testResults += @{
        Test = "Root Health"
        Status = "PASS"
        Details = "Status: $($response.StatusCode)"
    }
    Write-Host "PASS - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    $testResults += @{
        Test = "Root Health"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
    Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Invalid origin rejection
Write-Host "`nTest 4: Invalid origin rejection" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method GET -Headers @{
        "Origin" = "https://malicious-site.com"
    } -UseBasicParsing
    
    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -eq "https://malicious-site.com") {
        $testResults += @{
            Test = "Invalid Origin"
            Status = "FAIL"
            Details = "Security issue: Invalid origin allowed"
        }
        Write-Host "FAIL - Security issue: Invalid origin was allowed!" -ForegroundColor Red
    } else {
        $testResults += @{
            Test = "Invalid Origin"
            Status = "PASS"
            Details = "Invalid origin properly rejected"
        }
        Write-Host "PASS - Invalid origin properly rejected" -ForegroundColor Green
    }
} catch {
    $testResults += @{
        Test = "Invalid Origin"
        Status = "PASS"
        Details = "Request properly blocked"
    }
    Write-Host "PASS - Request properly blocked (expected)" -ForegroundColor Green
}

# Test 5: Localhost origin (should work for development)
Write-Host "`nTest 5: Localhost origin support" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method GET -Headers @{
        "Origin" = "http://localhost:3000"
    } -UseBasicParsing
    
    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"]
    if ($allowOrigin -eq "http://localhost:3000") {
        $testResults += @{
            Test = "Localhost Origin"
            Status = "PASS"
            Details = "Localhost origin supported"
        }
        Write-Host "PASS - Localhost origin supported" -ForegroundColor Green
    } else {
        $testResults += @{
            Test = "Localhost Origin"
            Status = "INFO"
            Details = "Localhost not in allowed origins (production mode)"
        }
        Write-Host "INFO - Localhost not allowed (production mode)" -ForegroundColor Yellow
    }
} catch {
    $testResults += @{
        Test = "Localhost Origin"
        Status = "INFO"
        Details = "Localhost blocked (production mode)"
    }
    Write-Host "INFO - Localhost blocked (production mode)" -ForegroundColor Yellow
}

# Test 6: CORS headers completeness
Write-Host "`nTest 6: CORS headers completeness" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method OPTIONS -Headers @{
        "Origin" = $CloudFrontOrigin
        "Access-Control-Request-Method" = "POST"
        "Access-Control-Request-Headers" = "Content-Type,Authorization,x-api-key"
    } -UseBasicParsing
    
    $requiredHeaders = @(
        "Access-Control-Allow-Origin",
        "Access-Control-Allow-Methods",
        "Access-Control-Allow-Headers",
        "Access-Control-Allow-Credentials"
    )
    
    $missingHeaders = @()
    foreach ($header in $requiredHeaders) {
        if (-not $response.Headers[$header]) {
            $missingHeaders += $header
        }
    }
    
    if ($missingHeaders.Count -eq 0) {
        $testResults += @{
            Test = "CORS Headers"
            Status = "PASS"
            Details = "All required CORS headers present"
        }
        Write-Host "PASS - All required CORS headers present" -ForegroundColor Green
    } else {
        $testResults += @{
            Test = "CORS Headers"
            Status = "FAIL"
            Details = "Missing headers: $($missingHeaders -join ', ')"
        }
        Write-Host "FAIL - Missing headers: $($missingHeaders -join ', ')" -ForegroundColor Red
    }
} catch {
    $testResults += @{
        Test = "CORS Headers"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
    Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
}

# Summary
Write-Host "`n" -NoNewline
Write-Host "CORS Verification Summary" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

$passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$infoCount = ($testResults | Where-Object { $_.Status -eq "INFO" }).Count

foreach ($result in $testResults) {
    $color = switch ($result.Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "INFO" { "Yellow" }
    }
    Write-Host "$($result.Status.PadRight(4)) - $($result.Test): $($result.Details)" -ForegroundColor $color
}

Write-Host "`nResults: $passCount PASS, $failCount FAIL, $infoCount INFO" -ForegroundColor Cyan

if ($failCount -eq 0) {
    Write-Host "`nCORS configuration is working correctly!" -ForegroundColor Green
    Write-Host "The dashboard should now be accessible from: $CloudFrontOrigin" -ForegroundColor Green
} else {
    Write-Host "`nCORS configuration has issues that need to be addressed." -ForegroundColor Red
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Access the dashboard at: $CloudFrontOrigin" -ForegroundColor White
Write-Host "2. Check browser developer tools for any CORS errors" -ForegroundColor White
Write-Host "3. Test actual API calls from the frontend" -ForegroundColor White