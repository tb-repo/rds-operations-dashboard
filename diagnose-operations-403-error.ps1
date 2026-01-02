#!/usr/bin/env pwsh

<#
.SYNOPSIS
Diagnose the 403 error on the operations endpoint

.DESCRIPTION
This script investigates the root cause of the 403 Forbidden error on the /api/operations endpoint.
It checks authentication flow, user permissions, and Lambda configuration.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-20T14:45:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-2.2, 2.3, 2.4 → DESIGN-OperationsAuth → TASK-3",
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
    [string]$UserPoolId = $env:COGNITO_USER_POOL_ID,
    [string]$Username = $env:TEST_USERNAME,
    [switch]$Verbose
)

Write-Host "🔍 Diagnosing Operations 403 Error" -ForegroundColor Cyan
Write-Host "=" * 50

# Check required parameters
if (-not $ApiKey) {
    Write-Host "❌ API_KEY environment variable not set" -ForegroundColor Red
    Write-Host "Please set API_KEY environment variable or pass -ApiKey parameter"
    exit 1
}

if (-not $AuthToken) {
    Write-Host "⚠️  AUTH_TOKEN not set - will test without authentication" -ForegroundColor Yellow
}

$headers = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

if ($AuthToken) {
    $headers['Authorization'] = "Bearer $AuthToken"
}

Write-Host "🔍 Step 1: Check Operations Lambda Logs" -ForegroundColor Green

