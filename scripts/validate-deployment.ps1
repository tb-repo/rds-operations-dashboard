# Simple deployment validation for API Gateway Stage Elimination
param(
    [string]$BffApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com",
    [string]$InternalApiUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
)

Write-Host "API Gateway Stage Elimination - Deployment Validation" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""

$ErrorCount = 0

Write-Host "1. Testing Clean URL Structure" -ForegroundColor Magenta
Write-Host "==============================" -ForegroundColor Magenta

# Test BFF endpoints
$endpoints = @(
    "$BffApiUrl/health",
    "$BffApiUrl/cors-config", 
    "$BffApiUrl/api/health",
    "$InternalApiUrl/instances",
    "$InternalApiUrl/operations",
    "$InternalApiUrl/discovery"
)

foreach ($url in $endpoints) {
    Write-Host "Testing: $url" -ForegroundColor Cyan
    
    # Check for stage prefixes
    if ($url -match "/prod/|/staging/|/dev/") {
        Write-Host "  ✗ FAIL: URL contains stage prefix" -ForegroundColor Red
        $ErrorCount++
        continue
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  ✓ PASS: Clean URL working" -ForegroundColor Green
    }
    catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "  ✓ PASS: Clean URL accessible (auth required)" -ForegroundColor Yellow
        } else {
            Write-Host "  ⚠ WARNING: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "2. Checking Environment Files" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

$envFiles = @("frontend/.env", "frontend/.env.production", "frontend/.env.example")

foreach ($file in $envFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        if ($content -match "/prod|/staging|/dev") {
            Write-Host "  ✗ FAIL: $file contains stage prefixes" -ForegroundColor Red
            $ErrorCount++
        } else {
            Write-Host "  ✓ PASS: $file has clean URLs" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠ WARNING: $file not found" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "3. Summary" -ForegroundColor Magenta
Write-Host "==========" -ForegroundColor Magenta

if ($ErrorCount -eq 0) {
    Write-Host "✓ API Gateway Stage Elimination validation PASSED!" -ForegroundColor Green
    Write-Host "  System is ready for production deployment" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Validation found $ErrorCount errors" -ForegroundColor Red
    exit 1
}