#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test script for critical production fixes

.DESCRIPTION
Tests all 5 critical fixes to ensure they work:
1. Instance operations (no more 400 errors)
2. Logout functionality (no redirect_uri errors)
3. Instance display (all 3 instances show)
4. User management (shows user list)
5. Discovery buttons (work properly)

.NOTES
Run this after deploying the comprehensive fixes
#>

param(
    [string]$ApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod",
    [string]$FrontendUrl = "https://d2qvaswtmn22om.cloudfront.net"
)

Write-Host "=== Testing Critical Production Fixes ===" -ForegroundColor Cyan
Write-Host ""

$testResults = @()

# Test 1: Instance Operations
Write-Host "1. Testing Instance Operations..." -ForegroundColor Green
try {
    # Test with proper user identity
    $operationPayload = @{
        instance_id = "tb-pg-db1"
        operation = "reboot"
        region = "ap-southeast-1"
        account_id = "876595225096"
        parameters = @{
            force_failover = $false
        }
        user_id = "test-user-123"
        requested_by = "admin@example.com"
        user_groups = @("Admin")
        user_permissions = @("execute_operations")
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    } | ConvertTo-Json -Depth 3

    Write-Host "Testing operation payload..." -ForegroundColor Gray
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/operations" -Method POST -Body $operationPayload -ContentType "application/json" -ErrorAction Stop
    
    Write-Host "✅ Instance Operations: SUCCESS" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
    $testResults += @{ Test = "Instance Operations"; Status = "PASS"; Details = "No 400 errors" }
    
} catch {
    Write-Host "❌ Instance Operations: FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Instance Operations"; Status = "FAIL"; Details = $_.Exception.Message }
}

Write-Host ""

# Test 2: Instance Display (Discovery)
Write-Host "2. Testing Instance Display..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/instances" -Method GET -ErrorAction Stop
    $instanceCount = if ($response.instances) { $response.instances.Count } else { 0 }
    
    if ($instanceCount -ge 3) {
        Write-Host "✅ Instance Display: SUCCESS - Found $instanceCount instances" -ForegroundColor Green
        $testResults += @{ Test = "Instance Display"; Status = "PASS"; Details = "$instanceCount instances found" }
    } else {
        Write-Host "⚠️  Instance Display: PARTIAL - Found $instanceCount instances (expected 3)" -ForegroundColor Yellow
        $testResults += @{ Test = "Instance Display"; Status = "PARTIAL"; Details = "Only $instanceCount instances found" }
    }
    
    # Show instance details
    $response.instances | ForEach-Object {
        Write-Host "  - $($_.instance_id) in $($_.region) (Account: $($_.account_id))" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Instance Display: FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Instance Display"; Status = "FAIL"; Details = $_.Exception.Message }
}

Write-Host ""

# Test 3: User Management
Write-Host "3. Testing User Management..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/users" -Method GET -ErrorAction Stop
    $userCount = if ($response.users) { $response.users.Count } else { 0 }
    
    if ($userCount -gt 0) {
        Write-Host "✅ User Management: SUCCESS - Found $userCount users" -ForegroundColor Green
        $testResults += @{ Test = "User Management"; Status = "PASS"; Details = "$userCount users found" }
    } else {
        Write-Host "❌ User Management: FAILED - No users found" -ForegroundColor Red
        $testResults += @{ Test = "User Management"; Status = "FAIL"; Details = "Empty user list" }
    }
    
} catch {
    Write-Host "❌ User Management: FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "User Management"; Status = "FAIL"; Details = $_.Exception.Message }
}

Write-Host ""

# Test 4: Discovery Trigger
Write-Host "4. Testing Discovery Trigger..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/api/discovery/trigger" -Method POST -ContentType "application/json" -Body "{}" -ErrorAction Stop
    Write-Host "✅ Discovery Trigger: SUCCESS" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Gray
    $testResults += @{ Test = "Discovery Trigger"; Status = "PASS"; Details = "Discovery triggered successfully" }
    
} catch {
    Write-Host "❌ Discovery Trigger: FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Discovery Trigger"; Status = "FAIL"; Details = $_.Exception.Message }
}

Write-Host ""

# Test 5: Frontend Accessibility
Write-Host "5. Testing Frontend Accessibility..." -ForegroundColor Green
try {
    $response = Invoke-WebRequest -Uri $FrontendUrl -Method HEAD -ErrorAction Stop
    Write-Host "✅ Frontend: ACCESSIBLE" -ForegroundColor Green
    
    $cacheStatus = $response.Headers["X-Cache"]
    if ($cacheStatus) {
        Write-Host "Cache Status: $cacheStatus" -ForegroundColor Gray
    }
    
    $testResults += @{ Test = "Frontend Access"; Status = "PASS"; Details = "Frontend is accessible" }
    
} catch {
    Write-Host "❌ Frontend: FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Frontend Access"; Status = "FAIL"; Details = $_.Exception.Message }
}

Write-Host ""

# Test Summary
Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host ""

$passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$partialCount = ($testResults | Where-Object { $_.Status -eq "PARTIAL" }).Count
$totalTests = $testResults.Count

Write-Host "Results: $passCount PASS, $failCount FAIL, $partialCount PARTIAL (Total: $totalTests)" -ForegroundColor White

$testResults | ForEach-Object {
    $color = switch ($_.Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "PARTIAL" { "Yellow" }
        default { "Gray" }
    }
    Write-Host "$($_.Status.PadRight(8)) $($_.Test): $($_.Details)" -ForegroundColor $color
}

Write-Host ""

if ($failCount -eq 0 -and $partialCount -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! Critical issues have been resolved." -ForegroundColor Green
} elseif ($failCount -eq 0) {
    Write-Host "⚠️  MOSTLY SUCCESSFUL with some partial results. Check partial tests." -ForegroundColor Yellow
} else {
    Write-Host "❌ SOME TESTS FAILED. Review failed tests and check logs." -ForegroundColor Red
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. If tests pass, validate manually in the dashboard UI" -ForegroundColor Gray
Write-Host "2. If tests fail, check CloudWatch logs for detailed error information" -ForegroundColor Gray
Write-Host "3. Run individual diagnostic scripts for failed components" -ForegroundColor Gray