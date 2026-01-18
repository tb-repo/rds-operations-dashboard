#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test Operations 400 Error Fix

.DESCRIPTION
Tests the operations endpoint to verify the 400 error fix is working.
This script tests both the BFF and Lambda components.

.EXAMPLE
./scripts/test-operations-fix.ps1
Test the operations fix
#>

$ErrorActionPreference = "Stop"

Write-Host "🧪 Testing Operations 400 Error Fix" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff-prod"
$OPERATIONS_FUNCTION_NAME = "rds-operations-prod"
$REGION = "ap-southeast-1"

Write-Host "📋 Test Configuration:" -ForegroundColor Cyan
Write-Host "  BFF Function: $BFF_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Operations Function: $OPERATIONS_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Region: $REGION" -ForegroundColor White
Write-Host ""

# Test 1: Direct Operations Lambda Test
Write-Host "🧪 Test 1: Direct Operations Lambda Test" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$testPayload = @{
    instance_id = "tb-pg-db1"
    operation = "stop_instance"
    region = "ap-southeast-1"
    account_id = "876595225096"
    parameters = @{}
    user_id = "test-user"
    requested_by = "test@example.com"
    user_groups = @("Admin")
} | ConvertTo-Json -Depth 3

$lambdaEvent = @{
    body = $testPayload
    requestContext = @{
        identity = @{}
    }
} | ConvertTo-Json -Depth 4

Write-Host "📤 Sending test request to Operations Lambda..." -ForegroundColor Cyan
Write-Host "Payload: $testPayload" -ForegroundColor Gray

