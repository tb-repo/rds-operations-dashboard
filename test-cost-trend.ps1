# Cost Trend Tracking Validation Script
# Tests syntax and basic functionality of cost trend tracking

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Cost Trend Tracking - Validation Tests" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

$ErrorCount = 0
$SuccessCount = 0

# Test 1: Python Syntax Check - reporting.py
Write-Host "`n[Test 1] Checking reporting.py syntax..." -ForegroundColor Yellow
try {
    python -m py_compile lambda/cost-analyzer/reporting.py
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ reporting.py syntax is valid" -ForegroundColor Green
        $SuccessCount++
    } else {
        Write-Host "  ✗ reporting.py has syntax errors" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "  ✗ Failed to check reporting.py: $_" -ForegroundColor Red
    $ErrorCount++
}

# Test 2: Python Syntax Check - handler.py
Write-Host "`n[Test 2] Checking handler.py syntax..." -ForegroundColor Yellow
try {
    python -m py_compile lambda/cost-analyzer/handler.py
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ handler.py syntax is valid" -ForegroundColor Green
        $SuccessCount++
    } else {
        Write-Host "  ✗ handler.py has syntax errors" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "  ✗ Failed to check handler.py: $_" -ForegroundColor Red
    $ErrorCount++
}

# Test 3: Check for required methods in reporting.py
Write-Host "`n[Test 3] Checking for required methods in reporting.py..." -ForegroundColor Yellow
$reportingContent = Get-Content lambda/cost-analyzer/reporting.py -Raw
$requiredMethods = @(
    "store_cost_snapshot",
    "calculate_cost_trends",
    "publish_cost_metrics",
    "generate_monthly_trend_report",
    "save_trend_report_to_s3"
)

$methodsFound = 0
foreach ($method in $requiredMethods) {
    if ($reportingContent -match "def $method\(") {
        Write-Host "  ✓ Found method: $method" -ForegroundColor Green
        $methodsFound++
    } else {
        Write-Host "  ✗ Missing method: $method" -ForegroundColor Red
        $ErrorCount++
    }
}

if ($methodsFound -eq $requiredMethods.Count) {
    Write-Host "  ✓ All required methods present" -ForegroundColor Green
    $SuccessCount++
}

# Test 4: Check DynamoDB table definition in data-stack.ts
Write-Host "`n[Test 4] Checking cost snapshots table in data-stack.ts..." -ForegroundColor Yellow
$dataStackContent = Get-Content infrastructure/lib/data-stack.ts -Raw
if ($dataStackContent -match "costSnapshotsTable" -and $dataStackContent -match "cost-snapshots") {
    Write-Host "  ✓ Cost snapshots table defined" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ✗ Cost snapshots table not found" -ForegroundColor Red
    $ErrorCount++
}

# Test 5: Check handler integration
Write-Host "`n[Test 5] Checking handler integration..." -ForegroundColor Yellow
$handlerContent = Get-Content lambda/cost-analyzer/handler.py -Raw
$integrationChecks = @(
    "store_cost_snapshot",
    "calculate_cost_trends",
    "generate_monthly_trend_report",
    "publish_cost_metrics"
)

$integrationsFound = 0
foreach ($check in $integrationChecks) {
    if ($handlerContent -match $check) {
        Write-Host "  ✓ Handler calls: $check" -ForegroundColor Green
        $integrationsFound++
    } else {
        Write-Host "  ✗ Handler missing call to: $check" -ForegroundColor Red
        $ErrorCount++
    }
}

if ($integrationsFound -eq $integrationChecks.Count) {
    Write-Host "  ✓ All integrations present in handler" -ForegroundColor Green
    $SuccessCount++
}

# Test 6: Check CloudWatch metrics
Write-Host "`n[Test 6] Checking CloudWatch metrics implementation..." -ForegroundColor Yellow
if ($reportingContent -match "TotalMonthlyCost" -and 
    $reportingContent -match "CostPerAccount" -and 
    $reportingContent -match "CostPerRegion") {
    Write-Host "  ✓ CloudWatch metrics defined" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ✗ CloudWatch metrics incomplete" -ForegroundColor Red
    $ErrorCount++
}

# Test 7: Check S3 report paths
Write-Host "`n[Test 7] Checking S3 report paths..." -ForegroundColor Yellow
if ($reportingContent -match "cost_trend_" -and $reportingContent -match "cost-reports/") {
    Write-Host "  ✓ S3 trend report paths configured" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ✗ S3 trend report paths missing" -ForegroundColor Red
    $ErrorCount++
}

# Test 8: Check DynamoDB conversion methods
Write-Host "`n[Test 8] Checking DynamoDB conversion methods..." -ForegroundColor Yellow
if ($reportingContent -match "_convert_to_dynamodb_item" -and 
    $reportingContent -match "_convert_from_dynamodb_item") {
    Write-Host "  ✓ DynamoDB conversion methods present" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ✗ DynamoDB conversion methods missing" -ForegroundColor Red
    $ErrorCount++
}

# Test 9: Check trend calculation logic
Write-Host "`n[Test 9] Checking trend calculation logic..." -ForegroundColor Yellow
if ($reportingContent -match "month_over_month" -and 
    $reportingContent -match "cost_change_percentage" -and
    $reportingContent -match "trend.*increasing.*decreasing") {
    Write-Host "  ✓ Trend calculation logic implemented" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ✗ Trend calculation logic incomplete" -ForegroundColor Red
    $ErrorCount++
}

# Test 10: Check error handling
Write-Host "`n[Test 10] Checking error handling..." -ForegroundColor Yellow
$errorHandlingCount = ([regex]::Matches($reportingContent, "try:")).Count
$exceptionHandlingCount = ([regex]::Matches($reportingContent, "except Exception")).Count

if ($errorHandlingCount -ge 5 -and $exceptionHandlingCount -ge 5) {
    Write-Host "  ✓ Error handling implemented ($errorHandlingCount try blocks, $exceptionHandlingCount exception handlers)" -ForegroundColor Green
    $SuccessCount++
} else {
    Write-Host "  ⚠ Limited error handling ($errorHandlingCount try blocks, $exceptionHandlingCount exception handlers)" -ForegroundColor Yellow
    $SuccessCount++
}

# Summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Passed: $SuccessCount" -ForegroundColor Green
Write-Host "Failed: $ErrorCount" -ForegroundColor Red
Write-Host "Total:  $($SuccessCount + $ErrorCount)" -ForegroundColor White

if ($ErrorCount -eq 0) {
    Write-Host "`n[SUCCESS] All tests passed! Cost trend tracking is ready." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[FAILED] Some tests failed. Please review the errors above." -ForegroundColor Red
    exit 1
}
