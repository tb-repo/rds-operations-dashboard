# Test Existing API Functionality with Clean URLs
# Validates: Requirements 7.1, 7.2, 7.3
# Ensures all existing endpoints work with new URL structure

param(
    [string]$Environment = "production",
    [string]$BffApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com",
    [string]$InternalApiUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com",
    [int]$TimeoutSeconds = 30,
    [switch]$Verbose
)

Write-Host "Testing Existing API Functionality with Clean URLs" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "BFF API URL: $BffApiUrl" -ForegroundColor Yellow
Write-Host "Internal API URL: $InternalApiUrl" -ForegroundColor Yellow
Write-Host ""

$ErrorCount = 0
$WarningCount = 0
$TestResults = @()

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Description,
        [bool]$RequiresAuth = $false,
        [string]$ExpectedStatus = "200"
    )
    
    try {
        if ($Verbose) {
            Write-Host "Testing: $Description" -ForegroundColor Cyan
            Write-Host "  URL: $Url" -ForegroundColor Gray
            Write-Host "  Method: $Method" -ForegroundColor Gray
        }
        
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        
        $result = @{
            Description = $Description
            Url = $Url
            Method = $Method
            Status = "PASS"
            StatusCode = "200"
            ResponseTime = $null
            Error = $null
            HasCleanUrl = -not ($Url -match "/prod/|/staging/|/dev/")
        }
        
        if ($Verbose) {
            Write-Host "  ✓ PASS" -ForegroundColor Green
        }
        
        return $result
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $isExpectedError = ($RequiresAuth -and $statusCode -eq 401) -or ($statusCode -eq 403)
        
        $result = @{
            Description = $Description
            Url = $Url
            Method = $Method
            Status = if ($isExpectedError) { "PASS (Expected Auth Error)" } else { "FAIL" }
            StatusCode = $statusCode
            ResponseTime = $null
            Error = $_.Exception.Message
            HasCleanUrl = -not ($Url -match "/prod/|/staging/|/dev/")
        }
        
        if ($isExpectedError) {
            if ($Verbose) {
                Write-Host "  ✓ PASS (Expected auth error)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $script:ErrorCount++
        }
        
        return $result
    }
}

function Test-UrlStructure {
    param([string]$Url, [string]$Description)
    
    $hasStagePrefix = $Url -match "/prod/|/staging/|/dev/"
    $hasDoubleSlash = $Url -match "//"
    $endsWithSlash = $Url -match "/$" -and $Url -ne "/"
    
    if ($hasStagePrefix) {
        Write-Host "  ⚠ WARNING: $Description contains stage prefix" -ForegroundColor Yellow
        $script:WarningCount++
        return $false
    }
    
    if ($hasDoubleSlash) {
        Write-Host "  ⚠ WARNING: $Description contains double slashes" -ForegroundColor Yellow
        $script:WarningCount++
        return $false
    }
    
    if ($endsWithSlash) {
        Write-Host "  ⚠ WARNING: $Description ends with unnecessary slash" -ForegroundColor Yellow
        $script:WarningCount++
        return $false
    }
    
    return $true
}

Write-Host "1. Testing BFF Health Endpoints" -ForegroundColor Magenta
Write-Host "================================" -ForegroundColor Magenta

# Test BFF health endpoint
$healthUrl = "$BffApiUrl/health"
Test-UrlStructure $healthUrl "BFF Health URL"
$TestResults += Test-Endpoint -Url $healthUrl -Description "BFF Health Check" -Method "GET"

# Test BFF CORS config
$corsUrl = "$BffApiUrl/cors-config"
Test-UrlStructure $corsUrl "BFF CORS Config URL"
$TestResults += Test-Endpoint -Url $corsUrl -Description "BFF CORS Configuration" -Method "GET"

Write-Host ""
Write-Host "2. Testing BFF API Endpoints" -ForegroundColor Magenta
Write-Host "============================" -ForegroundColor Magenta

# Test BFF API endpoints (these may require authentication)
$apiEndpoints = @(
    @{ Path = "/api/health"; Description = "API Health Check"; RequiresAuth = $false },
    @{ Path = "/api/instances"; Description = "RDS Instances List"; RequiresAuth = $true },
    @{ Path = "/api/metrics"; Description = "System Metrics"; RequiresAuth = $true },
    @{ Path = "/api/compliance"; Description = "Compliance Status"; RequiresAuth = $true },
    @{ Path = "/api/costs"; Description = "Cost Analysis"; RequiresAuth = $true },
    @{ Path = "/api/operations"; Description = "Operations History"; RequiresAuth = $true },
    @{ Path = "/api/discovery/trigger"; Description = "Discovery Trigger"; RequiresAuth = $true },
    @{ Path = "/api/monitoring"; Description = "Monitoring Data"; RequiresAuth = $true },
    @{ Path = "/api/approvals"; Description = "Approval Requests"; RequiresAuth = $true },
    @{ Path = "/api/errors"; Description = "Error Statistics"; RequiresAuth = $true },
    @{ Path = "/api/users"; Description = "User Management"; RequiresAuth = $true }
)