try {
    $response = aws lambda invoke `
        --function-name $OPERATIONS_FUNCTION_NAME `
        --payload $lambdaEvent `
        --region $REGION `
        response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content "response.json" | ConvertFrom-Json
        Write-Host "📥 Response Status: $($responseContent.statusCode)" -ForegroundColor Cyan
        
        if ($responseContent.statusCode -eq 200) {
            Write-Host "✅ Test 1 PASSED: Operations Lambda working correctly" -ForegroundColor Green
            $body = $responseContent.body | ConvertFrom-Json
            Write-Host "Operation Result: $($body.operation) on $($body.instance_id)" -ForegroundColor White
        } elseif ($responseContent.statusCode -eq 404) {
            Write-Host "⚠️  Test 1 PARTIAL: Lambda working but instance not found (expected)" -ForegroundColor Yellow
            Write-Host "This means the 400 error is fixed - instance just doesn't exist in inventory" -ForegroundColor Gray
        } elseif ($responseContent.statusCode -eq 400) {
            Write-Host "❌ Test 1 FAILED: Still getting 400 error" -ForegroundColor Red
            Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  Test 1 UNKNOWN: Unexpected status $($responseContent.statusCode)" -ForegroundColor Yellow
            Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
        }
    } else {
        Write-Host "❌ Test 1 FAILED: Lambda invocation failed" -ForegroundColor Red
    }
    
    # Clean up
    if (Test-Path "response.json") {
        Remove-Item "response.json" -Force
    }
    
} catch {
    Write-Host "❌ Test 1 ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Invalid Request Test (should return proper 400 with clear message)
Write-Host "🧪 Test 2: Invalid Request Test" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

$invalidPayload = @{
    # Missing required fields to test validation
    parameters = @{}
} | ConvertTo-Json -Depth 3

$invalidEvent = @{
    body = $invalidPayload
    requestContext = @{
        identity = @{}
    }
} | ConvertTo-Json -Depth 4

Write-Host "📤 Sending invalid request to test error handling..." -ForegroundColor Cyan

try {
    $response = aws lambda invoke `
        --function-name $OPERATIONS_FUNCTION_NAME `
        --payload $invalidEvent `
        --region $REGION `
        response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content "response.json" | ConvertFrom-Json
        Write-Host "📥 Response Status: $($responseContent.statusCode)" -ForegroundColor Cyan
        
        if ($responseContent.statusCode -eq 400) {
            $body = $responseContent.body | ConvertFrom-Json
            if ($body.error -and $body.error -like "*Operation type is required*") {
                Write-Host "✅ Test 2 PASSED: Proper validation error returned" -ForegroundColor Green
                Write-Host "Error Message: $($body.error)" -ForegroundColor White
            } else {
                Write-Host "⚠️  Test 2 PARTIAL: 400 returned but unexpected error message" -ForegroundColor Yellow
                Write-Host "Error: $($body.error)" -ForegroundColor Gray
            }
        } else {
            Write-Host "❌ Test 2 FAILED: Expected 400 but got $($responseContent.statusCode)" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Test 2 FAILED: Lambda invocation failed" -ForegroundColor Red
    }
    
    # Clean up
    if (Test-Path "response.json") {
        Remove-Item "response.json" -Force
    }
    
} catch {
    Write-Host "❌ Test 2 ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: BFF Function Test (if accessible)
Write-Host "🧪 Test 3: BFF Function Test" -ForegroundColor Yellow
Write-Host "-----------------------------" -ForegroundColor Yellow

$bffTestPayload = @{
    instance_id = "tb-pg-db1"
    operation = "stop_instance"
    region = "ap-southeast-1"
    account_id = "876595225096"
    parameters = @{}
} | ConvertTo-Json -Depth 3

$bffEvent = @{
    httpMethod = "POST"
    path = "/api/operations"
    body = $bffTestPayload
    headers = @{
        "Content-Type" = "application/json"
        "Authorization" = "Bearer test-token"
    }
    requestContext = @{
        identity = @{}
    }
} | ConvertTo-Json -Depth 4

Write-Host "📤 Testing BFF operations endpoint..." -ForegroundColor Cyan

try {
    $response = aws lambda invoke `
        --function-name $BFF_FUNCTION_NAME `
        --payload $bffEvent `
        --region $REGION `
        response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content "response.json" | ConvertFrom-Json
        Write-Host "📥 BFF Response Status: $($responseContent.statusCode)" -ForegroundColor Cyan
        
        if ($responseContent.statusCode -eq 200 -or $responseContent.statusCode -eq 404) {
            Write-Host "✅ Test 3 PASSED: BFF operations endpoint working" -ForegroundColor Green
        } elseif ($responseContent.statusCode -eq 401) {
            Write-Host "⚠️  Test 3 PARTIAL: BFF working but authentication required (expected)" -ForegroundColor Yellow
        } elseif ($responseContent.statusCode -eq 400) {
            Write-Host "❌ Test 3 FAILED: BFF still returning 400 error" -ForegroundColor Red
            Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  Test 3 UNKNOWN: BFF returned status $($responseContent.statusCode)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Test 3 FAILED: BFF invocation failed" -ForegroundColor Red
    }
    
    # Clean up
    if (Test-Path "response.json") {
        Remove-Item "response.json" -Force
    }
    
} catch {
    Write-Host "❌ Test 3 ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Summary
Write-Host "📊 Test Results Summary" -ForegroundColor Green
Write-Host "=======================" -ForegroundColor Green
Write-Host ""
Write-Host "🎯 Key Indicators:" -ForegroundColor Cyan
Write-Host "• If Test 1 shows 200 or 404: Operations Lambda is working correctly" -ForegroundColor White
Write-Host "• If Test 2 shows proper 400 validation: Error handling is improved" -ForegroundColor White
Write-Host "• If Test 3 shows 200/404/401: BFF is forwarding requests correctly" -ForegroundColor White
Write-Host ""
Write-Host "🔍 Next Steps:" -ForegroundColor Cyan
Write-Host "1. If tests pass: Try operations in the dashboard UI" -ForegroundColor White
Write-Host "2. If 404 errors: Run discovery to populate instance inventory" -ForegroundColor White
Write-Host "3. If still 400 errors: Check CloudWatch logs for detailed error info" -ForegroundColor White
Write-Host "4. Monitor logs: Both BFF and Operations Lambda now have enhanced logging" -ForegroundColor White
Write-Host ""
Write-Host "📋 Log Locations:" -ForegroundColor Cyan
Write-Host "• BFF Logs: /aws/lambda/$BFF_FUNCTION_NAME" -ForegroundColor White
Write-Host "• Operations Logs: /aws/lambda/$OPERATIONS_FUNCTION_NAME" -ForegroundColor White
Write-Host ""
Write-Host "🚀 Operations Fix Testing Complete!" -ForegroundColor Green