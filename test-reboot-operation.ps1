#!/usr/bin/env pwsh

# Test Reboot Operation
$ErrorActionPreference = "Stop"

Write-Host "Testing Reboot Operation..." -ForegroundColor Cyan

# Test with reboot operation on tb-pg-db1
$payload = @{
    body = @{
        instance_id = "tb-pg-db1"  # Use tb-pg-db1
        operation = "reboot"
        parameters = @{
            force_failover = $false
        }
        user_id = "test-user"
        requested_by = "test@example.com"
        user_groups = @("Admin")
    } | ConvertTo-Json
    requestContext = @{
        identity = @{
            sourceIp = "127.0.0.1"
        }
    }
} | ConvertTo-Json -Depth 5

Write-Host "Payload:" -ForegroundColor Yellow
Write-Host $payload

# Convert to base64
$payloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload))

Write-Host "`nInvoking operations Lambda..." -ForegroundColor Yellow

try {
    $result = aws lambda invoke --function-name "rds-operations-prod" --payload $payloadBase64 --output json response.json
    
    if (Test-Path response.json) {
        $response = Get-Content response.json -Raw
        Write-Host "Raw Response:" -ForegroundColor Green
        Write-Host $response
        
        try {
            $responseObj = $response | ConvertFrom-Json
            Write-Host "`nParsed Response:" -ForegroundColor Green
            Write-Host "Status Code: $($responseObj.statusCode)"
            
            if ($responseObj.body) {
                Write-Host "Body:" -ForegroundColor Green
                $bodyObj = $responseObj.body | ConvertFrom-Json
                $bodyObj | ConvertTo-Json -Depth 5
            }
        } catch {
            Write-Host "Could not parse response as JSON" -ForegroundColor Yellow
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "No response file created" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nTest Complete!" -ForegroundColor Cyan