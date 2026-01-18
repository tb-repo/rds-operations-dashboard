# Diagnose BFF Authentication Issues
# This script checks CloudWatch logs for authentication/authorization errors

$ErrorActionPreference = "Stop"

$FUNCTION_NAME = "rds-dashboard-bff-prod"
$REGION = "ap-southeast-1"
$LOG_GROUP = "/aws/lambda/$FUNCTION_NAME"

Write-Host "=== BFF Authentication Diagnostics ===" -ForegroundColor Cyan
Write-Host ""

# Get recent log streams
Write-Host "Fetching recent log streams..." -ForegroundColor Yellow
$logStreams = aws logs describe-log-streams `
    --log-group-name $LOG_GROUP `
    --region $REGION `
    --order-by LastEventTime `
    --descending `
    --max-items 5 `
    --query 'logStreams[*].logStreamName' `
    --output json | ConvertFrom-Json

if (-not $logStreams) {
    Write-Host "No log streams found" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($logStreams.Count) recent log streams" -ForegroundColor Green
Write-Host ""

# Check for authentication/authorization errors in recent logs
Write-Host "Searching for authentication/authorization errors..." -ForegroundColor Yellow
Write-Host ""

$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-30).ToUnixTimeMilliseconds()

$filterPatterns = @(
    '"Authentication failed"',
    '"Authorization failed"',
    '"500"',
    '"error"',
    '"INTERNAL_API_KEY"',
    '"API key"',
    '"Secrets Manager"',
    '"JWT"',
    '"token"'
)

foreach ($pattern in $filterPatterns) {
    Write-Host "Checking for: $pattern" -ForegroundColor Cyan
    
    $events = aws logs filter-log-events `
        --log-group-name $LOG_GROUP `
        --region $REGION `
        --start-time $startTime `
        --filter-pattern $pattern `
        --max-items 10 `
        --query 'events[*].[timestamp,message]' `
        --output json | ConvertFrom-Json
    
    if ($events -and $events.Count -gt 0) {
        Write-Host "  Found $($events.Count) matching events:" -ForegroundColor Yellow
        foreach ($event in $events) {
            $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($event[0]).ToString("yyyy-MM-dd HH:mm:ss")
            $message = $event[1]
            Write-Host "    [$timestamp] $message" -ForegroundColor White
        }
        Write-Host ""
    } else {
        Write-Host "  No events found" -ForegroundColor Gray
    }
}

# Check Lambda environment variables
Write-Host ""
Write-Host "Checking Lambda environment variables..." -ForegroundColor Yellow
$config = aws lambda get-function-configuration `
    --function-name $FUNCTION_NAME `
    --region $REGION `
    --query 'Environment.Variables' `
    --output json | ConvertFrom-Json

Write-Host "Environment variables:" -ForegroundColor Cyan
$config.PSObject.Properties | ForEach-Object {
    $key = $_.Name
    $value = $_.Value
    
    # Mask sensitive values
    if ($key -match "KEY|SECRET|PASSWORD|TOKEN") {
        $value = "***MASKED***"
    }
    
    Write-Host "  $key = $value" -ForegroundColor White
}

# Check if API key is configured
Write-Host ""
Write-Host "Checking API key configuration..." -ForegroundColor Yellow
if ($config.INTERNAL_API_KEY) {
    Write-Host "  INTERNAL_API_KEY: Set (length: $($config.INTERNAL_API_KEY.Length))" -ForegroundColor Green
} elseif ($config.API_SECRET_ARN) {
    Write-Host "  API_SECRET_ARN: $($config.API_SECRET_ARN)" -ForegroundColor Green
    Write-Host "  Checking Secrets Manager..." -ForegroundColor Yellow
    
    try {
        $secret = aws secretsmanager get-secret-value `
            --secret-id $config.API_SECRET_ARN `
            --region $REGION `
            --query 'SecretString' `
            --output text | ConvertFrom-Json
        
        if ($secret.apiKey) {
            Write-Host "  Secret contains apiKey: Yes (length: $($secret.apiKey.Length))" -ForegroundColor Green
        } else {
            Write-Host "  Secret does NOT contain apiKey field!" -ForegroundColor Red
        }
    } catch {
        Write-Host "  Failed to retrieve secret: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  WARNING: Neither INTERNAL_API_KEY nor API_SECRET_ARN is set!" -ForegroundColor Red
}

# Check Cognito configuration
Write-Host ""
Write-Host "Checking Cognito configuration..." -ForegroundColor Yellow
if ($config.COGNITO_USER_POOL_ID) {
    Write-Host "  COGNITO_USER_POOL_ID: $($config.COGNITO_USER_POOL_ID)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: COGNITO_USER_POOL_ID not set!" -ForegroundColor Red
}

if ($config.COGNITO_REGION) {
    Write-Host "  COGNITO_REGION: $($config.COGNITO_REGION)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: COGNITO_REGION not set!" -ForegroundColor Red
}

if ($config.COGNITO_CLIENT_ID) {
    Write-Host "  COGNITO_CLIENT_ID: $($config.COGNITO_CLIENT_ID)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: COGNITO_CLIENT_ID not set!" -ForegroundColor Red
}

# Test health endpoint
Write-Host ""
Write-Host "Testing health endpoint..." -ForegroundColor Yellow
$apiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"

try {
    $response = Invoke-RestMethod -Uri "$apiUrl/health" -Method Get
    Write-Host "  Health check: OK" -ForegroundColor Green
    Write-Host "  Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor White
} catch {
    Write-Host "  Health check: FAILED" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Diagnostics Complete ===" -ForegroundColor Cyan
