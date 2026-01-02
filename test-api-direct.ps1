#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test API Gateway directly with detailed error information
#>

Write-Host "=== Direct API Gateway Test ===" -ForegroundColor Cyan

$apiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/"

Write-Host "Testing: $apiUrl" -ForegroundColor Yellow

try {
    # Test with detailed error handling
    $response = Invoke-WebRequest -Uri $apiUrl -Method GET -UseBasicParsing -Verbose
    Write-Host "✅ Success!" -ForegroundColor Green
    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Headers:" -ForegroundColor Cyan
    $response.Headers.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
    }
    Write-Host "Content:" -ForegroundColor Cyan
    Write-Host $response.Content -ForegroundColor White
    
} catch [System.Net.WebException] {
    Write-Host "❌ WebException occurred" -ForegroundColor Red
    $exception = $_.Exception
    Write-Host "Message: $($exception.Message)" -ForegroundColor Red
    
    if ($exception.Response) {
        $response = $exception.Response
        Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Red
        Write-Host "Status Description: $($response.StatusDescription)" -ForegroundColor Red
        
        try {
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response Body: $responseBody" -ForegroundColor Red
        } catch {
            Write-Host "Could not read response body" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ General Exception: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing with curl (if available) ===" -ForegroundColor Cyan
try {
    $curlResult = curl -v -X GET $apiUrl 2>&1
    Write-Host "Curl output:" -ForegroundColor Yellow
    Write-Host $curlResult -ForegroundColor Gray
} catch {
    Write-Host "Curl not available or failed" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Lambda Function Status ===" -ForegroundColor Cyan
try {
    $lambdaStatus = aws lambda get-function --function-name rds-dashboard-bff-prod --region ap-southeast-1 | ConvertFrom-Json
    Write-Host "Function State: $($lambdaStatus.Configuration.State)" -ForegroundColor Green
    Write-Host "Last Update Status: $($lambdaStatus.Configuration.LastUpdateStatus)" -ForegroundColor Green
    Write-Host "Handler: $($lambdaStatus.Configuration.Handler)" -ForegroundColor Green
} catch {
    Write-Host "Could not get Lambda status: $($_.Exception.Message)" -ForegroundColor Red
}