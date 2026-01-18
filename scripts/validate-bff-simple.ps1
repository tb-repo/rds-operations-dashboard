#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple BFF deployment validation

.DESCRIPTION
Validates that the BFF Lambda function is deployed and accessible
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== BFF Deployment Validation ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Check Lambda function exists
Write-Host "Test 1/3: Checking Lambda function exists..." -ForegroundColor Yellow
try {
    $function = aws lambda get-function --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json
    
    if ($function.Configuration) {
        Write-Host "  ✓ Function exists: $($function.Configuration.FunctionName)" -ForegroundColor Green
        Write-Host "    Runtime: $($function.Configuration.Runtime)" -ForegroundColor Cyan
        Write-Host "    Memory: $($function.Configuration.MemorySize) MB" -ForegroundColor Cyan
        Write-Host "    Timeout: $($function.Configuration.Timeout) seconds" -ForegroundColor Cyan
        Write-Host "    Code Size: $([math]::Round($function.Configuration.CodeSize / 1MB, 2)) MB" -ForegroundColor Cyan
        Write-Host "    Last Modified: $($function.Configuration.LastModified)" -ForegroundColor Cyan
        $testsPassed++
    } else {
        Write-Host "  ✗ Function not found" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  ✗ Failed to get function: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""

# Test 2: Check environment variables
Write-Host "Test 2/3: Checking environment variables..." -ForegroundColor Yellow
try {
    $config = aws lambda get-function-configuration --function-name $FunctionName --region $Region --output json 2>&1 | ConvertFrom-Json
    
    $requiredVars = @(
        "COGNITO_USER_POOL_ID",
        "COGNITO_CLIENT_ID",
        "COGNITO_REGION",
        "INTERNAL_API_URL"
    )
    
    $missingVars = @()
    foreach ($var in $requiredVars) {
        if ($config.Environment.Variables.$var) {
            Write-Host "  ✓ $var is set" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $var is missing" -ForegroundColor Red
            $missingVars += $var
        }
    }
    
    if ($missingVars.Count -eq 0) {
        $testsPassed++
    } else {
        $testsFailed++
    }
} catch {
    Write-Host "  ✗ Failed to check environment variables: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""

# Test 3: Test Lambda invocation
Write-Host "Test 3/3: Testing Lambda invocation..." -ForegroundColor Yellow
try {
    $payload = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{}
        requestContext = @{
            requestId = "test-request"
        }
    } | ConvertTo-Json -Compress
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $payload | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
    
    $responseFile = [System.IO.Path]::GetTempFileName()
    
    aws lambda invoke `
        --function-name $FunctionName `
        --payload "file://$tempFile" `
        --region $Region `
        $responseFile 2>&1 | Out-Null
    
    if (Test-Path $responseFile) {
        $response = Get-Content $responseFile -Raw | ConvertFrom-Json
        
        if ($response.statusCode -eq 200) {
            Write-Host "  ✓ Lambda invocation successful" -ForegroundColor Green
            Write-Host "    Status Code: $($response.statusCode)" -ForegroundColor Cyan
            $testsPassed++
        } else {
            Write-Host "  ✗ Lambda returned error status: $($response.statusCode)" -ForegroundColor Red
            Write-Host "    Body: $($response.body)" -ForegroundColor Yellow
            $testsFailed++
        }
        
        Remove-Item $responseFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  ✗ No response from Lambda" -ForegroundColor Red
        $testsFailed++
    }
    
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "  ✗ Failed to invoke Lambda: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

if ($testsFailed -eq 0) {
    Write-Host ""
    Write-Host "✓ BFF deployment is valid and ready!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Test via API Gateway" -ForegroundColor White
    Write-Host "2. Test frontend integration" -ForegroundColor White
    Write-Host "3. Monitor CloudWatch logs" -ForegroundColor White
    exit 0
} else {
    Write-Host ""
    Write-Host "✗ BFF deployment has issues that need attention" -ForegroundColor Red
    exit 1
}
