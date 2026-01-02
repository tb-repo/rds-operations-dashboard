#!/usr/bin/env pwsh

<#
.SYNOPSIS
Verify production-only CORS configuration is working
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Verifying Production-Only CORS Configuration ===" -ForegroundColor Cyan

# Check function configuration
Write-Host "1. Checking Lambda function configuration..." -ForegroundColor Yellow
try {
    $config = aws lambda get-function-configuration --function-name $FunctionName --region $Region | ConvertFrom-Json
    
    Write-Host "Function Status:" -ForegroundColor Green
    Write-Host "  Name: $($config.FunctionName)" -ForegroundColor White
    Write-Host "  Status: $($config.LastUpdateStatus)" -ForegroundColor Green
    Write-Host "  Runtime: $($config.Runtime)" -ForegroundColor White
    
    if ($config.Environment.Variables.CORS_ORIGINS) {
        Write-Host "  CORS Origins: $($config.Environment.Variables.CORS_ORIGINS)" -ForegroundColor Green
        
        # Verify it's production-only
        if ($config.Environment.Variables.CORS_ORIGINS -eq "https://d2qvaswtmn22om.cloudfront.net") {
            Write-Host "  ✅ Production-only CORS configured correctly" -ForegroundColor Green
        } else {
            Write-Host "  ❌ CORS origins not set to production-only" -ForegroundColor Red
        }
    } else {
        Write-Host "  ❌ CORS_ORIGINS environment variable not set" -ForegroundColor Red
    }
    
    if ($config.Environment.Variables.NODE_ENV) {
        Write-Host "  Environment: $($config.Environment.Variables.NODE_ENV)" -ForegroundColor Green
        
        if ($config.Environment.Variables.NODE_ENV -eq "production") {
            Write-Host "  ✅ NODE_ENV set to production" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  NODE_ENV not set to production" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Error "Failed to get function configuration: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "2. Testing CORS functionality..." -ForegroundColor Yellow

# Test with production origin (should work)
Write-Host "Testing with production origin..." -ForegroundColor Cyan
$productionOrigin = "https://d2qvaswtmn22om.cloudfront.net"

# Create a simple test event
$testEvent = @{
    httpMethod = "OPTIONS"
    path = "/health"
    headers = @{
        Origin = $productionOrigin
        "Access-Control-Request-Method" = "GET"
        "Access-Control-Request-Headers" = "Content-Type"
    }
    queryStringParameters = $null
    body = $null
} | ConvertTo-Json -Depth 3

# Save to file for Lambda invoke
$testEvent | Out-File "cors-test-event.json" -Encoding UTF8

try {
    # Invoke the function
    aws lambda invoke `
        --function-name $FunctionName `
        --payload "file://cors-test-event.json" `
        --region $Region `
        "cors-test-response.json" | Out-Null
        
    if (Test-Path "cors-test-response.json") {
        $response = Get-Content "cors-test-response.json" | ConvertFrom-Json
        
        Write-Host "Response Status: $($response.statusCode)" -ForegroundColor Cyan
        
        if ($response.headers) {
            if ($response.headers.'Access-Control-Allow-Origin') {
                Write-Host "  ✅ CORS header present: $($response.headers.'Access-Control-Allow-Origin')" -ForegroundColor Green
                
                if ($response.headers.'Access-Control-Allow-Origin' -eq $productionOrigin) {
                    Write-Host "  ✅ CORS origin matches production origin" -ForegroundColor Green
                } else {
                    Write-Host "  ❌ CORS origin doesn't match expected production origin" -ForegroundColor Red
                }
            } else {
                Write-Host "  ❌ No CORS headers in response" -ForegroundColor Red
            }
            
            if ($response.headers.'Access-Control-Allow-Methods') {
                Write-Host "  ✅ Allowed methods: $($response.headers.'Access-Control-Allow-Methods')" -ForegroundColor Green
            }
            
            if ($response.headers.'Access-Control-Allow-Headers') {
                Write-Host "  ✅ Allowed headers: $($response.headers.'Access-Control-Allow-Headers')" -ForegroundColor Green
            }
        } else {
            Write-Host "  ❌ No headers in response" -ForegroundColor Red
        }
    } else {
        Write-Host "  ❌ No response file generated" -ForegroundColor Red
    }
} catch {
    Write-Warning "Function test had issues: $($_.Exception.Message)"
}

# Cleanup
Remove-Item "cors-test-event.json" -Force -ErrorAction SilentlyContinue
Remove-Item "cors-test-response.json" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "3. Security Verification..." -ForegroundColor Yellow

# Check that no development origins are configured
$corsOrigins = $config.Environment.Variables.CORS_ORIGINS
if ($corsOrigins) {
    $origins = $corsOrigins -split ","
    $devOrigins = $origins | Where-Object { 
        $_ -match "localhost" -or 
        $_ -match "127.0.0.1" -or 
        $_ -match "staging" -or 
        $_ -match "http://" 
    }
    
    if ($devOrigins.Count -eq 0) {
        Write-Host "  ✅ No development/staging origins detected" -ForegroundColor Green
        Write-Host "  ✅ Production-only security verified" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Development/staging origins detected: $($devOrigins -join ', ')" -ForegroundColor Red
    }
    
    # Check HTTPS only
    $httpOrigins = $origins | Where-Object { $_ -match "^http://" }
    if ($httpOrigins.Count -eq 0) {
        Write-Host "  ✅ All origins use HTTPS" -ForegroundColor Green
    } else {
        Write-Host "  ❌ HTTP origins detected (security risk): $($httpOrigins -join ', ')" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== CORS Verification Summary ===" -ForegroundColor Cyan
Write-Host "Function: $FunctionName" -ForegroundColor White
Write-Host "Region: $Region" -ForegroundColor White
Write-Host "Production Origin: $productionOrigin" -ForegroundColor Green
Write-Host "Configuration: Production-only CORS" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Test dashboard at: $productionOrigin" -ForegroundColor White
Write-Host "2. Verify no CORS errors in browser console" -ForegroundColor White
Write-Host "3. Confirm all API calls work correctly" -ForegroundColor White
Write-Host ""
Write-Host "Production-only CORS verification complete!" -ForegroundColor Green