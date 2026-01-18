Write-Host "Testing BFF Operations Endpoint with CORS" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Wait for Lambda to be ready
Write-Host "Waiting for Lambda function to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Test 1: OPTIONS request (preflight)
Write-Host "Test 1: OPTIONS Request (CORS Preflight)" -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor Green

try {
    $optionsResponse = Invoke-WebRequest -Uri "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations" -Method OPTIONS -Headers @{'Origin' = 'https://d2qvaswtmn22om.cloudfront.net'; 'Access-Control-Request-Method' = 'POST'; 'Access-Control-Request-Headers' = 'content-type'} -UseBasicParsing -ErrorAction Stop
    Write-Host "Status: $($optionsResponse.StatusCode)" -ForegroundColor Green
    Write-Host "Access-Control-Allow-Origin: $($optionsResponse.Headers['Access-Control-Allow-Origin'])" -ForegroundColor Green
    Write-Host "Access-Control-Allow-Methods: $($optionsResponse.Headers['Access-Control-Allow-Methods'])" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "OPTIONS request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# Test 2: POST request with Origin header
Write-Host "Test 2: POST Request with Origin Header" -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor Green

$body = '{"action":"start","instanceId":"test-instance","accountId":"876595225096"}'

try {
    $postResponse = Invoke-WebRequest -Uri "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations" -Method POST -Headers @{'Origin' = 'https://d2qvaswtmn22om.cloudfront.net'; 'Content-Type' = 'application/json'} -Body $body -UseBasicParsing -ErrorAction Stop
    Write-Host "Status: $($postResponse.StatusCode)" -ForegroundColor Green
    Write-Host "Access-Control-Allow-Origin: $($postResponse.Headers['Access-Control-Allow-Origin'])" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "POST request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# Test 3: Check Lambda function configuration
Write-Host "Test 3: Lambda Function Configuration" -ForegroundColor Green
Write-Host "--------------------------------------" -ForegroundColor Green

$lambdaConfig = aws lambda get-function-configuration --function-name rds-dashboard-bff-prod --region ap-southeast-1 --query '{LastModified:LastModified,CodeSize:CodeSize,CORS:Environment.Variables.CORS_ORIGINS}' --output json | ConvertFrom-Json

Write-Host "Last Modified: $($lambdaConfig.LastModified)" -ForegroundColor Green
Write-Host "Code Size: $($lambdaConfig.CodeSize) bytes" -ForegroundColor Green
Write-Host "CORS Origins: $($lambdaConfig.CORS)" -ForegroundColor Green
Write-Host ""

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "CORS Testing Complete!" -ForegroundColor Cyan
