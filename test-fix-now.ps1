#!/usr/bin/env pwsh

Write-Host "🧪 Testing Operations Fix" -ForegroundColor Green

$OPS_FUNCTION = "rds-operations-prod"
$REGION = "ap-southeast-1"

Write-Host "⏳ Waiting for deployment to propagate..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

Write-Host "🔍 Testing Operations Lambda..." -ForegroundColor Cyan

$testPayload = @{
    instance_id = "tb-pg-db1"
    operation = "stop_instance"
    region = "ap-southeast-1"
    account_id = "876595225096"
    parameters = @{}
} | ConvertTo-Json -Depth 3

$lambdaEvent = @{
    body = $testPayload
    requestContext = @{
        identity = @{}
    }
} | ConvertTo-Json -Depth 4

Write-Host "📤 Sending test request..." -ForegroundColor Cyan

aws lambda invoke --function-name $OPS_FUNCTION --payload $lambdaEvent --region $REGION response.json

if ($LASTEXITCODE -eq 0) {
    $responseContent = Get-Content "response.json" | ConvertFrom-Json
    Write-Host "📥 Response Status: $($responseContent.statusCode)" -ForegroundColor Cyan
    
    if ($responseContent.statusCode -eq 200) {
        Write-Host "✅ Test PASSED - Operations working!" -ForegroundColor Green
    } elseif ($responseContent.statusCode -eq 404) {
        Write-Host "⚠️  Test PARTIAL - Lambda working but instance not found (expected)" -ForegroundColor Yellow
        Write-Host "This means the 400 error is fixed!" -ForegroundColor Green
    } elseif ($responseContent.statusCode -eq 400) {
        Write-Host "❌ Test FAILED - Still getting 400 error" -ForegroundColor Red
        Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
    } else {
        Write-Host "⚠️  Test UNKNOWN - Status: $($responseContent.statusCode)" -ForegroundColor Yellow
        Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
    }
} else {
    Write-Host "❌ Lambda invocation failed" -ForegroundColor Red
}

# Clean up
if (Test-Path "response.json") {
    Remove-Item "response.json" -Force
}

Write-Host ""
Write-Host "🎯 Test Results:" -ForegroundColor Cyan
Write-Host "• If 200 or 404: Operations Lambda is working correctly" -ForegroundColor White
Write-Host "• If 404: Instance not in inventory (run discovery)" -ForegroundColor White
Write-Host "• If still 400: Check CloudWatch logs for details" -ForegroundColor White
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Try operations in the dashboard UI" -ForegroundColor White
Write-Host "2. If 404 errors: Run discovery to populate inventory" -ForegroundColor White
Write-Host "3. Monitor logs: /aws/lambda/$OPS_FUNCTION" -ForegroundColor White