#!/usr/bin/env pwsh
# Verify Frontend Fix

Write-Host "=== Verifying Frontend Fix ===" -ForegroundColor Cyan

# Get API key from .env
$envFile = Get-Content "../frontend/.env" -Raw
if ($envFile -match 'VITE_API_KEY=([^\r\n]+)') {
    $apiKey = $matches[1]
    Write-Host "OK: API Key found in .env" -ForegroundColor Green
} else {
    Write-Host "FAIL: API Key not found in .env" -ForegroundColor Red
    exit 1
}

# Get API URL from .env
if ($envFile -match 'VITE_API_BASE_URL=([^\r\n]+)') {
    $apiUrl = $matches[1].TrimEnd('/')
    Write-Host "OK: API URL found: $apiUrl" -ForegroundColor Green
} else {
    Write-Host "FAIL: API URL not found in .env" -ForegroundColor Red
    exit 1
}

# Test each endpoint
$endpoints = @('/instances', '/health', '/costs', '/compliance')
$allPassed = $true

foreach ($endpoint in $endpoints) {
    Write-Host "`nTesting $endpoint..." -ForegroundColor Yellow
    $headers = @{ 'x-api-key' = $apiKey; 'Content-Type' = 'application/json' }
    
    try {
        $response = Invoke-WebRequest -Uri "$apiUrl$endpoint" -Method GET -Headers $headers -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "  OK: $endpoint works (200)" -ForegroundColor Green
        } else {
            Write-Host "  FAIL: $endpoint returned $($response.StatusCode)" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "  FAIL: $endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "SUCCESS: All endpoints working! Frontend should work now." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. cd frontend" -ForegroundColor Cyan
    Write-Host "2. npm run dev" -ForegroundColor Cyan
    Write-Host "3. Open http://localhost:5173 in browser" -ForegroundColor Cyan
} else {
    Write-Host "FAIL: Some endpoints failed. Check the errors above." -ForegroundColor Red
}
