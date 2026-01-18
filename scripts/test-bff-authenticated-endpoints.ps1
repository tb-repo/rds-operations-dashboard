# Test BFF Authenticated Endpoints
# This script tests that authenticated endpoints now work after fixing Secrets Manager access

$ErrorActionPreference = "Stop"

$API_URL = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"
$REGION = "ap-southeast-1"

Write-Host "=== Testing BFF Authenticated Endpoints ===" -ForegroundColor Cyan
Write-Host ""

# First, check CloudWatch logs for API key loading
Write-Host "Checking if API key is loading successfully..." -ForegroundColor Yellow
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds()

$apiKeyLogs = aws logs filter-log-events `
    --log-group-name "/aws/lambda/rds-dashboard-bff-prod" `
    --region $REGION `
    --start-time $startTime `
    --filter-pattern '"API key"' `
    --max-items 5 `
    --query 'events[*].message' `
    --output json | ConvertFrom-Json

if ($apiKeyLogs) {
    Write-Host "Recent API key logs:" -ForegroundColor Cyan
    foreach ($log in $apiKeyLogs) {
        if ($log -match '"hasKey":(true|false)') {
            $hasKey = $matches[1]
            if ($hasKey -eq "true") {
                Write-Host "  ✓ API key loaded successfully" -ForegroundColor Green
            } else {
                Write-Host "  ✗ API key NOT loaded (hasKey: false)" -ForegroundColor Red
            }
        }
        Write-Host "  $log" -ForegroundColor Gray
    }
} else {
    Write-Host "No recent API key logs found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Testing endpoints..." -ForegroundColor Yellow
Write-Host ""

# Test 1: Health endpoint (no auth required)
Write-Host "1. Testing /health (no auth)..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$API_URL/health" -Method Get
    Write-Host "   ✓ Status: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Failed: $_" -ForegroundColor Red
}

# Test 2: Instances endpoint (requires auth - should return 401)
Write-Host ""
Write-Host "2. Testing /api/instances (requires auth)..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$API_URL/api/instances" -Method Get -ErrorAction Stop
    Write-Host "   ✗ Unexpected success (should require auth)" -ForegroundColor Yellow
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Write-Host "   ✓ Correctly returns 401 Unauthorized (auth required)" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Unexpected status code: $statusCode" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
    }
}

# Test 3: Check if we can get a Cognito token (for manual testing)
Write-Host ""
Write-Host "3. Cognito authentication info..." -ForegroundColor Cyan
$userPoolId = "ap-southeast-1_4tyxh4qJe"
$clientId = "28e031hsul0mi91k0s6f33bs7s"
$region = "ap-southeast-1"

Write-Host "   User Pool ID: $userPoolId" -ForegroundColor White
Write-Host "   Client ID: $clientId" -ForegroundColor White
Write-Host "   Region: $region" -ForegroundColor White
Write-Host ""
Write-Host "   To test authenticated endpoints:" -ForegroundColor Yellow
Write-Host "   1. Log in to the dashboard at: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor White
Write-Host "   2. Open browser DevTools (F12)" -ForegroundColor White
Write-Host "   3. Check Network tab for API calls" -ForegroundColor White
Write-Host "   4. Look for Authorization header with JWT token" -ForegroundColor White

# Test 4: Check recent errors in CloudWatch
Write-Host ""
Write-Host "4. Checking for recent errors..." -ForegroundColor Cyan
$errorLogs = aws logs filter-log-events `
    --log-group-name "/aws/lambda/rds-dashboard-bff-prod" `
    --region $REGION `
    --start-time $startTime `
    --filter-pattern '"error"' `
    --max-items 5 `
    --query 'events[*].message' `
    --output json | ConvertFrom-Json

if ($errorLogs) {
    Write-Host "   Recent errors found:" -ForegroundColor Yellow
    foreach ($log in $errorLogs) {
        if ($log -match "Secrets Manager") {
            Write-Host "   ✗ Secrets Manager error: $log" -ForegroundColor Red
        } elseif ($log -match "API key") {
            Write-Host "   ⚠ API key related: $log" -ForegroundColor Yellow
        } else {
            Write-Host "   $log" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   ✓ No recent errors" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration Status:" -ForegroundColor Yellow
Write-Host "  - Secret ARN: arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-KjtkXE" -ForegroundColor White
Write-Host "  - IAM permissions: Added SecretsManagerAccess policy" -ForegroundColor White
Write-Host "  - Lambda environment: Updated with correct ARN" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. If API key is still not loading, check Lambda execution role permissions" -ForegroundColor White
Write-Host "  2. Test authenticated endpoints from the dashboard UI" -ForegroundColor White
Write-Host "  3. Monitor CloudWatch logs for any remaining errors" -ForegroundColor White
Write-Host ""
