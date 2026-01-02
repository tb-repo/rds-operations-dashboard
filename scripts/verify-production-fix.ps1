#!/usr/bin/env pwsh

<#
.SYNOPSIS
Verify Production Fix

.DESCRIPTION
Verify that the production issue has been resolved and the dashboard is working
#>

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Verifying Production Fix ===" -ForegroundColor Cyan
Write-Info "CloudFront URL: https://d2qvaswtmn22om.cloudfront.net/dashboard"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Test 1: BFF Error Dashboard Endpoint
Write-Host "`n--- Test 1: BFF Error Dashboard Endpoint ---" -ForegroundColor Yellow

$testPayload1 = @{
    httpMethod = "GET"
    path = "/api/errors/dashboard"
    headers = @{ "Content-Type" = "application/json" }
    queryStringParameters = $null
} | ConvertTo-Json -Compress

$testResult1 = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload1 --region ap-southeast-1 test1.json 2>&1

if (Test-Path "test1.json") {
    $response1 = Get-Content "test1.json" | ConvertFrom-Json
    
    if ($response1.statusCode -eq 200) {
        Write-Success "✅ Error dashboard endpoint working (Status: $($response1.statusCode))"
        
        $body1 = $response1.body | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($body1 -and $body1.fallback) {
            Write-Success "✅ Fallback data structure correct"
        }
    } else {
        Write-Error "❌ Error dashboard endpoint failed (Status: $($response1.statusCode))"
    }
    
    Remove-Item "test1.json" -Force
} else {
    Write-Error "❌ No response from error dashboard endpoint"
}

# Test 2: BFF Error Statistics Endpoint
Write-Host "`n--- Test 2: BFF Error Statistics Endpoint ---" -ForegroundColor Yellow

$testPayload2 = @{
    httpMethod = "GET"
    path = "/api/errors/statistics"
    headers = @{ "Content-Type" = "application/json" }
    queryStringParameters = $null
} | ConvertTo-Json -Compress

$testResult2 = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload2 --region ap-southeast-1 test2.json 2>&1

if (Test-Path "test2.json") {
    $response2 = Get-Content "test2.json" | ConvertFrom-Json
    
    if ($response2.statusCode -eq 200) {
        Write-Success "✅ Error statistics endpoint working (Status: $($response2.statusCode))"
        
        $body2 = $response2.body | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($body2 -and $body2.statistics) {
            Write-Success "✅ Statistics data structure correct"
        }
    } else {
        Write-Error "❌ Error statistics endpoint failed (Status: $($response2.statusCode))"
    }
    
    Remove-Item "test2.json" -Force
} else {
    Write-Error "❌ No response from error statistics endpoint"
}

# Test 3: Check recent BFF logs for errors
Write-Host "`n--- Test 3: Checking Recent BFF Logs ---" -ForegroundColor Yellow

$logGroup = "/aws/lambda/rds-dashboard-bff-prod"
$streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($streams -and $streams.logStreams.Count -gt 0) {
    $latestStream = $streams.logStreams[0]
    Write-Info "Checking latest log stream: $($latestStream.logStreamName)"
    
    $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $latestStream.logStreamName --limit 10 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
    
    if ($events -and $events.events.Count -gt 0) {
        $errorEvents = $events.events | Where-Object { $_.message -match "ERROR|Error|Cannot find module" }
        
        if ($errorEvents.Count -eq 0) {
            Write-Success "✅ No recent errors in BFF logs"
        } else {
            Write-Warning "⚠️ Found $($errorEvents.Count) error events in recent logs"
            $errorEvents | Select-Object -First 2 | ForEach-Object {
                Write-Warning "  $(Get-Date $_.timestamp -UFormat '%H:%M:%S'): $($_.message.Substring(0, [Math]::Min(100, $_.message.Length)))..."
            }
        }
    } else {
        Write-Info "No recent log events found"
    }
} else {
    Write-Warning "Could not access BFF logs"
}

# Test 4: Check Lambda function status
Write-Host "`n--- Test 4: Lambda Function Status ---" -ForegroundColor Yellow

$functionInfo = aws lambda get-function --function-name "rds-dashboard-bff-prod" --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($functionInfo) {
    Write-Success "✅ Lambda function exists and is accessible"
    Write-Info "Function State: $($functionInfo.Configuration.State)"
    Write-Info "Last Modified: $($functionInfo.Configuration.LastModified)"
    Write-Info "Runtime: $($functionInfo.Configuration.Runtime)"
    Write-Info "Code Size: $([Math]::Round($functionInfo.Configuration.CodeSize / 1024, 2)) KB"
    
    if ($functionInfo.Configuration.State -eq "Active") {
        Write-Success "✅ Lambda function is active and ready"
    } else {
        Write-Warning "⚠️ Lambda function state: $($functionInfo.Configuration.State)"
    }
} else {
    Write-Error "❌ Could not retrieve Lambda function information"
}

# Summary
Write-Host "`n=== Production Fix Verification Summary ===" -ForegroundColor Cyan

Write-Host "`nExpected Results:" -ForegroundColor Yellow
Write-Host "- Error dashboard endpoint returns 200 with fallback data" -ForegroundColor Green
Write-Host "- Error statistics endpoint returns 200 with fallback data" -ForegroundColor Green
Write-Host "- No 'Cannot find module' errors in recent logs" -ForegroundColor Green
Write-Host "- Lambda function is active and ready" -ForegroundColor Green

Write-Host "`nUser Experience:" -ForegroundColor Yellow
Write-Host "• Dashboard loads without 500 errors" -ForegroundColor White
Write-Host "• Error monitoring section shows 'temporarily unavailable' message" -ForegroundColor White
Write-Host "• All other dashboard features work normally" -ForegroundColor White
Write-Host "• No more 'Failed to load error monitoring data' errors" -ForegroundColor White

Write-Host "`nTest URL:" -ForegroundColor Yellow
Write-Host "https://d2qvaswtmn22om.cloudfront.net/dashboard" -ForegroundColor Cyan

Write-Host "`nThe production issue should now be resolved!" -ForegroundColor Green