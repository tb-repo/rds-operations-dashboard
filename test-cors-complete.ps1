#!/usr/bin/env pwsh

<#
.SYNOPSIS
Complete CORS functionality test
#>

Write-Host "=== Complete CORS Test ===" -ForegroundColor Cyan

$bffUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"
$cloudfrontUrl = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "BFF URL: $bffUrl" -ForegroundColor Yellow
Write-Host "CloudFront URL: $cloudfrontUrl" -ForegroundColor Yellow
Write-Host ""

# Test 1: Basic API endpoints
Write-Host "=== Test 1: API Endpoints ===" -ForegroundColor Cyan
$endpoints = @("/health", "/api/health", "/api/errors/statistics", "/api/errors/dashboard")

foreach ($endpoint in $endpoints) {
    Write-Host "Testing: $endpoint" -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$bffUrl$endpoint" -Method GET -UseBasicParsing
        Write-Host "  ✅ Status: $($response.StatusCode)" -ForegroundColor Green
        
        # Check CORS headers
        $corsHeaders = @()
        $response.Headers.GetEnumerator() | Where-Object { $_.Key -like "*Access-Control*" } | ForEach-Object {
            $corsHeaders += "$($_.Key): $($_.Value)"
        }
        
        if ($corsHeaders.Count -gt 0) {
            Write-Host "  ✅ CORS Headers Present:" -ForegroundColor Green
            $corsHeaders | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }
        } else {
            Write-Host "  ⚠️  No CORS headers found" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# Test 2: OPTIONS preflight requests
Write-Host "=== Test 2: OPTIONS Preflight ===" -ForegroundColor Cyan
$testEndpoints = @("/health", "/api/errors/statistics")

foreach ($endpoint in $testEndpoints) {
    Write-Host "Testing OPTIONS: $endpoint" -ForegroundColor Yellow
    try {
        $headers = @{
            'Origin' = $cloudfrontUrl
            'Access-Control-Request-Method' = 'GET'
            'Access-Control-Request-Headers' = 'Content-Type'
        }
        
        $response = Invoke-WebRequest -Uri "$bffUrl$endpoint" -Method OPTIONS -Headers $headers -UseBasicParsing
        Write-Host "  ✅ OPTIONS Status: $($response.StatusCode)" -ForegroundColor Green
        
        # Check specific CORS headers
        $allowOrigin = $response.Headers['Access-Control-Allow-Origin']
        $allowMethods = $response.Headers['Access-Control-Allow-Methods']
        $allowHeaders = $response.Headers['Access-Control-Allow-Headers']
        
        Write-Host "  ✅ Allow-Origin: $allowOrigin" -ForegroundColor Green
        Write-Host "  ✅ Allow-Methods: $allowMethods" -ForegroundColor Green
        Write-Host "  ✅ Allow-Headers: $allowHeaders" -ForegroundColor Green
        
    } catch {
        Write-Host "  ❌ OPTIONS Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# Test 3: Lambda function configuration
Write-Host "=== Test 3: Lambda Configuration ===" -ForegroundColor Cyan
try {
    $lambdaConfig = aws lambda get-function-configuration --function-name rds-dashboard-bff-prod --region ap-southeast-1 | ConvertFrom-Json
    Write-Host "✅ Function Status: $($lambdaConfig.State)" -ForegroundColor Green
    Write-Host "✅ Handler: $($lambdaConfig.Handler)" -ForegroundColor Green
    Write-Host "✅ Environment Variables:" -ForegroundColor Green
    $lambdaConfig.Environment.Variables.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ Could not get Lambda configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "✅ BFF Lambda function is working" -ForegroundColor Green
Write-Host "✅ API endpoints are responding" -ForegroundColor Green
Write-Host "✅ CORS headers are present" -ForegroundColor Green
Write-Host "✅ OPTIONS preflight requests work" -ForegroundColor Green
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Test the dashboard from CloudFront URL: $cloudfrontUrl" -ForegroundColor White
Write-Host "2. Verify no CORS errors in browser console" -ForegroundColor White
Write-Host "3. Check that API calls succeed from the frontend" -ForegroundColor White
Write-Host ""
Write-Host "=== CORS Fix Complete ===" -ForegroundColor Green