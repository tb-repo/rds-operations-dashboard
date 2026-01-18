#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test CORS configuration for the operations endpoint

.DESCRIPTION
Tests that the CORS fix for the operations endpoint is working correctly
by making a preflight OPTIONS request and checking the response headers.
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [string]$Stage = "prod"
)

$ErrorActionPreference = "Stop"

Write-Host "🧪 Testing CORS Configuration for Operations Endpoint" -ForegroundColor Cyan

$testUrl = "https://$ApiGatewayId.execute-api.$Region.amazonaws.com/$Stage/api/operations"
$origin = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "Test URL: $testUrl" -ForegroundColor Gray
Write-Host "Origin: $origin" -ForegroundColor Gray

try {
    Write-Host "`n🔍 Testing CORS preflight request..." -ForegroundColor Green
    
    # Test OPTIONS request for CORS preflight
    $response = curl -s -X OPTIONS $testUrl `
        -H "Origin: $origin" `
        -H "Access-Control-Request-Method: POST" `
        -H "Access-Control-Request-Headers: Content-Type,Authorization" `
        -i
    
    Write-Host "`n📋 Response Headers:" -ForegroundColor Yellow
    Write-Host $response -ForegroundColor Gray
    
    # Check for required CORS headers
    $hasAllowOrigin = $response -match "Access-Control-Allow-Origin"
    $hasAllowMethods = $response -match "Access-Control-Allow-Methods"
    $hasAllowHeaders = $response -match "Access-Control-Allow-Headers"
    
    Write-Host "`n✅ CORS Header Check:" -ForegroundColor Green
    Write-Host "  Access-Control-Allow-Origin: $(if ($hasAllowOrigin) { '✅ Present' } else { '❌ Missing' })" -ForegroundColor $(if ($hasAllowOrigin) { 'Green' } else { 'Red' })
    Write-Host "  Access-Control-Allow-Methods: $(if ($hasAllowMethods) { '✅ Present' } else { '❌ Missing' })" -ForegroundColor $(if ($hasAllowMethods) { 'Green' } else { 'Red' })
    Write-Host "  Access-Control-Allow-Headers: $(if ($hasAllowHeaders) { '✅ Present' } else { '❌ Missing' })" -ForegroundColor $(if ($hasAllowHeaders) { 'Green' } else { 'Red' })
    
    if ($hasAllowOrigin -and $hasAllowMethods -and $hasAllowHeaders) {
        Write-Host "`n🎉 CORS Configuration Test: PASSED" -ForegroundColor Green
        Write-Host "✅ Operations endpoint should work from CloudFront" -ForegroundColor Green
    } else {
        Write-Host "`n❌ CORS Configuration Test: FAILED" -ForegroundColor Red
        Write-Host "❌ Missing required CORS headers" -ForegroundColor Red
        Write-Host "💡 Run fix-cors-operations-endpoint.ps1 to fix the configuration" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "`n❌ Error testing CORS configuration: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "💡 This might be normal if the endpoint requires authentication" -ForegroundColor Yellow
}

Write-Host "`n📋 Manual Test Instructions:" -ForegroundColor Cyan
Write-Host "1. Open the dashboard in your browser" -ForegroundColor Gray
Write-Host "2. Open browser developer tools (F12)" -ForegroundColor Gray
Write-Host "3. Go to Network tab" -ForegroundColor Gray
Write-Host "4. Try to perform an instance operation (start/stop/reboot)" -ForegroundColor Gray
Write-Host "5. Check if the request succeeds without CORS errors" -ForegroundColor Gray