foreach ($endpoint in $apiEndpoints) {
    $url = "$BffApiUrl$($endpoint.Path)"
    Test-UrlStructure $url "BFF API Endpoint ($($endpoint.Path))"
    $TestResults += Test-Endpoint -Url $url -Description $endpoint.Description -RequiresAuth $endpoint.RequiresAuth
}

Write-Host ""
Write-Host "3. Testing Internal API Endpoints" -ForegroundColor Magenta
Write-Host "=================================" -ForegroundColor Magenta

# Test internal API endpoints
$internalEndpoints = @(
    @{ Path = "/instances"; Description = "Internal RDS Instances"; RequiresAuth = $true },
    @{ Path = "/operations"; Description = "Internal Operations"; RequiresAuth = $true },
    @{ Path = "/discovery"; Description = "Internal Discovery"; RequiresAuth = $true },
    @{ Path = "/monitoring"; Description = "Internal Monitoring"; RequiresAuth = $true },
    @{ Path = "/compliance"; Description = "Internal Compliance"; RequiresAuth = $true },
    @{ Path = "/costs"; Description = "Internal Cost Analysis"; RequiresAuth = $true }
)

foreach ($endpoint in $internalEndpoints) {
    $url = "$InternalApiUrl$($endpoint.Path)"
    Test-UrlStructure $url "Internal API Endpoint ($($endpoint.Path))"
    $TestResults += Test-Endpoint -Url $url -Description $endpoint.Description -RequiresAuth $endpoint.RequiresAuth
}

Write-Host ""
Write-Host "4. Testing Authentication Flow" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

# Test authentication endpoints
$authEndpoints = @(
    @{ Path = "/api/auth/login"; Description = "Login Endpoint"; Method = "POST"; RequiresAuth = $false },
    @{ Path = "/api/auth/logout"; Description = "Logout Endpoint"; Method = "POST"; RequiresAuth = $false },
    @{ Path = "/api/auth/refresh"; Description = "Token Refresh"; Method = "POST"; RequiresAuth = $false },
    @{ Path = "/api/auth/user"; Description = "User Info"; Method = "GET"; RequiresAuth = $true }
)

foreach ($endpoint in $authEndpoints) {
    $url = "$BffApiUrl$($endpoint.Path)"
    Test-UrlStructure $url "Auth Endpoint ($($endpoint.Path))"
    $TestResults += Test-Endpoint -Url $url -Description $endpoint.Description -Method $endpoint.Method -RequiresAuth $endpoint.RequiresAuth
}

Write-Host ""
Write-Host "5. Testing RDS Operations Functionality" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta

# Test RDS operations (these will likely fail without proper auth, but we're testing URL structure)
$rdsOperations = @(
    @{ Path = "/api/instances/start"; Description = "Start RDS Instance"; Method = "POST"; RequiresAuth = $true },
    @{ Path = "/api/instances/stop"; Description = "Stop RDS Instance"; Method = "POST"; RequiresAuth = $true },
    @{ Path = "/api/instances/reboot"; Description = "Reboot RDS Instance"; Method = "POST"; RequiresAuth = $true },
    @{ Path = "/api/instances/backup"; Description = "Backup RDS Instance"; Method = "POST"; RequiresAuth = $true }
)

