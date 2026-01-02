#!/usr/bin/env pwsh

<#
.SYNOPSIS
Diagnose API connectivity issues
#>

Write-Host "=== API Connectivity Diagnosis ===" -ForegroundColor Cyan

# Test different API Gateway endpoints
$endpoints = @(
    "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/health",
    "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/health",
    "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod/health",
    "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod/api/health"
)

foreach ($endpoint in $endpoints) {
    Write-Host "Testing: $endpoint" -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri $endpoint -Method GET -UseBasicParsing -TimeoutSec 10
        Write-Host "  ✅ Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "  ✅ Content: $($response.Content)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            try {
                $errorContent = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorContent)
                $errorBody = $reader.ReadToEnd()
                Write-Host "  ❌ Error Body: $errorBody" -ForegroundColor Red
            } catch {
                Write-Host "  ❌ Could not read error body" -ForegroundColor Red
            }
        }
    }
    Write-Host ""
}

# Check Lambda function status
Write-Host "Checking Lambda function status..." -ForegroundColor Yellow
try {
    $lambdaConfig = aws lambda get-function-configuration --function-name rds-dashboard-bff-prod --region ap-southeast-1 | ConvertFrom-Json
    Write-Host "  Function Status: $($lambdaConfig.State)" -ForegroundColor Green
    Write-Host "  Last Update Status: $($lambdaConfig.LastUpdateStatus)" -ForegroundColor Green
    Write-Host "  Handler: $($lambdaConfig.Handler)" -ForegroundColor Green
    Write-Host "  Environment Variables:" -ForegroundColor Green
    $lambdaConfig.Environment.Variables.PSObject.Properties | ForEach-Object {
        Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ❌ Error checking Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Frontend Configuration Check ===" -ForegroundColor Cyan
if (Test-Path "frontend/.env") {
    Write-Host "Frontend .env file contents:" -ForegroundColor Yellow
    Get-Content "frontend/.env" | Where-Object { $_ -match "VITE_" } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Cyan
    }
} else {
    Write-Host "  ❌ Frontend .env file not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Diagnosis Complete ===" -ForegroundColor Cyan