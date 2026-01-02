#!/usr/bin/env pwsh
# Diagnose BFF Issue

Write-Host "=== BFF Diagnostic Script ===" -ForegroundColor Cyan

# Test 1: Query Handler Lambda directly
Write-Host "`n1. Testing Query Handler Lambda directly..." -ForegroundColor Yellow
$payload = '{"httpMethod":"GET","path":"/instances","headers":{}}'
aws lambda invoke --function-name rds-query-handler-prod --cli-binary-format raw-in-base64-out --payload $payload test1.json 2>&1 | Out-Null
$result1 = Get-Content test1.json -Raw | ConvertFrom-Json
if ($result1.statusCode -eq 200) {
    Write-Host "✓ Query Handler works" -ForegroundColor Green
} else {
    Write-Host "✗ Query Handler failed" -ForegroundColor Red
    Write-Host "Error: $($result1.errorMessage)" -ForegroundColor Red
}

# Test 2: Internal API with API Key
Write-Host "`n2. Testing Internal API with API Key..." -ForegroundColor Yellow
$secret = aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod --query SecretString --output text | ConvertFrom-Json
$headers = @{ 'x-api-key' = $secret.apiKey; 'Content-Type' = 'application/json' }
try {
    $response = Invoke-WebRequest -Uri 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/instances' -Method GET -Headers $headers -UseBasicParsing
    Write-Host "✓ Internal API works (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "✗ Internal API failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: BFF Lambda directly
Write-Host "`n3. Testing BFF Lambda directly..." -ForegroundColor Yellow
$payload = '{"httpMethod":"GET","path":"/instances","headers":{"Origin":"http://localhost:5173"}}'
aws lambda invoke --function-name rds-dashboard-bff-prod --cli-binary-format raw-in-base64-out --payload $payload test3.json 2>&1 | Out-Null
$result3 = Get-Content test3.json -Raw | ConvertFrom-Json
if ($result3.statusCode -eq 200) {
    Write-Host "✓ BFF Lambda works" -ForegroundColor Green
    $body = $result3.body | ConvertFrom-Json
    Write-Host "  Instances: $($body.instances.Count)" -ForegroundColor Cyan
} else {
    Write-Host "✗ BFF Lambda failed" -ForegroundColor Red
    Write-Host "Status: $($result3.statusCode)" -ForegroundColor Red
}

# Test 4: BFF API Gateway
Write-Host "`n4. Testing BFF API Gateway..." -ForegroundColor Yellow
$headers = @{ 'Origin' = 'http://localhost:5173'; 'Content-Type' = 'application/json' }
try {
    $response = Invoke-WebRequest -Uri 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/instances' -Method GET -Headers $headers -UseBasicParsing
    Write-Host "✓ BFF API Gateway works (Status: $($response.StatusCode))" -ForegroundColor Green
    $content = $response.Content | ConvertFrom-Json
    Write-Host "  Instances: $($content.instances.Count)" -ForegroundColor Cyan
} catch {
    Write-Host "✗ BFF API Gateway failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# Test 5: Check BFF logs for errors
Write-Host "`n5. Checking recent BFF logs..." -ForegroundColor Yellow
$logs = aws logs tail /aws/lambda/rds-dashboard-bff-prod --since 2m --format short 2>&1 | Select-String "ERROR|error|Error" | Select-Object -First 5
if ($logs) {
    Write-Host "Found errors in logs:" -ForegroundColor Red
    $logs | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
} else {
    Write-Host "No errors found in recent logs" -ForegroundColor Green
}

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Cyan
