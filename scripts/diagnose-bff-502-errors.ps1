# Diagnose BFF 502 Errors
Write-Host "Diagnosing BFF 502 Errors..." -ForegroundColor Cyan

$FunctionName = "rds-dashboard-bff-production"
$Region = "ap-southeast-1"

Write-Host "`n=== Step 1: Check Lambda Function Status ===" -ForegroundColor Yellow
aws lambda get-function --function-name $FunctionName --region $Region --query 'Configuration.[FunctionName,Runtime,LastModified,State,StateReason]' --output table

Write-Host "`n=== Step 2: Check Recent Lambda Logs ===" -ForegroundColor Yellow
$LogGroup = "/aws/lambda/$FunctionName"
Write-Host "Fetching logs from: $LogGroup" -ForegroundColor Cyan

# Get the most recent log stream
$LatestStream = aws logs describe-log-streams `
    --log-group-name $LogGroup `
    --region $Region `
    --order-by LastEventTime `
    --descending `
    --max-items 1 `
    --query 'logStreams[0].logStreamName' `
    --output text

if ($LatestStream) {
    Write-Host "Latest log stream: $LatestStream" -ForegroundColor Cyan
    
    Write-Host "`nRecent log events:" -ForegroundColor Yellow
    aws logs get-log-events `
        --log-group-name $LogGroup `
        --log-stream-name $LatestStream `
        --region $Region `
        --limit 50 `
        --query 'events[*].[timestamp,message]' `
        --output text | ForEach-Object {
            if ($_ -match "ERROR|Error|error|WARN|Warning") {
                Write-Host $_ -ForegroundColor Red
            } else {
                Write-Host $_
            }
        }
} else {
    Write-Host "No log streams found" -ForegroundColor Red
}

Write-Host "`n=== Step 3: Check Lambda Environment Variables ===" -ForegroundColor Yellow
aws lambda get-function-configuration `
    --function-name $FunctionName `
    --region $Region `
    --query 'Environment.Variables' `
    --output json

Write-Host "`n=== Step 4: Test Lambda Function Directly ===" -ForegroundColor Yellow
$TestPayload = @{
    httpMethod = "GET"
    path = "/health"
    headers = @{}
    body = $null
} | ConvertTo-Json

Write-Host "Testing /health endpoint..." -ForegroundColor Cyan
$TestPayload | Out-File -FilePath "test-payload-temp.json" -Encoding UTF8

aws lambda invoke `
    --function-name $FunctionName `
    --region $Region `
    --payload file://test-payload-temp.json `
    --cli-binary-format raw-in-base64-out `
    response-temp.json

if (Test-Path "response-temp.json") {
    Write-Host "`nLambda Response:" -ForegroundColor Green
    Get-Content "response-temp.json" | ConvertFrom-Json | ConvertTo-Json -Depth 10
    Remove-Item "response-temp.json" -Force
}

if (Test-Path "test-payload-temp.json") {
    Remove-Item "test-payload-temp.json" -Force
}

Write-Host "`n=== Diagnosis Summary ===" -ForegroundColor Cyan
Write-Host "1. Check if Lambda is in 'Active' state" -ForegroundColor Yellow
Write-Host "2. Look for errors in logs (especially 'app.listen' or module import errors)" -ForegroundColor Yellow
Write-Host "3. Verify environment variables are set correctly" -ForegroundColor Yellow
Write-Host "4. Check if /health endpoint responds" -ForegroundColor Yellow

Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
Write-Host "If you see 'app.listen' errors or module import failures:" -ForegroundColor Yellow
Write-Host "  1. Run: cd bff" -ForegroundColor White
Write-Host "  2. Run: npm run build" -ForegroundColor White
Write-Host "  3. Run: ./package-lambda.ps1" -ForegroundColor White
Write-Host "  4. Run: ./deploy-to-lambda.ps1" -ForegroundColor White

Write-Host "`nIf CORS errors persist after Lambda is fixed:" -ForegroundColor Yellow
Write-Host "  1. Check API Gateway CORS configuration" -ForegroundColor White
Write-Host "  2. Verify BFF CORS middleware is working" -ForegroundColor White
Write-Host "  3. Check CloudFront origin settings" -ForegroundColor White
