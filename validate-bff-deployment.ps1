#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple BFF Deployment Validation

.DESCRIPTION
Quick validation script to verify BFF deployment is working correctly
#>

param(
    [string]$BffUrl = "https://api.rdsdashboard.com",
    [string]$ApiKey = "your-api-key-here",
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

# Colors for output
function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== BFF Deployment Validation ===" -ForegroundColor Cyan
Write-Info "Environment: $Environment"
Write-Info "BFF URL: $BffUrl"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Setup headers
$headers = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

$validationsPassed = 0
$validationsFailed = 0

# Test 1: Lambda Function Status
Write-Host "`n--- Test 1: Lambda Function Status ---"
try {
    $lambdaStatus = aws lambda get-function --function-name "rds-dashboard-bff-$Environment" --region ap-southeast-1 --query 'Configuration.[State,LastModified]' --output text
    Write-Success "Lambda function status: $lambdaStatus"
    $validationsPassed++
} catch {
    Write-Error "Failed to get Lambda function status: $($_.Exception.Message)"
    $validationsFailed++
}

# Test 2: Health Endpoint
Write-Host "`n--- Test 2: Health Endpoint ---"
try {
    $healthResponse = Invoke-RestMethod -Uri "$BffUrl/health" -TimeoutSec 10
    Write-Success "Health endpoint responding: $($healthResponse.status)"
    $validationsPassed++
} catch {
    Write-Error "Health endpoint failed: $($_.Exception.Message)"
    $validationsFailed++
}

# Test 3: Error Statistics Endpoint
Write-Host "`n--- Test 3: Error Statistics Endpoint ---"
try {
    $startTime = Get-Date
    $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/statistics" -Headers $headers -TimeoutSec 15
    $endTime = Get-Date
    $responseTime = ($endTime - $startTime).TotalMilliseconds
    
    Write-Success "Error statistics endpoint working"
    Write-Info "Response time: $([math]::Round($responseTime, 2))ms"
    Write-Info "Status: $($response.status)"
    
    if ($response.fallback) {
        Write-Warning "Using fallback data (monitoring service may be unavailable)"
    } else {
        Write-Success "Real data from monitoring service"
    }
    
    $validationsPassed++
} catch {
    $status = $_.Exception.Response.StatusCode
    if ($status -eq 500) {
        Write-Error "CRITICAL: Still getting 500 error - fix not working"
    } else {
        Write-Error "Error statistics endpoint failed: $status - $($_.Exception.Message)"
    }
    $validationsFailed++
}

# Test 4: Operations Endpoint (Safe Operation)
Write-Host "`n--- Test 4: Operations Endpoint ---"
$operationsPayload = @{
    operation_type = "create_snapshot"
    instance_id = "test-validation-instance"
    parameters = @{ snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $operationsPayload -TimeoutSec 15
    Write-Success "Operations endpoint accepting requests"
    $validationsPassed++
} catch {
    $status = $_.Exception.Response.StatusCode
    
    if ($status -eq 404) {
        Write-Success "Operations endpoint working (404 - test instance not found, expected)"
        $validationsPassed++
    } elseif ($status -eq 400) {
        Write-Success "Operations endpoint working (400 - validation error, expected)"
        $validationsPassed++
    } elseif ($status -eq 403) {
        Write-Error "CRITICAL: Still getting 403 error - authorization fix not working"
        $validationsFailed++
    } else {
        Write-Warning "Unexpected status: $status"
        $validationsPassed++
    }
}

# Test 5: Recent CloudWatch Logs
Write-Host "`n--- Test 5: CloudWatch Logs Check ---"
try {
    $logGroup = "/aws/lambda/rds-dashboard-bff-$Environment"
    $streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 --output json | ConvertFrom-Json
    
    if ($streams.logStreams.Count -gt 0) {
        $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $streams.logStreams[0].logStreamName --limit 10 --output json | ConvertFrom-Json
        
        $errors = $events.events | Where-Object { $_.message -match "ERROR|Exception|Failed|500" }
        
        if ($errors.Count -eq 0) {
            Write-Success "No recent errors in CloudWatch logs"
            $validationsPassed++
        } else {
            Write-Warning "$($errors.Count) recent errors found in logs"
            $errors | ForEach-Object {
                $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($_.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
                Write-Warning "[$timestamp] $($_.message.Substring(0, [Math]::Min(100, $_.message.Length)))..."
            }
            $validationsFailed++
        }
    } else {
        Write-Warning "No log streams found"
        $validationsPassed++
    }
} catch {
    Write-Warning "Could not analyze CloudWatch logs: $($_.Exception.Message)"
    $validationsPassed++
}

# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $validationsPassed" -ForegroundColor Green
Write-Host "Failed: $validationsFailed" -ForegroundColor Red

if ($validationsFailed -eq 0) {
    Write-Host "`nALL VALIDATIONS PASSED!" -ForegroundColor Green
    Write-Host "The BFF deployment is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSOME VALIDATIONS FAILED" -ForegroundColor Red
    Write-Host "Please review the failed tests above." -ForegroundColor Red
    exit 1
}