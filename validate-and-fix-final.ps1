#!/usr/bin/env pwsh
# Final Validation and Fix Script for Critical Issues
# This script validates the current system status and applies any necessary fixes

Write-Host "=== RDS Dashboard - Final Validation and Fix ===" -ForegroundColor Green
Write-Host ""

# Configuration
$apiKey = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
$apiUrl = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
$bffUrl = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$userEmail = "itthiagu@gmail.com"

$results = @{
    backend_health = $false
    bff_health = $false
    instances_endpoint = $false
    discovery_endpoint = $false
    operations_ready = $false
}

# Function to test endpoint with timeout
function Test-Endpoint {
    param(
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$Description,
        [int]$TimeoutSec = 10
    )
    
    Write-Host "Testing $Description..." -ForegroundColor Yellow
    
    try {
        $response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method GET -TimeoutSec $TimeoutSec -ErrorAction Stop
        Write-Host "[OK] $Description" -ForegroundColor Green
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Host "[FAIL] $Description - HTTP $statusCode" -ForegroundColor Red
        } else {
            Write-Host "[FAIL] $Description - $errorMsg" -ForegroundColor Red
        }
        return $false
    }
}

Write-Host "=== Phase 1: System Status Validation ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Backend API Health
$results.backend_health = Test-Endpoint -Url "$apiUrl/health" -Headers @{"x-api-key"=$apiKey} -Description "Backend API Health"

# Test 2: BFF Health
$results.bff_health = Test-Endpoint -Url "$bffUrl/health" -Description "BFF Health"

# Test 3: Instances Endpoint
$results.instances_endpoint = Test-Endpoint -Url "$apiUrl/instances" -Headers @{"x-api-key"=$apiKey} -Description "Instances Endpoint"

# Test 4: Discovery Endpoint
$results.discovery_endpoint = Test-Endpoint -Url "$apiUrl/discovery" -Headers @{"x-api-key"=$apiKey} -Description "Discovery Endpoint"

Write-Host ""
Write-Host "=== Phase 2: Lambda Function Status ===" -ForegroundColor Cyan
Write-Host ""

# Check Lambda function status
$lambdaFunctions = @(
    "rds-dashboard-bff",
    "rds-health-monitor",
    "rds-discovery",
    "rds-operations"
)

