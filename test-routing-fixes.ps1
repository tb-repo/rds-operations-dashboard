# Test Routing Fixes
# Tests the deployed application to see which endpoints are working

$BFF_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod"
$FRONTEND_URL = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing RDS Dashboard Routing Fixes" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Note: These tests will fail with 401 Unauthorized without a valid token
# But we can see if we get 404 (not found) vs 401 (found but unauthorized)

Write-Host "Testing BFF Endpoints (without auth - expect 401 if working, 404 if broken):`n" -ForegroundColor Yellow

$endpoints = @(
    @{ Name = "Health (no auth)"; Path = "/health"; ExpectNoAuth = $true },
    @{ Name = "API Health"; Path = "/api/health"; ExpectNoAuth = $false },
    @{ Name = "Users"; Path = "/api/users"; ExpectNoAuth = $false },
    @{ Name = "Approvals"; Path = "/api/approvals"; ExpectNoAuth = $false },
    @{ Name = "Instances"; Path = "/api/instances"; ExpectNoAuth = $false },
    @{ Name = "Operations"; Path = "/api/operations"; ExpectNoAuth = $false }
)

foreach ($endpoint in $endpoints) {
    $url = "$BFF_URL$($endpoint.Path)"
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop
        if ($endpoint.ExpectNoAuth) {
            Write-Host "✅ $($endpoint.Name): $($response.StatusCode) - Working!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  $($endpoint.Name): $($response.StatusCode) - Unexpected (should need auth)" -ForegroundColor Yellow
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            Write-Host "✅ $($endpoint.Name): 401 Unauthorized - Route exists!" -ForegroundColor Green
        } elseif ($statusCode -eq 404) {
            Write-Host "❌ $($endpoint.Name): 404 Not Found - Route missing!" -ForegroundColor Red
        } elseif ($statusCode -eq 403) {
            Write-Host "⚠️  $($endpoint.Name): 403 Forbidden - Route exists but access denied" -ForegroundColor Yellow
        } else {
            Write-Host "⚠️  $($endpoint.Name): $statusCode - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Frontend Status" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri $FRONTEND_URL -Method Get -ErrorAction Stop
    Write-Host "✅ Frontend: $($response.StatusCode) - Accessible" -ForegroundColor Green
} catch {
    Write-Host "❌ Frontend: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Frontend Changes: ✅ Deployed" -ForegroundColor Green
Write-Host "BFF Changes: ⚠️  Pending (needs Docker + deployment)" -ForegroundColor Yellow
Write-Host "`nTo complete the fix:" -ForegroundColor White
Write-Host "1. Start Docker Desktop" -ForegroundColor White
Write-Host "2. Run: cd infrastructure; npx cdk deploy RDSDashboard-BFF --require-approval never" -ForegroundColor White
Write-Host "`nTest the application: $FRONTEND_URL`n" -ForegroundColor Cyan
