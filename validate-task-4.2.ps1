# Simple validation for Task 4.2 - Cost Trend Tracking

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Task 4.2 Validation - Cost Trend Tracking" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$passed = 0
$failed = 0

# Test 1: Syntax Check
Write-Host "[1/5] Python Syntax Validation..." -ForegroundColor Yellow
python -m py_compile lambda/cost-analyzer/reporting.py 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  PASS - reporting.py syntax valid" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - reporting.py has syntax errors" -ForegroundColor Red
    $failed++
}

python -m py_compile lambda/cost-analyzer/handler.py 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  PASS - handler.py syntax valid" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - handler.py has syntax errors" -ForegroundColor Red
    $failed++
}

# Test 2: Check Methods Exist
Write-Host "`n[2/5] Checking Required Methods..." -ForegroundColor Yellow
$content = Get-Content lambda/cost-analyzer/reporting.py -Raw
$methods = @("store_cost_snapshot", "calculate_cost_trends", "publish_cost_metrics", "generate_monthly_trend_report")
$methodCount = 0
foreach ($m in $methods) {
    if ($content -match "def $m") {
        $methodCount++
    }
}
if ($methodCount -eq 4) {
    Write-Host "  PASS - All 4 required methods found" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - Only $methodCount/4 methods found" -ForegroundColor Red
    $failed++
}

# Test 3: Check DynamoDB Table
Write-Host "`n[3/5] Checking DynamoDB Table Definition..." -ForegroundColor Yellow
$stack = Get-Content infrastructure/lib/data-stack.ts -Raw
if ($stack -match "costSnapshotsTable" -and $stack -match "cost-snapshots") {
    Write-Host "  PASS - Cost snapshots table defined" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - Cost snapshots table missing" -ForegroundColor Red
    $failed++
}

# Test 4: Check Handler Integration
Write-Host "`n[4/5] Checking Handler Integration..." -ForegroundColor Yellow
$handler = Get-Content lambda/cost-analyzer/handler.py -Raw
if ($handler -match "store_cost_snapshot" -and $handler -match "calculate_cost_trends") {
    Write-Host "  PASS - Handler integrated with trend tracking" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - Handler missing trend tracking calls" -ForegroundColor Red
    $failed++
}

# Test 5: Check CloudWatch Metrics
Write-Host "`n[5/5] Checking CloudWatch Metrics..." -ForegroundColor Yellow
if ($content -match "TotalMonthlyCost" -and $content -match "CostPerAccount") {
    Write-Host "  PASS - CloudWatch metrics configured" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL - CloudWatch metrics missing" -ForegroundColor Red
    $failed++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($failed -eq 0) {
    Write-Host "SUCCESS - Task 4.2 implementation validated!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILED - Some validations failed" -ForegroundColor Red
    exit 1
}