foreach ($function in $lambdaFunctions) {
    Write-Host "Checking $function..." -ForegroundColor Yellow
    try {
        $functionInfo = aws lambda get-function --function-name $function --output json 2>&1 | ConvertFrom-Json
        if ($functionInfo.Configuration) {
            $state = $functionInfo.Configuration.State
            $lastModified = $functionInfo.Configuration.LastModified
            Write-Host "[OK] $function - State: $state, Last Modified: $lastModified" -ForegroundColor Green
        }
    } catch {
        Write-Host "[FAIL] $function - Not found or inaccessible" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Phase 3: User Context Validation ===" -ForegroundColor Cyan
Write-Host ""

# Check user's Cognito groups
Write-Host "Checking Cognito user groups for $userEmail..." -ForegroundColor Yellow
try {
    $userPoolId = "ap-southeast-1_4tyxh4qJe"
    $username = $userEmail
    
    $userGroups = aws cognito-idp admin-list-groups-for-user --user-pool-id $userPoolId --username $username --output json 2>&1 | ConvertFrom-Json
    
    if ($userGroups.Groups) {
        $groupNames = $userGroups.Groups | ForEach-Object { $_.GroupName }
        Write-Host "[OK] User groups: $($groupNames -join ', ')" -ForegroundColor Green
        
        $hasAdmin = $groupNames -contains "Admin"
        $hasDBA = $groupNames -contains "DBA"
        
        if ($hasAdmin -or $hasDBA) {
            Write-Host "[OK] User has required privileges (Admin or DBA)" -ForegroundColor Green
            $results.operations_ready = $true
        } else {
            Write-Host "[WARN] User does not have Admin or DBA privileges" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN] No groups found for user" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[FAIL] Could not check user groups: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Phase 4: Configuration Validation ===" -ForegroundColor Cyan
Write-Host ""

# Check BFF Lambda environment variables
Write-Host "Checking BFF Lambda configuration..." -ForegroundColor Yellow
try {
    $bffConfig = aws lambda get-function-configuration --function-name "rds-dashboard-bff" --output json 2>&1 | ConvertFrom-Json
    
    if ($bffConfig.Environment.Variables) {
        $envVars = $bffConfig.Environment.Variables
        
        $hasApiKey = $envVars.INTERNAL_API_KEY -ne $null
        $hasApiUrl = $envVars.INTERNAL_API_URL -ne $null
        $hasProductionOps = $envVars.ENABLE_PRODUCTION_OPERATIONS -eq "true"
        
        Write-Host "  INTERNAL_API_KEY: $(if($hasApiKey){'[SET]'}else{'[MISSING]'})" -ForegroundColor $(if($hasApiKey){'Green'}else{'Red'})
        Write-Host "  INTERNAL_API_URL: $(if($hasApiUrl){'[SET]'}else{'[MISSING]'})" -ForegroundColor $(if($hasApiUrl){'Green'}else{'Red'})
        Write-Host "  ENABLE_PRODUCTION_OPERATIONS: $(if($hasProductionOps){'[ENABLED]'}else{'[DISABLED]'})" -ForegroundColor $(if($hasProductionOps){'Green'}else{'Yellow'})
        
        if (-not $hasApiKey) {
            Write-Host "[ACTION NEEDED] BFF is missing INTERNAL_API_KEY" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "[FAIL] Could not check BFF configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Phase 5: Applying Fixes (if needed) ===" -ForegroundColor Cyan
Write-Host ""

# Fix 1: Update BFF environment variables if needed
if (-not $results.bff_health -or -not $results.backend_health) {
    Write-Host "Applying BFF configuration fix..." -ForegroundColor Yellow
    
    $envVars = @{
        "PORT" = "8080"
        "INTERNAL_API_URL" = $apiUrl
        "INTERNAL_API_KEY" = $apiKey
        "COGNITO_USER_POOL_ID" = "ap-southeast-1_4tyxh4qJe"
        "COGNITO_REGION" = "ap-southeast-1"
        "COGNITO_CLIENT_ID" = "28e031hsul0mi91k0s6f33bs7s"
        "FRONTEND_URL" = "*"
        "ENABLE_PRODUCTION_OPERATIONS" = "true"
        "ENABLE_AUDIT_LOGGING" = "true"
        "NODE_ENV" = "production"
        "LOG_LEVEL" = "info"
        "API_SECRET_ARN" = "arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-vWyaxH"
        "AUDIT_LOG_GROUP" = "/aws/rds-dashboard/audit"
    }
    
    $envJson = $envVars | ConvertTo-Json -Compress
    
    try {
        aws lambda update-function-configuration `
            --function-name "rds-dashboard-bff" `
            --environment "Variables=$envJson" `
            --output json | Out-Null
        Write-Host "[OK] BFF configuration updated" -ForegroundColor Green
        Write-Host "[INFO] Waiting 10 seconds for changes to propagate..." -ForegroundColor Cyan
        Start-Sleep -Seconds 10
    } catch {
        Write-Host "[FAIL] Could not update BFF configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Fix 2: Trigger discovery if discovery endpoint is working
if ($results.discovery_endpoint) {
    Write-Host "Triggering discovery scan..." -ForegroundColor Yellow
    
    try {
        $discoveryPayload = @{
            "trigger_type" = "manual"
            "scan_all_regions" = $true
            "force_refresh" = $true
        } | ConvertTo-Json
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $discoveryPayload | Out-File -FilePath $tempFile -Encoding utf8
        
        aws lambda invoke `
            --function-name "rds-discovery" `
            --payload "file://$tempFile" `
            --output json discovery-result.json | Out-Null
        
        Remove-Item $tempFile -Force
        
        if (Test-Path discovery-result.json) {
            $discoveryResult = Get-Content discovery-result.json | ConvertFrom-Json
            Remove-Item discovery-result.json -Force
            
            if ($discoveryResult.statusCode -eq 200) {
                Write-Host "[OK] Discovery scan triggered successfully" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Discovery scan may have issues - check logs" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "[FAIL] Could not trigger discovery: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Phase 6: Final Validation ===" -ForegroundColor Cyan
Write-Host ""

# Wait a moment for changes to propagate
Start-Sleep -Seconds 5

# Re-test critical endpoints
Write-Host "Re-testing critical endpoints..." -ForegroundColor Yellow

$finalResults = @{
    backend_health = Test-Endpoint -Url "$apiUrl/health" -Headers @{"x-api-key"=$apiKey} -Description "Backend API Health (Final)"
    bff_health = Test-Endpoint -Url "$bffUrl/health" -Description "BFF Health (Final)"
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Green
Write-Host ""

Write-Host "Initial Status:" -ForegroundColor Yellow
Write-Host "  Backend API: $(if($results.backend_health){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($results.backend_health){'Green'}else{'Red'})
Write-Host "  BFF API: $(if($results.bff_health){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($results.bff_health){'Green'}else{'Red'})
Write-Host "  Instances Endpoint: $(if($results.instances_endpoint){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($results.instances_endpoint){'Green'}else{'Red'})
Write-Host "  Discovery Endpoint: $(if($results.discovery_endpoint){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($results.discovery_endpoint){'Green'}else{'Red'})
Write-Host "  Operations Ready: $(if($results.operations_ready){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($results.operations_ready){'Green'}else{'Red'})

Write-Host ""
Write-Host "Final Status:" -ForegroundColor Yellow
Write-Host "  Backend API: $(if($finalResults.backend_health){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($finalResults.backend_health){'Green'}else{'Red'})
Write-Host "  BFF API: $(if($finalResults.bff_health){'[OK]'}else{'[FAIL]'})" -ForegroundColor $(if($finalResults.bff_health){'Green'}else{'Red'})

Write-Host ""
Write-Host "=== Next Steps for User ===" -ForegroundColor Green
Write-Host ""

if ($finalResults.backend_health -and $finalResults.bff_health) {
    Write-Host "[SUCCESS] System is operational!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Please follow these steps:" -ForegroundColor Cyan
    Write-Host "1. Close ALL browser tabs with the dashboard" -ForegroundColor White
    Write-Host "2. Clear browser cache completely (Ctrl+Shift+Delete)" -ForegroundColor White
    Write-Host "   - Select 'All time' for time range" -ForegroundColor Gray
    Write-Host "   - Check 'Cached images and files'" -ForegroundColor Gray
    Write-Host "   - Check 'Cookies and other site data'" -ForegroundColor Gray
    Write-Host "3. Close and reopen your browser" -ForegroundColor White
    Write-Host "4. Log in to the dashboard with: $userEmail" -ForegroundColor White
    Write-Host "5. Test the following features:" -ForegroundColor White
    Write-Host "   - Dashboard should load without 500 errors" -ForegroundColor Gray
    Write-Host "   - Discovery button should work" -ForegroundColor Gray
    Write-Host "   - Instance operations should be available" -ForegroundColor Gray
    Write-Host ""
    Write-Host "If issues persist after cache clearing:" -ForegroundColor Yellow
    Write-Host "- Try incognito/private browsing mode" -ForegroundColor Gray
    Write-Host "- Check browser console for specific errors (F12)" -ForegroundColor Gray
    Write-Host "- Wait 5-10 minutes for Lambda changes to fully propagate" -ForegroundColor Gray
} else {
    Write-Host "[WARN] Some issues detected" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Cyan
    Write-Host "1. Check CloudWatch logs for errors:" -ForegroundColor White
    Write-Host "   aws logs tail /aws/lambda/rds-dashboard-bff --follow" -ForegroundColor Gray
    Write-Host "   aws logs tail /aws/lambda/rds-health-monitor --follow" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Verify API Gateway deployments:" -ForegroundColor White
    Write-Host "   - BFF API: $bffUrl" -ForegroundColor Gray
    Write-Host "   - Backend API: $apiUrl" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Check Lambda function status in AWS Console" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Verify DynamoDB tables are accessible" -ForegroundColor White
}

Write-Host ""
Write-Host "=== Validation Complete ===" -ForegroundColor Green
Write-Host ""