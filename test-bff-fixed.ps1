# Test BFF endpoints after fix
Write-Host "Testing BFF endpoints after API key fix..." -ForegroundColor Cyan

$BFF_URL = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"

# Test 1: Health endpoint (no auth)
Write-Host "`n1. Testing health endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BFF_URL/health" -Method GET
    Write-Host "✓ Health endpoint: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response: $($response.Content)"
} catch {
    Write-Host "✗ Health endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Get a token (you'll need to login first)
Write-Host "`n2. To test authenticated endpoints, please:" -ForegroundColor Yellow
Write-Host "   - Open https://d2iqvvvqxqvqxq.cloudfront.net in your browser"
Write-Host "   - Login with your credentials"
Write-Host "   - Open browser DevTools (F12)"
Write-Host "   - Go to Application > Local Storage"
Write-Host "   - Copy the 'idToken' value"
Write-Host "   - Paste it below when prompted"

$token = Read-Host "`nEnter your ID token (or press Enter to skip authenticated tests)"

if ($token) {
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # Test 3: Get approvals
    Write-Host "`n3. Testing GET /api/approvals..." -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$BFF_URL/api/approvals" -Method GET -Headers $headers
        Write-Host "✓ GET approvals: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Response: $($response.Content)"
    } catch {
        Write-Host "✗ GET approvals failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Error details: $responseBody" -ForegroundColor Red
        }
    }

    # Test 4: Get instances
    Write-Host "`n4. Testing GET /api/instances..." -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$BFF_URL/api/instances" -Method GET -Headers $headers
        Write-Host "✓ GET instances: $($response.StatusCode)" -ForegroundColor Green
        $instances = ($response.Content | ConvertFrom-Json).instances
        Write-Host "Found $($instances.Count) instances"
    } catch {
        Write-Host "✗ GET instances failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "`nSkipping authenticated tests." -ForegroundColor Gray
}

Write-Host "`nTest complete!" -ForegroundColor Cyan
