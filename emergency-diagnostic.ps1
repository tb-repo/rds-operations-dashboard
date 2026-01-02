#!/usr/bin/env pwsh
# Emergency Diagnostic Script - Find Real Issues
# This script will identify what's actually broken

Write-Host "=== EMERGENCY DIAGNOSTIC - FINDING REAL ISSUES ===" -ForegroundColor Red
Write-Host ""

$issues = @()
$apiKey = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
$apiUrl = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
$bffUrl = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"

# Function to test with short timeout
function Test-QuickEndpoint {
    param([string]$Url, [hashtable]$Headers = @{}, [string]$Name)
    
    Write-Host "Testing $Name..." -NoNewline
    try {
        $response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method GET -TimeoutSec 5 -ErrorAction Stop
        Write-Host " [OK]" -ForegroundColor Green
        return $true
    } catch {
        Write-Host " [FAIL] - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "=== PHASE 1: BASIC CONNECTIVITY ===" -ForegroundColor Yellow

# Test 1: Can we reach the APIs at all?
$backendReachable = Test-QuickEndpoint -Url "$apiUrl/health" -Headers @{"x-api-key"=$apiKey} -Name "Backend API"
$bffReachable = Test-QuickEndpoint -Url "$bffUrl/health" -Name "BFF API"

if (-not $backendReachable) { $issues += "Backend API unreachable or API key invalid" }
if (-not $bffReachable) { $issues += "BFF API unreachable" }

Write-Host ""
Write-Host "=== PHASE 2: LAMBDA FUNCTION STATUS ===" -ForegroundColor Yellow

# Check if Lambda functions exist and are active
$lambdas = @("rds-health-monitor", "rds-discovery", "rds-operations", "rds-dashboard-bff")

foreach ($lambda in $lambdas) {
    Write-Host "Checking $lambda..." -NoNewline
    try {
        $config = aws lambda get-function-configuration --function-name $lambda --output json 2>&1
        if ($config -match '"State"') {
            $configObj = $config | ConvertFrom-Json
            $state = $configObj.State
            if ($state -eq "Active") {
                Write-Host " [OK] Active" -ForegroundColor Green
            } else {
                Write-Host " [FAIL] State: $state" -ForegroundColor Red
                $issues += "$lambda is not Active (State: $state)"
            }
        } else {
            Write-Host " [FAIL] Not found" -ForegroundColor Red
            $issues += "$lambda function not found"
        }
    } catch {
        Write-Host " [FAIL] Error checking" -ForegroundColor Red
        $issues += "$lambda function check failed"
    }
}

Write-Host ""
Write-Host "=== PHASE 3: LAMBDA INVOCATION TEST ===" -ForegroundColor Yellow

# Test Lambda functions directly with minimal payload
foreach ($lambda in $lambdas) {
    Write-Host "Testing $lambda invocation..." -NoNewline
    try {
        $result = aws lambda invoke --function-name $lambda --payload '{}' --output json test-response.json 2>&1
        
        if (Test-Path test-response.json) {
            $response = Get-Content test-response.json | ConvertFrom-Json
            Remove-Item test-response.json -Force
            
            if ($result -match '"StatusCode": 200') {
                Write-Host " [OK]" -ForegroundColor Green
            } else {
                Write-Host " [FAIL] Non-200 response" -ForegroundColor Red
                $issues += "$lambda invocation failed"
            }
        } else {
            Write-Host " [FAIL] No response file" -ForegroundColor Red
            $issues += "$lambda invocation failed - no response"
        }
    } catch {
        Write-Host " [FAIL] Invocation error" -ForegroundColor Red
        $issues += "$lambda invocation error: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "=== PHASE 4: COGNITO USER CHECK ===" -ForegroundColor Yellow

# Check user groups
Write-Host "Checking user groups for itthiagu@gmail.com..." -NoNewline
try {
    $userGroups = aws cognito-idp admin-list-groups-for-user --user-pool-id "ap-southeast-1_4tyxh4qJe" --username "itthiagu@gmail.com" --output json 2>&1 | ConvertFrom-Json
    
    if ($userGroups.Groups) {
        $groupNames = $userGroups.Groups | ForEach-Object { $_.GroupName }
        Write-Host " [OK] Groups: $($groupNames -join ', ')" -ForegroundColor Green
        
        if (-not ($groupNames -contains "Admin" -or $groupNames -contains "DBA")) {
            $issues += "User does not have Admin or DBA group membership"
        }
    } else {
        Write-Host " [FAIL] No groups found" -ForegroundColor Red
        $issues += "User has no Cognito groups assigned"
    }
} catch {
    Write-Host " [FAIL] Cannot check groups" -ForegroundColor Red
    $issues += "Cannot verify user Cognito groups"
}

Write-Host ""
Write-Host "=== PHASE 5: DYNAMODB TABLE CHECK ===" -ForegroundColor Yellow

# Check if DynamoDB tables exist
$tables = @("rds-inventory-prod", "audit-log-prod", "metrics-cache-prod")

foreach ($table in $tables) {
    Write-Host "Checking table $table..." -NoNewline
    try {
        $tableInfo = aws dynamodb describe-table --table-name $table --output json 2>&1
        if ($tableInfo -match '"TableStatus"') {
            $tableObj = $tableInfo | ConvertFrom-Json
            $status = $tableObj.Table.TableStatus
            if ($status -eq "ACTIVE") {
                Write-Host " [OK] Active" -ForegroundColor Green
            } else {
                Write-Host " [FAIL] Status: $status" -ForegroundColor Red
                $issues += "DynamoDB table $table is not ACTIVE"
            }
        } else {
            Write-Host " [FAIL] Not found" -ForegroundColor Red
            $issues += "DynamoDB table $table not found"
        }
    } catch {
        Write-Host " [FAIL] Error checking" -ForegroundColor Red
        $issues += "Cannot check DynamoDB table $table"
    }
}

Write-Host ""
Write-Host "=== DIAGNOSTIC RESULTS ===" -ForegroundColor Red
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "[UNEXPECTED] No issues found, but user reported problems" -ForegroundColor Yellow
    Write-Host "This suggests the issues may be:"
    Write-Host "- Browser cache problems"
    Write-Host "- Frontend JavaScript errors"
    Write-Host "- Authentication/session issues"
    Write-Host "- Network connectivity from user's location"
} else {
    Write-Host "CRITICAL ISSUES IDENTIFIED:" -ForegroundColor Red
    for ($i = 0; $i -lt $issues.Count; $i++) {
        Write-Host "  $($i + 1). $($issues[$i])" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== NEXT STEPS ===" -ForegroundColor Yellow

if ($issues -contains "Backend API unreachable or API key invalid") {
    Write-Host "PRIORITY 1: Fix Backend API" -ForegroundColor Red
    Write-Host "- Check API Gateway deployment"
    Write-Host "- Verify API key is correct"
    Write-Host "- Check Lambda function permissions"
}

if ($issues | Where-Object { $_ -match "function not found" }) {
    Write-Host "PRIORITY 1: Deploy Missing Lambda Functions" -ForegroundColor Red
    Write-Host "- Run infrastructure deployment"
    Write-Host "- Check CDK/CloudFormation stacks"
}

if ($issues | Where-Object { $_ -match "not Active" }) {
    Write-Host "PRIORITY 2: Fix Lambda Function States" -ForegroundColor Red
    Write-Host "- Check CloudWatch logs for errors"
    Write-Host "- Redeploy Lambda functions"
    Write-Host "- Check IAM permissions"
}

if ($issues | Where-Object { $_ -match "DynamoDB" }) {
    Write-Host "PRIORITY 2: Fix DynamoDB Tables" -ForegroundColor Red
    Write-Host "- Deploy data stack"
    Write-Host "- Check table permissions"
}

if ($issues | Where-Object { $_ -match "Cognito" }) {
    Write-Host "PRIORITY 3: Fix User Permissions" -ForegroundColor Red
    Write-Host "- Add user to Admin or DBA group"
    Write-Host "- Verify Cognito configuration"
}

Write-Host ""
Write-Host "=== IMMEDIATE ACTION REQUIRED ===" -ForegroundColor Red
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "The system is NOT operational. Critical infrastructure issues detected." -ForegroundColor Red
    Write-Host "Browser cache clearing will NOT fix these issues." -ForegroundColor Red
    Write-Host ""
    Write-Host "Required actions:" -ForegroundColor Yellow
    Write-Host "1. Fix the infrastructure issues identified above" -ForegroundColor White
    Write-Host "2. Redeploy Lambda functions and API Gateway" -ForegroundColor White
    Write-Host "3. Verify DynamoDB tables are created and accessible" -ForegroundColor White
    Write-Host "4. Test again with this diagnostic script" -ForegroundColor White
} else {
    Write-Host "Infrastructure appears healthy. Issues may be:" -ForegroundColor Yellow
    Write-Host "1. Frontend/browser related" -ForegroundColor White
    Write-Host "2. Authentication/session problems" -ForegroundColor White
    Write-Host "3. Network connectivity from user location" -ForegroundColor White
    Write-Host "4. Clear browser cache and test in incognito mode" -ForegroundColor White
}

Write-Host ""
Write-Host "Diagnostic complete. Address issues in priority order." -ForegroundColor Green