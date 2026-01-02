#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test the operations 403 error fix

.DESCRIPTION
This script tests the fixed operations endpoint to ensure 403 errors are resolved.
It validates authentication, authorization, and proper error handling.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-20T15:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-2.2, 2.3, 2.4, 2.5 → DESIGN-OperationsAuth → TASK-3",
  "review_status": "Pending",
  "risk_level": "Level 1",
  "reviewed_by": null,
  "approved_by": null
}
#>

param(
    [string]$BffUrl = "https://your-bff-domain.com",
    [string]$ApiUrl = "https://your-api-gateway-url.com/prod",
    [string]$ApiKey = $env:API_KEY,
    [string]$AuthToken = $env:AUTH_TOKEN,
    [string]$TestInstanceId = "test-instance-1",
    [switch]$TestAllOperations
)

Write-Host "🧪 Testing Operations 403 Error Fix" -ForegroundColor Cyan
Write-Host "=" * 50

# Check required parameters
if (-not $ApiKey) {
    Write-Host "❌ API_KEY environment variable not set" -ForegroundColor Red
    Write-Host "Please set API_KEY environment variable or pass -ApiKey parameter"
    exit 1
}

if (-not $AuthToken) {
    Write-Host "⚠️  AUTH_TOKEN not set - some tests may fail" -ForegroundColor Yellow
}

$headers = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

if ($AuthToken) {
    $headers['Authorization'] = "Bearer $AuthToken"
}

Write-Host "🔍 Test 1: Safe Operations (No Admin Required)" -ForegroundColor Green

