# Test BFF Endpoints After Fix
Write-Host "Testing BFF Endpoints..." -ForegroundColor Cyan

# Get the BFF URL
$BFF_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"

# Test health endpoint (no auth required)
Write-Host "Testing /health endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BFF_URL/health" -Method Get
    Write-Host "Health endpoint working" -ForegroundColor Green
    $response | ConvertTo-Json
} catch {
    Write-Host "Health endpoint failed: $_" -ForegroundColor Red
}

# Check recent BFF logs
Write-Host "Checking recent BFF logs..." -ForegroundColor Yellow
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds()
aws logs filter-log-events --log-group-name /aws/lambda/rds-dashboard-bff --start-time $startTime --max-items 10 --output json | ConvertFrom-Json | Select-Object -ExpandProperty events | ForEach-Object {
    Write-Host $_.message
}

Write-Host "Test complete" -ForegroundColor Cyan
