#!/usr/bin/env pwsh

Write-Host "Verifying DNS Fix..." -ForegroundColor Cyan

# Read current configuration
$envFile = "frontend/.env"
$content = Get-Content $envFile -Raw
$bffUrl = ($content | Select-String "VITE_BFF_API_URL=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })

Write-Host "`nCurrent BFF URL: $bffUrl" -ForegroundColor Yellow

# Test the endpoint
$testUrl = "$bffUrl/prod/api/health"
Write-Host "Testing: $testUrl" -ForegroundColor White

try {
    $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "SUCCESS: API Gateway is accessible (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 403) {
            Write-Host "SUCCESS: API Gateway exists and requires authentication (Status: 403)" -ForegroundColor Green
            Write-Host "This is expected behavior - the BFF requires authentication" -ForegroundColor Yellow
        } elseif ($statusCode -eq 401) {
            Write-Host "SUCCESS: API Gateway exists and requires authentication (Status: 401)" -ForegroundColor Green
            Write-Host "This is expected behavior - the API requires authentication" -ForegroundColor Yellow
        } else {
            Write-Host "WARNING: Unexpected status code: $statusCode" -ForegroundColor Yellow
        }
    } else {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -match "ERR_NAME_NOT_RESOLVED") {
            Write-Host "DNS resolution still failing - the endpoint may not exist" -ForegroundColor Red
        }
    }
}

Write-Host "`nDNS Fix Verification Complete!" -ForegroundColor Green
Write-Host "If you see 'SUCCESS' above, the DNS errors should be resolved." -ForegroundColor Cyan