try {
    Write-Host "Checking recent Lambda logs for operations function..." -ForegroundColor Gray
    
    # Get recent logs from operations Lambda
    $logGroups = @(
        "/aws/lambda/rds-operations",
        "/aws/lambda/rds-ops-operations",
        "/aws/lambda/operations"
    )
    
    foreach ($logGroup in $logGroups) {
        try {
            $logStreams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 2>$null | ConvertFrom-Json
            
            if ($logStreams.logStreams.Count -gt 0) {
                Write-Host "✅ Found log group: $logGroup" -ForegroundColor Green
                
                $latestStream = $logStreams.logStreams[0].logStreamName
                Write-Host "   Latest stream: $latestStream" -ForegroundColor Gray
                
                # Get recent log events
                $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $latestStream --limit 10 2>$null | ConvertFrom-Json
                
                if ($events.events.Count -gt 0) {
                    Write-Host "   Recent log entries:" -ForegroundColor Gray
                    foreach ($event in $events.events | Select-Object -Last 3) {
                        $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($event.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
                        Write-Host "   [$timestamp] $($event.message)" -ForegroundColor DarkGray
                    }
                }
                break
            }
        } catch {
            if ($Verbose) {
                Write-Host "   Log group $logGroup not found or inaccessible" -ForegroundColor DarkGray
            }
        }
    }
} catch {
    Write-Host "❌ Error checking Lambda logs: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "🔍 Step 2: Test Direct API Gateway Operations Endpoint" -ForegroundColor Green

try {
    $testPayload = @{
        operation_type = "create_snapshot"
        instance_id = "test-instance"
        parameters = @{
            snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        user_id = "test-user"
        user_groups = @("Admin")
        user_permissions = @("execute_operations")
        requested_by = "test@example.com"
    } | ConvertTo-Json -Depth 3

    Write-Host "Testing direct API Gateway call..." -ForegroundColor Gray
    Write-Host "Payload: $testPayload" -ForegroundColor DarkGray
    
    $response = Invoke-RestMethod -Uri "$ApiUrl/operations" -Method POST -Headers $headers -Body $testPayload -TimeoutSec 10
    Write-Host "✅ Direct API Gateway call succeeded" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Direct API Gateway call failed" -ForegroundColor Red
    Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response.StatusCode -eq 403) {
        Write-Host "   🚨 Confirmed 403 error - authorization issue" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🔍 Step 3: Test BFF Operations Endpoint" -ForegroundColor Green

if ($AuthToken) {
    try {
        $testPayload = @{
            operation_type = "create_snapshot"
            instance_id = "test-instance"
            parameters = @{
                snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
        } | ConvertTo-Json -Depth 3

        Write-Host "Testing BFF endpoint with JWT token..." -ForegroundColor Gray
        
        $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $testPayload -TimeoutSec 10
        Write-Host "✅ BFF operations call succeeded" -ForegroundColor Green
        Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
    } catch {
        Write-Host "❌ BFF operations call failed" -ForegroundColor Red
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Host "   🚨 BFF also returns 403 - issue is in authentication/authorization" -ForegroundColor Red
        }
    }
} else {
    Write-Host "⚠️  Skipping BFF test - no AUTH_TOKEN provided" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔍 Step 4: Check User Cognito Groups" -ForegroundColor Green

if ($UserPoolId -and $Username) {
    try {
        Write-Host "Checking Cognito groups for user: $Username" -ForegroundColor Gray
        
        $userGroups = aws cognito-idp admin-list-groups-for-user --user-pool-id $UserPoolId --username $Username 2>$null | ConvertFrom-Json
        
        if ($userGroups.Groups.Count -gt 0) {
            Write-Host "✅ User groups found:" -ForegroundColor Green
            foreach ($group in $userGroups.Groups) {
                Write-Host "   - $($group.GroupName): $($group.Description)" -ForegroundColor Gray
            }
            
            $hasAdminAccess = $userGroups.Groups | Where-Object { $_.GroupName -in @("Admin", "DBA") }
            if ($hasAdminAccess) {
                Write-Host "✅ User has admin access (Admin or DBA group)" -ForegroundColor Green
            } else {
                Write-Host "❌ User does NOT have admin access - missing Admin or DBA group" -ForegroundColor Red
                Write-Host "   This could be the cause of the 403 error for production operations" -ForegroundColor Red
            }
        } else {
            Write-Host "❌ No groups found for user" -ForegroundColor Red
            Write-Host "   User needs to be in Admin or DBA group for operations" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Error checking user groups: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  Skipping user groups check - COGNITO_USER_POOL_ID or TEST_USERNAME not set" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔍 Step 5: Decode JWT Token (if available)" -ForegroundColor Green

if ($AuthToken) {
    try {
        # Decode JWT token (just the payload, not verifying signature)
        $tokenParts = $AuthToken.Split('.')
        if ($tokenParts.Length -eq 3) {
            # Decode the payload (second part)
            $payload = $tokenParts[1]
            
            # Add padding if needed for base64 decoding
            while ($payload.Length % 4 -ne 0) {
                $payload += "="
            }
            
            $decodedBytes = [System.Convert]::FromBase64String($payload)
            $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
            $tokenData = $decodedJson | ConvertFrom-Json
            
            Write-Host "✅ JWT Token decoded successfully:" -ForegroundColor Green
            Write-Host "   Subject: $($tokenData.sub)" -ForegroundColor Gray
            Write-Host "   Email: $($tokenData.email)" -ForegroundColor Gray
            Write-Host "   Groups: $($tokenData.'cognito:groups' -join ', ')" -ForegroundColor Gray
            Write-Host "   Token Use: $($tokenData.token_use)" -ForegroundColor Gray
            Write-Host "   Expires: $(([DateTimeOffset]::FromUnixTimeSeconds($tokenData.exp)).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
            
            # Check if token is expired
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if ($tokenData.exp -lt $now) {
                Write-Host "❌ Token is EXPIRED" -ForegroundColor Red
                Write-Host "   This is likely the cause of the 403 error" -ForegroundColor Red
            } else {
                Write-Host "✅ Token is still valid" -ForegroundColor Green
            }
            
            # Check groups
            $groups = $tokenData.'cognito:groups'
            if ($groups -and ($groups -contains "Admin" -or $groups -contains "DBA")) {
                Write-Host "✅ Token contains required groups (Admin or DBA)" -ForegroundColor Green
            } else {
                Write-Host "❌ Token does NOT contain required groups (Admin or DBA)" -ForegroundColor Red
                Write-Host "   Current groups: $($groups -join ', ')" -ForegroundColor Red
                Write-Host "   This is likely the cause of the 403 error" -ForegroundColor Red
            }
        } else {
            Write-Host "❌ Invalid JWT token format" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Error decoding JWT token: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  No JWT token to decode" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔍 Step 6: Check Operations Lambda Configuration" -ForegroundColor Green

try {
    Write-Host "Checking operations Lambda function configuration..." -ForegroundColor Gray
    
    $lambdaFunctions = @(
        "rds-operations",
        "rds-ops-operations", 
        "operations"
    )
    
    foreach ($functionName in $lambdaFunctions) {
        try {
            $functionConfig = aws lambda get-function --function-name $functionName 2>$null | ConvertFrom-Json
            
            if ($functionConfig) {
                Write-Host "✅ Found Lambda function: $functionName" -ForegroundColor Green
                Write-Host "   Runtime: $($functionConfig.Configuration.Runtime)" -ForegroundColor Gray
                Write-Host "   Handler: $($functionConfig.Configuration.Handler)" -ForegroundColor Gray
                Write-Host "   Timeout: $($functionConfig.Configuration.Timeout)s" -ForegroundColor Gray
                Write-Host "   Memory: $($functionConfig.Configuration.MemorySize)MB" -ForegroundColor Gray
                
                # Check environment variables
                $envVars = $functionConfig.Configuration.Environment.Variables
                if ($envVars) {
                    Write-Host "   Environment variables:" -ForegroundColor Gray
                    if ($envVars.ENABLE_PRODUCTION_OPERATIONS) {
                        Write-Host "     ENABLE_PRODUCTION_OPERATIONS: $($envVars.ENABLE_PRODUCTION_OPERATIONS)" -ForegroundColor Gray
                    }
                    if ($envVars.AUDIT_LOG_TABLE) {
                        Write-Host "     AUDIT_LOG_TABLE: $($envVars.AUDIT_LOG_TABLE)" -ForegroundColor Gray
                    }
                }
                break
            }
        } catch {
            if ($Verbose) {
                Write-Host "   Function $functionName not found" -ForegroundColor DarkGray
            }
        }
    }
} catch {
    Write-Host "❌ Error checking Lambda configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "📊 Diagnosis Summary" -ForegroundColor Cyan
Write-Host "=" * 50

Write-Host "Based on the analysis, the 403 error is likely caused by:"
Write-Host ""
Write-Host "🔍 Most Likely Causes:" -ForegroundColor Yellow
Write-Host "1. User not in required Cognito groups (Admin or DBA)"
Write-Host "2. JWT token expired or invalid"
Write-Host "3. Missing 'confirm_production: true' parameter for risky operations"
Write-Host "4. Authentication middleware rejecting the token"
Write-Host ""
Write-Host "🔧 Recommended Fixes:" -ForegroundColor Green
Write-Host "1. Add user to Admin or DBA Cognito group:"
Write-Host "   aws cognito-idp admin-add-user-to-group --user-pool-id <pool-id> --username <username> --group-name Admin"
Write-Host ""
Write-Host "2. Refresh JWT token in frontend application"
Write-Host ""
Write-Host "3. For risky operations, include confirm_production parameter:"
Write-Host "   { ""operation_type"": ""reboot"", ""parameters"": { ""confirm_production"": true } }"
Write-Host ""
Write-Host "4. Check CloudWatch logs for specific error messages:"
Write-Host "   aws logs tail /aws/lambda/rds-operations --follow"
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Fix user permissions (add to Admin/DBA group)"
Write-Host "2. Test with fresh JWT token"
Write-Host "3. Monitor Lambda logs during testing"
Write-Host "4. Implement better error messages in operations Lambda"