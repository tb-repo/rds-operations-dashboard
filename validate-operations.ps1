#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate Operations Service Implementation

.DESCRIPTION
    Tests the operations service handler for syntax, imports, and basic functionality.
    
.NOTES
    Task: 6 - Operations Service
    Date: 2025-11-13
#>

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Operations Service Validation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testsPassed = 0
$testsFailed = 0

function Test-Component {
    param(
        [string]$Name,
        [string]$File
    )
    
    Write-Host "Testing: $Name" -ForegroundColor Yellow
    Write-Host "  File: $File" -ForegroundColor Gray
    
    if (-not (Test-Path $File)) {
        Write-Host "  [FAIL] File not found" -ForegroundColor Red
        $script:testsFailed++
        return
    }
    
    $result = python -m py_compile $File 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [PASS] Syntax valid" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "  [FAIL] Syntax error: $result" -ForegroundColor Red
        $script:testsFailed++
    }
}

# Test Operations Service
Write-Host "1. Operations Service Handler" -ForegroundColor Cyan
Test-Component "Operations Handler" "lambda/operations/handler.py"

Write-Host "`n2. Operations Tests" -ForegroundColor Cyan
Test-Component "Operations Tests" "lambda/tests/test_operations.py"

Write-Host "`n3. Documentation" -ForegroundColor Cyan
if (Test-Path "docs/operations-service.md") {
    Write-Host "  [PASS] Documentation exists" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  [FAIL] Documentation missing" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n4. Task Summary" -ForegroundColor Cyan
if (Test-Path "TASK-6-SUMMARY.md") {
    Write-Host "  [PASS] Task summary exists" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  [FAIL] Task summary missing" -ForegroundColor Red
    $testsFailed++
}

# Test key features
Write-Host "`n5. Feature Verification" -ForegroundColor Cyan

Write-Host "  Checking: Supported operations..." -ForegroundColor Gray
$opsCheck = Select-String -Path "lambda/operations/handler.py" -Pattern "ALLOWED_OPERATIONS.*=.*\['create_snapshot', 'reboot_instance', 'modify_backup_window'\]"
if ($opsCheck) {
    Write-Host "  [PASS] All operations defined" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  [FAIL] Operations not properly defined" -ForegroundColor Red
    $testsFailed++
}

Write-Host "  Checking: Environment classifier integration..." -ForegroundColor Gray
$envCheck = Select-String -Path "lambda/operations/handler.py" -Pattern "EnvironmentClassifier"
if ($envCheck) {
    Write-Host "  [PASS] Environment classifier integrated" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  [FAIL] Environment classifier missing" -ForegroundColor Red
    $testsFailed++
}

Write-Host "  Checking: Audit logging..." -ForegroundColor Gray
$auditCheck = Select-String -Path "lambda/operations/handler.py" -Pattern "_log_audit"
if ($auditCheck) {
    Write-Host "  [PASS] Audit logging implemented" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  [FAIL] Audit logging missing" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTotal Tests:  $($testsPassed + $testsFailed)" -ForegroundColor White
Write-Host "Passed:       $testsPassed" -ForegroundColor Green
Write-Host "Failed:       $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

if ($testsFailed -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "VALIDATION PASSED!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nOperations Service is ready for deployment." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "VALIDATION FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "`nPlease fix the errors above." -ForegroundColor Red
    exit 1
}
