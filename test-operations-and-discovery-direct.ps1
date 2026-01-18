#!/usr/bin/env pwsh

# Test Operations and Discovery Endpoints Directly
# This script tests the actual API endpoints to diagnose issues

$ErrorActionPreference = "Stop"

Write-Host "Testing Operations and Discovery Endpoints..." -ForegroundColor Cyan

# Configuration
$API_BASE_URL = "https://api.rds-dashboard.com"
$BFF_URL = "https://bff.rds-dashboard.com"

# Test 1: Test Discovery Trigger via BFF
Write-Host "`nTest 1: Testing Discovery Trigger via BFF" -ForegroundColor Yellow

try {
    $discoveryPayload = @{
        trigger = "manual"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json

    Write-Host "Discovery payload: $discoveryPayload"
    
    # Note: This will fail without auth token, but we can see the response
    $discoveryResponse = Invoke-RestMethod -Uri "$BFF_URL/api/discovery/trigger" -Method POST -Body $discoveryPayload -ContentType "application/json" -ErrorAction Continue
    
    Write-Host "Discovery Response: $($discoveryResponse | ConvertTo-Json -Depth 3)" -ForegroundColor Green
    
} catch {
    Write-Host "Discovery Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

# Test 2: Test Operations via BFF
Write-Host "`nTest 2: Testing Operations via BFF" -ForegroundColor Yellow

try {
    $operationPayload = @{
        instance_id = "tb-pg-db1"
        operation = "create_snapshot"
        region = "ap-southeast-1"
        account_id = "876595225096"
        parameters = @{
            snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json

    Write-Host "Operation payload: $operationPayload"
    
    # Note: This will fail without auth token, but we can see the response
    $operationResponse = Invoke-RestMethod -Uri "$BFF_URL/api/operations" -Method POST -Body $operationPayload -ContentType "application/json" -ErrorAction Continue
    
    Write-Host "Operation Response: $($operationResponse | ConvertTo-Json -Depth 3)" -ForegroundColor Green
    
} catch {
    Write-Host "Operation Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

# Test 3: Test Direct Lambda Invocation for Discovery
Write-Host "`nTest 3: Testing Direct Discovery Lambda" -ForegroundColor Yellow

try {
    $discoveryLambdaPayload = @{
        trigger = "test"
    } | ConvertTo-Json

    Write-Host "Invoking discovery Lambda directly..."
    
    $discoveryLambdaResponse = aws lambda invoke --function-name "rds-discovery-prod" --payload $discoveryLambdaPayload --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json | ConvertFrom-Json
        Write-Host "Discovery Lambda Response: $($responseContent | ConvertTo-Json -Depth 3)" -ForegroundColor Green
        
        # Clean up
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Discovery Lambda invocation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Discovery Lambda Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test Direct Lambda Invocation for Operations
Write-Host "`nTest 4: Testing Direct Operations Lambda" -ForegroundColor Yellow

try {
    $operationsLambdaPayload = @{
        body = @{
            instance_id = "tb-pg-db1"
            operation = "create_snapshot"
            region = "ap-southeast-1"
            account_id = "876595225096"
            parameters = @{
                snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            user_id = "test-user"
            requested_by = "test@example.com"
            user_groups = @("Admin")
        } | ConvertTo-Json
        requestContext = @{
            identity = @{
                sourceIp = "127.0.0.1"
                userAgent = "test-script"
            }
        }
    } | ConvertTo-Json -Depth 3

    Write-Host "Invoking operations Lambda directly..."
    
    $operationsLambdaResponse = aws lambda invoke --function-name "rds-operations-prod" --payload $operationsLambdaPayload --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json | ConvertFrom-Json
        Write-Host "Operations Lambda Response: $($responseContent | ConvertTo-Json -Depth 3)" -ForegroundColor Green
        
        # Clean up
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Operations Lambda invocation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Operations Lambda Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Check Lambda Function Status
Write-Host "`nTest 5: Checking Lambda Function Status" -ForegroundColor Yellow

try {
    Write-Host "Discovery Lambda Status:"
    aws lambda get-function --function-name "rds-discovery-prod" --query 'Configuration.{State:State,LastModified:LastModified,Runtime:Runtime,Timeout:Timeout}' --output table
    
    Write-Host "`nOperations Lambda Status:"
    aws lambda get-function --function-name "rds-operations-prod" --query 'Configuration.{State:State,LastModified:LastModified,Runtime:Runtime,Timeout:Timeout}' --output table
    
    Write-Host "`nBFF Lambda Status:"
    aws lambda get-function --function-name "rds-dashboard-bff-prod" --query 'Configuration.{State:State,LastModified:LastModified,Runtime:Runtime,Timeout:Timeout}' --output table
    
} catch {
    Write-Host "Lambda status check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Check Recent Lambda Logs
Write-Host "`nTest 6: Checking Recent Lambda Logs" -ForegroundColor Yellow

try {
    Write-Host "Recent Discovery Lambda Logs:"
    aws logs describe-log-streams --log-group-name "/aws/lambda/rds-discovery-prod" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text | ForEach-Object {
        if ($_) {
            aws logs get-log-events --log-group-name "/aws/lambda/rds-discovery-prod" --log-stream-name $_ --limit 5 --query 'events[*].message' --output text
        }
    }
    
    Write-Host "`nRecent Operations Lambda Logs:"
    aws logs describe-log-streams --log-group-name "/aws/lambda/rds-operations-prod" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text | ForEach-Object {
        if ($_) {
            aws logs get-log-events --log-group-name "/aws/lambda/rds-operations-prod" --log-stream-name $_ --limit 5 --query 'events[*].message' --output text
        }
    }
    
} catch {
    Write-Host "Log check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nDirect Testing Complete!" -ForegroundColor Cyan
Write-Host "Check the output above to identify specific issues with operations and discovery." -ForegroundColor Yellow