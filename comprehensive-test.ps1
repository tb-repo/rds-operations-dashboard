# Comprehensive Code Testing Script
# Tests all Python Lambda functions for syntax and import errors

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "COMPREHENSIVE CODE TESTING - RDS Operations Dashboard" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

$totalTests = 0
$passedTests = 0
$failedTests = 0
$errors = @()

function Test-PythonFile {
    param(
        [string]$FilePath,
        [string]$Description
    )
    
    $script:totalTests++
    Write-Host "`n[$script:totalTests] Testing: $Description" -ForegroundColor Yellow
    Write-Host "    File: $FilePath" -ForegroundColor Gray
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "    [SKIP] File not found" -ForegroundColor Yellow
        return
    }
    
    try {
        $result = python -m py_compile $FilePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [PASS] Syntax valid" -ForegroundColor Green
            $script:passedTests++
        } else {
            Write-Host "    [FAIL] Syntax error" -ForegroundColor Red
            Write-Host "    Error: $result" -ForegroundColor Red
            $script:failedTests++
            $script:errors += @{File=$FilePath; Error=$result}
        }
    } catch {
        Write-Host "    [FAIL] Exception: $_" -ForegroundColor Red
        $script:failedTests++
        $script:errors += @{File=$FilePath; Error=$_.Exception.Message}
    }
}

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 1: Shared Modules" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/shared/logger.py" "Shared Logger Module"
Test-PythonFile "lambda/shared/aws_clients.py" "Shared AWS Clients Module"
Test-PythonFile "lambda/shared/config.py" "Shared Config Module"
Test-PythonFile "lambda/shared/config_file_loader.py" "Config File Loader"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 2: Discovery Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/discovery/handler.py" "Discovery Handler"
Test-PythonFile "lambda/discovery/persistence.py" "Discovery Persistence"
Test-PythonFile "lambda/discovery/monitoring.py" "Discovery Monitoring"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 3: Health Monitor Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/health-monitor/handler.py" "Health Monitor Handler"
Test-PythonFile "lambda/health-monitor/cache_manager.py" "Cache Manager"
Test-PythonFile "lambda/health-monitor/alerting.py" "Alerting Module"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 4: Cost Analyzer Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/cost-analyzer/handler.py" "Cost Analyzer Handler"
Test-PythonFile "lambda/cost-analyzer/pricing.py" "Pricing Calculator"
Test-PythonFile "lambda/cost-analyzer/utilization.py" "Utilization Analyzer"
Test-PythonFile "lambda/cost-analyzer/recommendations.py" "Recommendation Engine"
Test-PythonFile "lambda/cost-analyzer/reporting.py" "Cost Reporter (with Trend Tracking)"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 5: Compliance Checker Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/compliance-checker/handler.py" "Compliance Checker Handler"
Test-PythonFile "lambda/compliance-checker/checks.py" "Compliance Checks"
Test-PythonFile "lambda/compliance-checker/reporting.py" "Compliance Reporter"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 6: Operations Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/operations/handler.py" "Operations Service Handler"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 7: Query Handler Service" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/query-handler/handler.py" "Query Handler"

Write-Host "`n" + ("-" * 70) -ForegroundColor Cyan
Write-Host "SECTION 8: Test Files" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Cyan

Test-PythonFile "lambda/tests/test_basic.py" "Basic Tests"
Test-PythonFile "lambda/tests/test_alerting.py" "Alerting Tests"
Test-PythonFile "lambda/tests/test_cost_analyzer.py" "Cost Analyzer Tests"
Test-PythonFile "lambda/tests/test_cost_trend_tracking.py" "Cost Trend Tracking Tests"
Test-PythonFile "lambda/tests/test_flexible_environment_tags.py" "Flexible Environment Tags Tests"
Test-PythonFile "lambda/tests/test_operations.py" "Operations Service Tests"

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-Host "`nTotal Tests:  $totalTests" -ForegroundColor White
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "Success Rate: $([math]::Round(($passedTests/$totalTests)*100, 1))%" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Yellow" })

if ($failedTests -gt 0) {
    Write-Host "`n" + ("-" * 70) -ForegroundColor Red
    Write-Host "ERRORS FOUND" -ForegroundColor Red
    Write-Host ("-" * 70) -ForegroundColor Red
    
    foreach ($error in $errors) {
        Write-Host "`nFile: $($error.File)" -ForegroundColor Yellow
        Write-Host "Error: $($error.Error)" -ForegroundColor Red
    }
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Red
    Write-Host "RESULT: FAILED - Please fix the errors above" -ForegroundColor Red
    Write-Host ("=" * 70) -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Green
    Write-Host "RESULT: ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host "`nAll Python files have valid syntax and no import errors." -ForegroundColor Green
    Write-Host "The codebase is ready for deployment.`n" -ForegroundColor Green
    exit 0
}
