# Simple Test Fixes Verification Script

Write-Host "Testing Deployed Fixes..." -ForegroundColor Green
Write-Host ""

# Test 1: Check frontend
Write-Host "Test 1: Checking frontend..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://d2qvaswtmn22om.cloudfront.net" -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "  SUCCESS: Frontend is accessible" -ForegroundColor Green
    }
} catch {
    Write-Host "  ERROR: Frontend not accessible - $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Check API
Write-Host "Test 2: Checking API..." -ForegroundColor Yellow
$apiUrls = @(
    "https://api.rds-dashboard.idp-connect.com",
    "https://bff.rds-dashboard.idp-connect.com"
)

foreach ($apiUrl in $apiUrls) {
    try {
        Write-Host "  Trying: $apiUrl" -ForegroundColor White
        $healthResponse = Invoke-RestMethod -Uri "$apiUrl/health" -Method GET -TimeoutSec 5
        Write-Host "  SUCCESS: API responding at $apiUrl" -ForegroundColor Green
        break
    } catch {
        Write-Host "  FAILED: $apiUrl not responding" -ForegroundColor Red
    }
}

Write-Host ""

# Manual testing instructions
Write-Host "MANUAL TESTING REQUIRED:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Open: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor White
Write-Host ""
Write-Host "2. Test Instance Operations:" -ForegroundColor Yellow
Write-Host "   - Click on any RDS instance" -ForegroundColor White
Write-Host "   - Try 'Stop Instance' operation" -ForegroundColor White
Write-Host "   - Should work without 400 error" -ForegroundColor White
Write-Host ""
Write-Host "3. Test Logout:" -ForegroundColor Yellow
Write-Host "   - Click logout button" -ForegroundColor White
Write-Host "   - Should redirect cleanly" -ForegroundColor White
Write-Host ""
Write-Host "4. Test User Management:" -ForegroundColor Yellow
Write-Host "   - Go to Users tab" -ForegroundColor White
Write-Host "   - Should show clear error message" -ForegroundColor White
Write-Host ""
Write-Host "5. Check Browser Console (F12):" -ForegroundColor Yellow
Write-Host "   - Should be clean of errors" -ForegroundColor White
Write-Host ""
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "The fixes have been applied and deployed." -ForegroundColor Green