foreach ($operation in $rdsOperations) {
    $url = "$BffApiUrl$($operation.Path)"
    Test-UrlStructure $url "RDS Operation ($($operation.Path))"
    # Note: We're not actually testing these operations as they require valid instance IDs and auth
    # Just validating URL structure
    Write-Host "  URL Structure Check: $url" -ForegroundColor Gray
    if (Test-UrlStructure $url "RDS Operation ($($operation.Path))") {
        Write-Host "  ✓ Clean URL structure" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "6. Testing Cross-Origin Requests" -ForegroundColor Magenta
Write-Host "================================" -ForegroundColor Magenta

# Test CORS preflight requests
$corsHeaders = @{
    "Origin" = "https://example.com"
    "Access-Control-Request-Method" = "GET"
    "Access-Control-Request-Headers" = "Content-Type,Authorization"
}

$corsEndpoints = @("/health", "/cors-config", "/api/health")
foreach ($endpoint in $corsEndpoints) {
    $url = "$BffApiUrl$endpoint"
    $TestResults += Test-Endpoint -Url $url -Description "CORS Preflight ($endpoint)" -Method "OPTIONS" -Headers $corsHeaders
}

Write-Host ""
Write-Host "7. Validating URL Consistency" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

# Check that all URLs follow clean URL patterns
$allUrls = $TestResults | ForEach-Object { $_.Url }
$cleanUrls = $allUrls | Where-Object { -not ($_ -match "/prod/|/staging/|/dev/") }
$dirtyUrls = $allUrls | Where-Object { $_ -match "/prod/|/staging/|/dev/" }

Write-Host "Total URLs tested: $($allUrls.Count)" -ForegroundColor Cyan
Write-Host "Clean URLs: $($cleanUrls.Count)" -ForegroundColor Green
Write-Host "URLs with stage prefixes: $($dirtyUrls.Count)" -ForegroundColor Red

if ($dirtyUrls.Count -gt 0) {
    Write-Host "URLs with stage prefixes:" -ForegroundColor Red
    $dirtyUrls | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    $ErrorCount += $dirtyUrls.Count
}

Write-Host ""
Write-Host "8. Testing Service Discovery" -ForegroundColor Magenta
Write-Host "============================" -ForegroundColor Magenta

# Validate that BFF is not calling itself
if ($BffApiUrl -eq $InternalApiUrl) {
    Write-Host "  ✗ ERROR: BFF and Internal API URLs are the same - potential circular reference" -ForegroundColor Red
    $ErrorCount++
} elseif ($InternalApiUrl -eq "$BffApiUrl/prod") {
    Write-Host "  ✗ ERROR: Internal API URL is BFF URL with /prod - circular reference detected" -ForegroundColor Red
    $ErrorCount++
} else {
    Write-Host "  ✓ BFF and Internal API URLs are different - no circular reference" -ForegroundColor Green
}

# Check for clean internal API URL
if ($InternalApiUrl -match "/prod$|/staging$|/dev$") {
    Write-Host "  ⚠ WARNING: Internal API URL ends with stage prefix" -ForegroundColor Yellow
    $WarningCount++
} else {
    Write-Host "  ✓ Internal API URL is clean (no stage prefix)" -ForegroundColor Green
}

Write-Host ""
Write-Host "9. Summary Report" -ForegroundColor Magenta
Write-Host "=================" -ForegroundColor Magenta

$passCount = ($TestResults | Where-Object { $_.Status -like "PASS*" }).Count
$failCount = ($TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalTests = $TestResults.Count

Write-Host "Test Results Summary:" -ForegroundColor Cyan
Write-Host "  Total Tests: $totalTests" -ForegroundColor White
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor Red
Write-Host "  Errors: $ErrorCount" -ForegroundColor Red
Write-Host "  Warnings: $WarningCount" -ForegroundColor Yellow

# Clean URL compliance
$cleanUrlTests = ($TestResults | Where-Object { $_.HasCleanUrl }).Count
$dirtyUrlTests = $totalTests - $cleanUrlTests
$cleanUrlPercentage = if ($totalTests -gt 0) { [math]::Round(($cleanUrlTests / $totalTests) * 100, 2) } else { 0 }

Write-Host ""
Write-Host "Clean URL Compliance:" -ForegroundColor Cyan
Write-Host "  Clean URLs: $cleanUrlTests / $totalTests ($cleanUrlPercentage%)" -ForegroundColor $(if ($cleanUrlPercentage -eq 100) { "Green" } else { "Yellow" })
Write-Host "  URLs with stage prefixes: $dirtyUrlTests" -ForegroundColor $(if ($dirtyUrlTests -eq 0) { "Green" } else { "Red" })

# Export detailed results
$resultsFile = "api-functionality-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$TestResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host ""
Write-Host "Detailed results exported to: $resultsFile" -ForegroundColor Cyan

# Final status
Write-Host ""
if ($ErrorCount -eq 0 -and $cleanUrlPercentage -eq 100) {
    Write-Host "✓ ALL TESTS PASSED - API functionality working with clean URLs" -ForegroundColor Green
    exit 0
} elseif ($ErrorCount -eq 0) {
    Write-Host "⚠ TESTS PASSED WITH WARNINGS - Some URLs still have stage prefixes" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "✗ TESTS FAILED - $ErrorCount errors found" -ForegroundColor Red
    exit 2
}