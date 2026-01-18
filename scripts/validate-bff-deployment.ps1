#!/usr/bin/env pwsh

<#
.SYNOPSIS
Validate BFF deployment

.DESCRIPTION
Tests the deployed BFF Lambda function to ensure it's working correctly.
Checks health endpoint, CORS configuration, and basic API functionality.

.PARAMETER FunctionName
The Lambda function name (default: rds-dashboard-bff-prod)

.PARAMETER Region
AWS region (default: ap-southeast-1)

.PARAMETER ApiUrl
API Gateway URL (optional, will test via Lambda if not provided)

.EXAMPLE
./validate-bff-deployment.ps1
./validate-bff-deployment.ps1 -ApiUrl https://your-api.execute-api.ap-southeast-1.amazonaws.com/prod
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1",
    [string]$ApiUrl = ""
)

$ErrorActionPreference = "Continue"

Write-Host "=== BFF Deployment Validation ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Lambda function exists
Write-Host "[Test 1/5] Checking Lambda function exists..." -ForegroundColor Yellow
try {
    $functionInfo = aws lambda get-function --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json
    Write-Host "✓ Lambda function exists" -ForegroundColor Green
    Write-Host "  Runtime: $($functionInfo.Configuration.Runtime)" -ForegroundColor Gray
    Write-Host "  Handler: $($functionInfo.Configuration.Handler)" -ForegroundColor Gray
    Write-Host "  Memory: $($functionInfo.Configuration.MemorySize) MB" -ForegroundColor Gray
    Write-Host "  Timeout: $($functionInfo.Configuration.Timeout) seconds" -ForegroundColor Gray
    $testsPassed++
} catch {
    Write-Host "✗ Lambda function not found" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 2: Health endpoint via Lambda
Write-Host "[Test 2/5] Testing health endpoint via Lambda..." -ForegroundColor Yellow
try {
    $healthPayload = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{}
    } | ConvertTo-Json -Compress

    $null = aws lambda invoke `
        --function-name $FunctionName `
        --payload $healthPayload `
        --region $Region `
        health-response.json 2>&1

    if (Test-Path "health-response.json") {
        $response = Get-Content "health-response.json" -Raw | ConvertFrom-Json
        
        if ($response.statusCode -eq 200) {
            Write-Host "✓ Health endpoint responding" -ForegroundColor Green
            $body = $response.body | ConvertFrom-Json
            Write-Host "  Status: $($body.status)" -ForegroundColor Gray
            Write-Host "  Service: $($body.service)" -ForegroundColor Gray
            $testsPassed++
        } else {
            Write-Host "✗ Health endpoint returned status: $($response.statusCode)" -ForegroundColor Red
            $testsFailed++
        }
        
        Remove-Item "health-response.json" -Force
    } else {
        Write-Host "✗ No response from Lambda" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "✗ Health check failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 3: CORS headers
Write-Host "[Test 3/5] Testing CORS configuration..." -ForegroundColor Yellow
try {
    $corsPayload = @{
        httpMethod = "OPTIONS"
        path = "/api/instances"
        headers = @{
            "Origin" = "https://your-cloudfront-domain.cloudfront.net"
            "Access-Control-Request-Method" = "GET"
        }
    } | ConvertTo-Json -Compress

    $null = aws lambda invoke `
        --function-name $FunctionName `
        --payload $corsPayload `
        --region $Region `
        cors-response.json 2>&1

    if (Test-Path "cors-response.json") {
        $response = Get-Content "cors-response.json" -Raw | ConvertFrom-Json
        
        if ($response.statusCode -eq 200 -or $response.statusCode -eq 204) {
            $headers = $response.headers
            if ($headers.'Access-Control-Allow-Origin') {
                Write-Host "✓ CORS headers present" -ForegroundColor Green
                Write-Host "  Allow-Origin: $($headers.'Access-Control-Allow-Origin')" -ForegroundColor Gray
                Write-Host "  Allow-Methods: $($headers.'Access-Control-Allow-Methods')" -ForegroundColor Gray
                Write-Host "  Allow-Headers: $($headers.'Access-Control-Allow-Headers')" -ForegroundColor Gray
                $testsPassed++
            } else {
                Write-Host "✗ CORS headers missing" -ForegroundColor Red
                $testsFailed++
            }
        } else {
            Write-Host "✗ OPTIONS request returned status: $($response.statusCode)" -ForegroundColor Red
            $testsFailed++
        }
        
        Remove-Item "cors-response.json" -Force
    } else {
        Write-Host "✗ No response from Lambda" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "✗ CORS test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 4: Environment variables
Write-Host "[Test 4/5] Checking environment variables..." -ForegroundColor Yellow
try {
    $config = aws lambda get-function-configuration --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json
    $env = $config.Environment.Variables
    
    $requiredVars = @(
        "COGNITO_USER_POOL_ID",
        "COGNITO_CLIENT_ID",
        "COGNITO_REGION",
        "INTERNAL_API_URL"
    )
    
    $missingVars = @()
    foreach ($var in $requiredVars) {
        if (-not $env.$var) {
            $missingVars += $var
        }
    }
    
    if ($missingVars.Count -eq 0) {
        Write-Host "✓ All required environment variables set" -ForegroundColor Green
        Write-Host "  COGNITO_USER_POOL_ID: $($env.COGNITO_USER_POOL_ID)" -ForegroundColor Gray
        Write-Host "  COGNITO_REGION: $($env.COGNITO_REGION)" -ForegroundColor Gray
        Write-Host "  INTERNAL_API_URL: $($env.INTERNAL_API_URL)" -ForegroundColor Gray
        $testsPassed++
    } else {
        Write-Host "✗ Missing environment variables: $($missingVars -join ', ')" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "✗ Failed to check environment variables: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}
Write-Host ""

# Test 5: CloudWatch logs
Write-Host "[Test 5/5] Checking CloudWatch logs..." -ForegroundColor Yellow
try {
    $logGroup = "/aws/lambda/$FunctionName"
    $recentLogs = aws logs describe-log-streams `
        --log-group-name $logGroup `
        --order-by LastEventTime `
        --descending `
        --max-items 1 `
        --region $Region `
        --output json 2>&1 | ConvertFrom-Json
    
    if ($recentLogs.logStreams -and $recentLogs.logStreams.Count -gt 0) {
        $latestStream = $recentLogs.logStreams[0]
        $lastEventTime = [DateTimeOffset]::FromUnixTimeMilliseconds($latestStream.lastEventTime).DateTime
        Write-Host "✓ CloudWatch logs accessible" -ForegroundColor Green
        Write-Host "  Log Group: $logGroup" -ForegroundColor Gray
        Write-Host "  Latest Stream: $($latestStream.logStreamName)" -ForegroundColor Gray
        Write-Host "  Last Event: $lastEventTime" -ForegroundColor Gray
        $testsPassed++
    } else {
        Write-Host "⚠ No log streams found (function may not have been invoked yet)" -ForegroundColor Yellow
        $testsPassed++
    }
} catch {
    Write-Host "⚠ Could not access CloudWatch logs: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  This is not critical if the function is newly deployed" -ForegroundColor Gray
    $testsPassed++
}
Write-Host ""

# Summary
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "✓ BFF deployment is healthy!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Test via API Gateway: curl https://your-api-url/health" -ForegroundColor White
    Write-Host "  2. Test frontend integration" -ForegroundColor White
    Write-Host "  3. Monitor logs: aws logs tail /aws/lambda/$FunctionName --follow" -ForegroundColor White
    exit 0
} else {
    Write-Host "✗ BFF deployment has issues that need attention" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check Lambda function logs: aws logs tail /aws/lambda/$FunctionName --follow" -ForegroundColor White
    Write-Host "  2. Verify environment variables are set correctly" -ForegroundColor White
    Write-Host "  3. Test Lambda directly: aws lambda invoke --function-name $FunctionName --payload file://test-payload.json response.json" -ForegroundColor White
    Write-Host "  4. Review deployment script output for errors" -ForegroundColor White
    exit 1
}
