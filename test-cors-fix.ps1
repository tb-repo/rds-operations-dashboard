#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test CORS configuration fix

.DESCRIPTION
Tests that the BFF Lambda function now accepts requests from the CloudFront origin
#>

param(
    [string]$BffUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com",
    [string]$CloudFrontUrl = "https://d2qvaswtmn22om.cloudfront.net"
)

Write-Host "=== Testing CORS Configuration Fix ===" -ForegroundColor Cyan

# Test 1: Health endpoint without origin (should work)
Write-Host "Test 1: Health endpoint without origin header..." -ForegroundColor Yellow
try {
    $response1 = Invoke-RestMethod -Uri "$BffUrl/health" -Method GET -Headers @{
        "User-Agent" = "CORS-Test/1.0"
    } -ErrorAction Stop
    
    Write-Host "✅ Health endpoint accessible without origin" -ForegroundColor Green
    Write-Host "Response: $($response1.status)" -ForegroundColor Cyan
} catch {
    Write-Host "❌ Health endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Health endpoint with CloudFront origin (should work)
Write-Host "`nTest 2: Health endpoint with CloudFront origin..." -ForegroundColor Yellow
try {
    $response2 = Invoke-RestMethod -Uri "$BffUrl/health" -Method GET -Headers @{
        "Origin" = $CloudFrontUrl
        "User-Agent" = "CORS-Test/1.0"
    } -ErrorAction Stop
    
    Write-Host "✅ Health endpoint accessible with CloudFront origin" -ForegroundColor Green
    Write-Host "Response: $($response2.status)" -ForegroundColor Cyan
} catch {
    Write-Host "❌ Health endpoint with origin failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: OPTIONS preflight request (should work)
Write-Host "`nTest 3: OPTIONS preflight request..." -ForegroundColor Yellow
try {
    $response3 = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method OPTIONS -Headers @{
        "Origin" = $CloudFrontUrl
        "Access-Control-Request-Method" = "GET"
        "Access-Control-Request-Headers" = "Content-Type,Authorization"
        "User-Agent" = "CORS-Test/1.0"
    } -ErrorAction Stop
    
    Write-Host "✅ OPTIONS preflight request successful" -ForegroundColor Green
    Write-Host "Status Code: $($response3.StatusCode)" -ForegroundColor Cyan
    
    # Check CORS headers
    $corsHeaders = @(
        "Access-Control-Allow-Origin",
        "Access-Control-Allow-Methods", 
        "Access-Control-Allow-Headers",
        "Access-Control-Allow-Credentials"
    )
    
    Write-Host "CORS Headers:" -ForegroundColor Cyan
    foreach ($header in $corsHeaders) {
        if ($response3.Headers[$header]) {
            Write-Host "  ${header}: $($response3.Headers[$header])" -ForegroundColor Green
        } else {
            Write-Host "  ${header}: Not present" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "❌ OPTIONS preflight failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test with invalid origin (should be blocked or no CORS headers)
Write-Host "`nTest 4: Request with invalid origin..." -ForegroundColor Yellow
try {
    $response4 = Invoke-WebRequest -Uri "$BffUrl/health" -Method GET -Headers @{
        "Origin" = "https://malicious-site.com"
        "User-Agent" = "CORS-Test/1.0"
    } -ErrorAction Stop
    
    Write-Host "⚠️  Request with invalid origin succeeded (status: $($response4.StatusCode))" -ForegroundColor Yellow
    
    # Check if CORS headers are present (they shouldn't be for invalid origins)
    if ($response4.Headers["Access-Control-Allow-Origin"]) {
        Write-Host "❌ CORS headers present for invalid origin - security issue!" -ForegroundColor Red
    } else {
        Write-Host "✅ No CORS headers for invalid origin - correct behavior" -ForegroundColor Green
    }
} catch {
    Write-Host "✅ Request with invalid origin blocked: $($_.Exception.Message)" -ForegroundColor Green
}

Write-Host "`n=== CORS Test Complete ===" -ForegroundColor Green
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "- BFF Lambda FRONTEND_URL updated to: $CloudFrontUrl" -ForegroundColor White
Write-Host "- BFF Lambda CORS_ORIGIN updated to: $CloudFrontUrl" -ForegroundColor White
Write-Host "- CORS configuration should now allow requests from CloudFront" -ForegroundColor White