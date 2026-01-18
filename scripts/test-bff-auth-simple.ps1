# Test BFF Authentication - Simple Version
$ErrorActionPreference = "Stop"

$API_URL = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"
$REGION = "ap-southeast-1"

Write-Host "=== Testing BFF Endpoints ===" -ForegroundColor Cyan
Write-Host ""

# Test health endpoint
Write-Host "Testing /health..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$API_URL/health" -Method Get
    Write-Host "✓ Health: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "✗ Health check failed: $_" -ForegroundColor Red
}

# Test authenticated endpoint (should return 401)
Write-Host ""
Write-Host "Testing /api/instances (requires auth)..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$API_URL/api/instances" -Method Get -ErrorAction Stop
    Write-Host "✗ Unexpected success" -ForegroundColor Yellow
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Write-Host "✓ Correctly returns 401 (auth required)" -ForegroundColor Green
    } elseif ($statusCode -eq 500) {
        Write-Host "✗ Returns 500 (internal error)" -ForegroundColor Red
    } else {
        Write-Host "✗ Status code: $statusCode" -ForegroundColor Red
    }
}

# Check CloudWatch logs
Write-Host ""
Write-Host "Checking CloudWatch logs..." -ForegroundColor Yellow
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds()

Write-Host "  API key status:" -ForegroundColor Cyan
aws logs filter-log-events --log-group-name "/aws/lambda/rds-dashboard-bff-prod" --region $REGION --start-time $startTime --filter-pattern '"hasKey"' --max-items 3 --query 'events[*].message' --output text

Write-Host ""
Write-Host "  Recent errors:" -ForegroundColor Cyan
aws logs filter-log-events --log-group-name "/aws/lambda/rds-dashboard-bff-prod" --region $REGION --start-time $startTime --filter-pattern '"error"' --max-items 3 --query 'events[*].message' --output text

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Secret ARN: arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-KjtkXE" -ForegroundColor White
Write-Host "  IAM Policy: SecretsManagerAccess added to RDSDashboardLambdaRole-prod" -ForegroundColor White
Write-Host ""
Write-Host "Next: Test from dashboard UI at https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Yellow