$safeOperations = @(
    @{
        operation = "create_snapshot"
        parameters = @{
            snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
    },
    @{
        operation = "modify_backup_window"
        parameters = @{
            backup_window = "03:00-04:00"
            apply_immediately = $true
        }
    },
    @{
        operation = "enable_storage_autoscaling"
        parameters = @{
            max_allocated_storage = 1000
            apply_immediately = $true
        }
    }
)

foreach ($testOp in $safeOperations) {
    Write-Host "Testing safe operation: $($testOp.operation)" -ForegroundColor Gray
    
    $payload = @{
        operation_type = $testOp.operation
        instance_id = $TestInstanceId
        parameters = $testOp.parameters
    } | ConvertTo-Json -Depth 3
    
    try {
        $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $payload -TimeoutSec 10
        Write-Host "✅ $($testOp.operation) - Success (or expected failure for test instance)" -ForegroundColor Green
        
        if ($response.error -and $response.error -like "*not found*") {
            Write-Host "   ℹ️  Test instance not found (expected for test)" -ForegroundColor Blue
        } elseif ($response.success -eq $false -and $response.error) {
            Write-Host "   ⚠️  Operation failed: $($response.error)" -ForegroundColor Yellow
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        if ($statusCode -eq 403) {
            Write-Host "❌ $($testOp.operation) - Still getting 403 error" -ForegroundColor Red
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        } elseif ($statusCode -eq 404) {
            Write-Host "✅ $($testOp.operation) - 404 (test instance not found, auth working)" -ForegroundColor Green
        } else {
            Write-Host "⚠️  $($testOp.operation) - Status: $statusCode" -ForegroundColor Yellow
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "🔍 Test 2: Risky Operations (Admin Required)" -ForegroundColor Green

$riskyOperations = @(
    @{
        operation = "reboot_instance"
        parameters = @{
            force_failover = $false
            confirm_production = $true
        }
    },
    @{
        operation = "stop_instance"
        parameters = @{
            confirm_production = $true
        }
    },
    @{
        operation = "start_instance"
        parameters = @{}
    }
)

foreach ($testOp in $riskyOperations) {
    Write-Host "Testing risky operation: $($testOp.operation)" -ForegroundColor Gray
    
    $payload = @{
        operation_type = $testOp.operation
        instance_id = $TestInstanceId
        parameters = $testOp.parameters
    } | ConvertTo-Json -Depth 3
    
    try {
        $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $payload -TimeoutSec 10
        Write-Host "✅ $($testOp.operation) - Success (or expected failure for test instance)" -ForegroundColor Green
        
        if ($response.error -and $response.error -like "*not found*") {
            Write-Host "   ℹ️  Test instance not found (expected for test)" -ForegroundColor Blue
        } elseif ($response.success -eq $false -and $response.error) {
            Write-Host "   ⚠️  Operation failed: $($response.error)" -ForegroundColor Yellow
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        if ($statusCode -eq 403) {
            # Parse the error message to understand why
            try {
                $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = $errorResponse.error
                
                if ($errorMessage -like "*admin privileges*") {
                    Write-Host "❌ $($testOp.operation) - User lacks admin privileges" -ForegroundColor Red
                    Write-Host "   This is expected if user is not in Admin/DBA group" -ForegroundColor Yellow
                } elseif ($errorMessage -like "*confirm_production*") {
                    Write-Host "❌ $($testOp.operation) - Missing production confirmation" -ForegroundColor Red
                    Write-Host "   This should not happen as we included confirm_production" -ForegroundColor Red
                } else {
                    Write-Host "❌ $($testOp.operation) - Other 403 error: $errorMessage" -ForegroundColor Red
                }
            } catch {
                Write-Host "❌ $($testOp.operation) - 403 error (unable to parse details)" -ForegroundColor Red
            }
        } elseif ($statusCode -eq 404) {
            Write-Host "✅ $($testOp.operation) - 404 (test instance not found, auth working)" -ForegroundColor Green
        } else {
            Write-Host "⚠️  $($testOp.operation) - Status: $statusCode" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "🔍 Test 3: Invalid Operations (Should Return 400)" -ForegroundColor Green

$invalidOperations = @(
    @{
        operation = "invalid_operation"
        parameters = @{}
        expectedError = "not supported"
    },
    @{
        operation = "create_snapshot"
        parameters = @{}  # Missing snapshot_id
        expectedError = "required"
    },
    @{
        operation = ""
        parameters = @{}
        expectedError = "required"
    }
)

foreach ($testOp in $invalidOperations) {
    Write-Host "Testing invalid operation: '$($testOp.operation)'" -ForegroundColor Gray
    
    $payload = @{
        operation_type = $testOp.operation
        instance_id = $TestInstanceId
        parameters = $testOp.parameters
    } | ConvertTo-Json -Depth 3
    
    try {
        $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $payload -TimeoutSec 10
        Write-Host "⚠️  Expected error but got success: $($response | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        if ($statusCode -eq 400) {
            Write-Host "✅ Correctly returned 400 for invalid operation" -ForegroundColor Green
        } elseif ($statusCode -eq 403) {
            Write-Host "❌ Still getting 403 instead of 400 for validation error" -ForegroundColor Red
        } else {
            Write-Host "⚠️  Unexpected status: $statusCode" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "🔍 Test 4: Authentication Test (No Token)" -ForegroundColor Green

$noAuthHeaders = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

$payload = @{
    operation_type = "create_snapshot"
    instance_id = $TestInstanceId
    parameters = @{
        snapshot_id = "test-snapshot"
    }
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $noAuthHeaders -Body $payload -TimeoutSec 10
    Write-Host "❌ Expected 401 but got success - authentication not working" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    if ($statusCode -eq 401) {
        Write-Host "✅ Correctly returned 401 for missing authentication" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Expected 401 but got $statusCode" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "🔍 Test 5: Direct API Gateway Test (Bypass BFF)" -ForegroundColor Green

$directPayload = @{
    operation_type = "create_snapshot"
    instance_id = $TestInstanceId
    parameters = @{
        snapshot_id = "test-snapshot-direct"
    }
    user_id = "test-user"
    user_groups = @("Admin")
    user_permissions = @("execute_operations")
    requested_by = "test@example.com"
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/operations" -Method POST -Headers @{'x-api-key' = $ApiKey; 'Content-Type' = 'application/json'} -Body $directPayload -TimeoutSec 10
    Write-Host "✅ Direct API Gateway call succeeded" -ForegroundColor Green
    
    if ($response.error -and $response.error -like "*not found*") {
        Write-Host "   ℹ️  Test instance not found (expected)" -ForegroundColor Blue
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    if ($statusCode -eq 403) {
        Write-Host "❌ Direct API Gateway still returns 403" -ForegroundColor Red
        Write-Host "   This indicates the issue is in the Lambda function itself" -ForegroundColor Red
    } else {
        Write-Host "⚠️  Direct API Gateway returned: $statusCode" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "📊 Test Summary" -ForegroundColor Cyan
Write-Host "=" * 50

Write-Host "✅ Tests completed. Key findings:" -ForegroundColor Green
Write-Host ""
Write-Host "🔍 If you see:" -ForegroundColor Yellow
Write-Host "• ✅ 404 errors: Authentication is working, test instance doesn't exist"
Write-Host "• ✅ 400 errors: Validation is working correctly"
Write-Host "• ✅ 401 errors: Authentication middleware is working"
Write-Host "• ❌ 403 errors: Still have authorization issues"
Write-Host ""
Write-Host "🔧 Common fixes for remaining 403 errors:" -ForegroundColor Cyan
Write-Host "1. User not in Admin or DBA Cognito group"
Write-Host "2. JWT token expired or invalid"
Write-Host "3. Missing confirm_production parameter for risky operations"
Write-Host "4. Operations Lambda not receiving user context correctly"
Write-Host ""
Write-Host "🎯 Next steps if 403 errors persist:" -ForegroundColor Yellow
Write-Host "1. Check CloudWatch logs: aws logs tail /aws/lambda/rds-operations --follow"
Write-Host "2. Verify user groups: aws cognito-idp admin-list-groups-for-user --user-pool-id <pool> --username <user>"
Write-Host "3. Add user to Admin group: aws cognito-idp admin-add-user-to-group --user-pool-id <pool> --username <user> --group-name Admin"
Write-Host "4. Test with fresh JWT token from the dashboard login"

Write-Host ""
Write-Host "✅ Operations 403 Error Testing Complete!" -ForegroundColor Green