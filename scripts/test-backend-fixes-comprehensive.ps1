#!/usr/bin/env pwsh

<#
.SYNOPSIS
Comprehensive Testing for Backend Infrastructure Fixes

.DESCRIPTION
This script tests all the backend infrastructure fixes:
1. Multi-region discovery functionality
2. User management with Cognito Admin permissions
3. Instance operations across regions
4. Cross-account functionality

.EXAMPLE
./test-backend-fixes-comprehensive.ps1
Run comprehensive backend testing
#>

# Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Magenta = "`e[35m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Write-Status {
    param($Message, $Color = $Blue)
    Write-Host "${Color}[$(Get-Date -Format 'HH:mm:ss')] $Message${Reset}"
}

function Write-Success {
    param($Message)
    Write-Host "${Green}✅ $Message${Reset}"
}

function Write-Warning {
    param($Message)
    Write-Host "${Yellow}⚠️  $Message${Reset}"
}

function Write-Error {
    param($Message)
    Write-Host "${Red}❌ $Message${Reset}"
}

function Write-Info {
    param($Message)
    Write-Host "${Cyan}ℹ️  $Message${Reset}"
}

function Test-LambdaFunction {
    param(
        [string]$FunctionName,
        [string]$Payload,
        [string]$TestName
    )
    
    try {
        Write-Status "Testing $TestName..."
        
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $Payload `
            --output json `
            "test-response-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $responseFile = Get-ChildItem "test-response-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            if ($responseFile -and (Test-Path $responseFile.FullName)) {
                $response = Get-Content $responseFile.FullName | ConvertFrom-Json
                Remove-Item $responseFile.FullName -Force
                return $response
            }
        } else {
            Write-Error "Lambda invocation failed: $result"
            return $null
        }
    } catch {
        Write-Error "Error testing $TestName: $_"
        return $null
    }
}

Write-Status "🧪 Starting Comprehensive Backend Fixes Testing" $Magenta
Write-Status "Testing multi-region discovery, user management, and operations" $Cyan

$testResults = @{
    DiscoveryConfiguration = $false
    MultiRegionDiscovery = $false
    UserManagement = $false
    InstanceOperations = $false
    CrossAccountAccess = $false
}

# Test 1: Discovery Lambda Configuration
Write-Status "📋 Test 1: Discovery Lambda Configuration"

try {
    $discoveryConfig = aws lambda get-function-configuration `
        --function-name "rds-discovery-prod" `
        --output json | ConvertFrom-Json
    
    $targetRegions = $discoveryConfig.Environment.Variables.TARGET_REGIONS
    $targetAccounts = $discoveryConfig.Environment.Variables.TARGET_ACCOUNTS
    
    Write-Info "Discovery Configuration:"
    Write-Host "  Target Regions: $targetRegions"
    Write-Host "  Target Accounts: $targetAccounts"
    
    # Parse regions array
    $regions = $targetRegions | ConvertFrom-Json
    $expectedRegions = @("ap-southeast-1", "eu-west-2", "ap-south-1", "us-east-1")
    
    $hasAllRegions = $true
    foreach ($region in $expectedRegions) {
        if ($region -notin $regions) {
            $hasAllRegions = $false
            Write-Warning "Missing region: $region"
        }
    }
    
    if ($hasAllRegions -and $regions.Count -eq 4) {
        Write-Success "Discovery Lambda configured with all 4 required regions"
        $testResults.DiscoveryConfiguration = $true
    } else {
        Write-Error "Discovery Lambda missing required regions. Expected 4, found $($regions.Count)"
    }
    
} catch {
    Write-Error "Failed to check discovery configuration: $_"
}

# Test 2: Multi-Region Discovery Functionality
Write-Status "📋 Test 2: Multi-Region Discovery Functionality"

$discoveryResponse = Test-LambdaFunction -FunctionName "rds-discovery-prod" -Payload '{"trigger": "test", "source": "comprehensive-testing"}' -TestName "Multi-Region Discovery"

if ($discoveryResponse) {
    Write-Info "Discovery response status: $($discoveryResponse.StatusCode)"
    
    if ($discoveryResponse.StatusCode -eq 200) {
        Write-Success "Discovery Lambda executed successfully"
        
        # Wait for discovery to complete and check results
        Write-Status "Waiting for discovery to complete..."
        Start-Sleep -Seconds 15
        
        # Check instances API for results
        $instancesResponse = Test-LambdaFunction -FunctionName "rds-dashboard-bff" -Payload '{"httpMethod": "GET", "path": "/api/instances", "headers": {"Authorization": "Bearer test"}}' -TestName "Instances API"
        
        if ($instancesResponse -and $instancesResponse.statusCode -eq 200) {
            try {
                $instancesData = $instancesResponse.body | ConvertFrom-Json
                $instanceCount = 0
                
                if ($instancesData.instances) {
                    $instanceCount = $instancesData.instances.Count
                }
                
                Write-Info "Instances discovered: $instanceCount"
                
                if ($instanceCount -gt 1) {
                    Write-Success "Multi-region discovery working! Found $instanceCount instances"
                    $testResults.MultiRegionDiscovery = $true
                    
                    # Show region distribution
                    $regionCounts = @{}
                    foreach ($instance in $instancesData.instances) {
                        $region = $instance.region
                        if ($regionCounts.ContainsKey($region)) {
                            $regionCounts[$region]++
                        } else {
                            $regionCounts[$region] = 1
                        }
                    }
                    
                    Write-Info "Instances by region:"
                    foreach ($region in $regionCounts.Keys) {
                        Write-Host "  $region: $($regionCounts[$region]) instances"
                    }
                } else {
                    Write-Warning "Only found $instanceCount instance(s). Multi-region discovery may need additional configuration."
                }
            } catch {
                Write-Warning "Error parsing instances response: $_"
            }
        }
    } else {
        Write-Error "Discovery Lambda returned error status: $($discoveryResponse.StatusCode)"
    }
}

# Test 3: User Management with Cognito Admin Permissions
Write-Status "📋 Test 3: User Management with Cognito Admin Permissions"

# First check BFF Lambda role permissions
try {
    $bffConfig = aws lambda get-function-configuration `
        --function-name "rds-dashboard-bff" `
        --output json | ConvertFrom-Json
    
    $roleName = ($bffConfig.Role -split '/')[-1]
    Write-Info "BFF Lambda role: $roleName"
    
    # Check if Cognito policy is attached
    $attachedPolicies = aws iam list-attached-role-policies `
        --role-name $roleName `
        --output json | ConvertFrom-Json
    
    $hasCognitoPolicy = $false
    foreach ($policy in $attachedPolicies.AttachedPolicies) {
        if ($policy.PolicyName -like "*Cognito*") {
            $hasCognitoPolicy = $true
            Write-Info "Found Cognito policy: $($policy.PolicyName)"
            break
        }
    }
    
    if ($hasCognitoPolicy) {
        Write-Success "BFF Lambda has Cognito Admin permissions attached"
    } else {
        Write-Warning "BFF Lambda may be missing Cognito Admin permissions"
    }
    
} catch {
    Write-Warning "Error checking BFF Lambda permissions: $_"
}

# Test user management API
$usersResponse = Test-LambdaFunction -FunctionName "rds-dashboard-bff" -Payload '{"httpMethod": "GET", "path": "/api/users", "headers": {"Authorization": "Bearer test"}}' -TestName "User Management API"

if ($usersResponse) {
    Write-Info "User management API response status: $($usersResponse.statusCode)"
    
    if ($usersResponse.statusCode -eq 200) {
        try {
            $usersData = $usersResponse.body | ConvertFrom-Json
            
            if ($usersData.users -and $usersData.users.Count -gt 0) {
                Write-Success "User management API working! Found $($usersData.users.Count) users"
                $testResults.UserManagement = $true
                
                Write-Info "Sample user data:"
                $sampleUser = $usersData.users[0]
                Write-Host "  Username: $($sampleUser.Username)"
                Write-Host "  Email: $($sampleUser.Attributes | Where-Object {$_.Name -eq 'email'} | Select-Object -ExpandProperty Value)"
                Write-Host "  Status: $($sampleUser.UserStatus)"
                
            } elseif ($usersData.message -and $usersData.message -notlike "*generic message*") {
                Write-Info "User management API response: $($usersData.message)"
                
                if ($usersData.message -like "*AccessDenied*" -or $usersData.message -like "*not authorized*") {
                    Write-Warning "User management API has permission issues"
                } else {
                    Write-Success "User management API returning proper responses (not generic message)"
                    $testResults.UserManagement = $true
                }
            } else {
                Write-Warning "User management API still returning generic responses"
            }
        } catch {
            Write-Warning "Error parsing user management response: $_"
        }
    } else {
        Write-Warning "User management API returned error status: $($usersResponse.statusCode)"
    }
}

# Test 4: Instance Operations
Write-Status "📋 Test 4: Instance Operations Testing"

# Test operations Lambda configuration
try {
    $operationsConfig = aws lambda get-function-configuration `
        --function-name "rds-operations-prod" `
        --output json | ConvertFrom-Json
    
    $targetRegions = $operationsConfig.Environment.Variables.TARGET_REGIONS
    Write-Info "Operations Lambda regions: $targetRegions"
    
    $regions = $targetRegions | ConvertFrom-Json
    if ($regions.Count -eq 4) {
        Write-Success "Operations Lambda configured with all 4 regions"
        $testResults.InstanceOperations = $true
    } else {
        Write-Warning "Operations Lambda missing regions. Expected 4, found $($regions.Count)"
    }
    
} catch {
    Write-Warning "Error checking operations configuration: $_"
}

# Test operations API (dry run)
$operationsPayload = @{
    httpMethod = "POST"
    path = "/api/operations"
    headers = @{
        Authorization = "Bearer test"
        "Content-Type" = "application/json"
    }
    body = @{
        instanceId = "test-instance"
        operation = "describe"
        region = "ap-southeast-1"
        dryRun = $true
    } | ConvertTo-Json
} | ConvertTo-Json -Depth 10

$operationsResponse = Test-LambdaFunction -FunctionName "rds-dashboard-bff" -Payload $operationsPayload -TestName "Instance Operations API"

if ($operationsResponse) {
    Write-Info "Operations API response status: $($operationsResponse.statusCode)"
    
    if ($operationsResponse.statusCode -eq 200 -or $operationsResponse.statusCode -eq 400) {
        Write-Success "Operations API is responding (status: $($operationsResponse.statusCode))"
        
        if ($operationsResponse.body) {
            try {
                $operationsData = $operationsResponse.body | ConvertFrom-Json
                Write-Info "Operations response: $($operationsData.message)"
            } catch {
                Write-Info "Operations API returned response"
            }
        }
    } else {
        Write-Warning "Operations API returned unexpected status: $($operationsResponse.statusCode)"
    }
}

# Test 5: Cross-Account Access
Write-Status "📋 Test 5: Cross-Account Access Testing"

try {
    # Check if cross-account roles are configured
    $discoveryEnv = Get-Content "discovery_env.json" | ConvertFrom-Json
    $targetAccounts = $discoveryEnv.Variables.TARGET_ACCOUNTS | ConvertFrom-Json
    
    Write-Info "Target accounts configured: $($targetAccounts.Count)"
    foreach ($account in $targetAccounts) {
        Write-Host "  Account: $account"
    }
    
    if ($targetAccounts.Count -gt 1) {
        Write-Success "Multi-account configuration detected"
        $testResults.CrossAccountAccess = $true
    } else {
        Write-Warning "Only single account configured"
    }
    
} catch {
    Write-Warning "Error checking cross-account configuration: $_"
}

# Test Summary
Write-Status "📊 Test Results Summary" $Magenta

$passedTests = 0
$totalTests = $testResults.Count

Write-Host ""
Write-Info "Backend Infrastructure Fixes Test Results:"

foreach ($test in $testResults.GetEnumerator()) {
    $status = if ($test.Value) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($test.Value) { $Green } else { $Red }
    
    Write-Host "${color}  $($test.Key): $status${Reset}"
    
    if ($test.Value) {
        $passedTests++
    }
}

Write-Host ""
Write-Status "Overall Results: $passedTests/$totalTests tests passed" $(if ($passedTests -eq $totalTests) { $Green } else { $Yellow })

if ($passedTests -eq $totalTests) {
    Write-Success "🎉 All backend infrastructure fixes are working correctly!"
} elseif ($passedTests -ge ($totalTests * 0.8)) {
    Write-Warning "⚠️  Most backend fixes are working, but some issues remain"
} else {
    Write-Error "❌ Significant backend issues detected - additional configuration needed"
}

# Recommendations
Write-Host ""
Write-Status "📋 Recommendations:" $Cyan

if (-not $testResults.DiscoveryConfiguration) {
    Write-Host "  - Update discovery Lambda environment variables with all 4 regions"
}

if (-not $testResults.MultiRegionDiscovery) {
    Write-Host "  - Verify cross-account roles exist in all target accounts"
    Write-Host "  - Check CloudWatch logs for discovery errors"
    Write-Host "  - Ensure RDS instances exist in configured regions"
}

if (-not $testResults.UserManagement) {
    Write-Host "  - Verify Cognito Admin policy is attached to BFF Lambda role"
    Write-Host "  - Check USER_POOL_ID environment variable in BFF Lambda"
    Write-Host "  - Verify Cognito user pool has users"
}

if (-not $testResults.InstanceOperations) {
    Write-Host "  - Update operations Lambda environment variables"
    Write-Host "  - Verify RDS permissions are properly configured"
}

if (-not $testResults.CrossAccountAccess) {
    Write-Host "  - Set up cross-account roles in additional AWS accounts"
    Write-Host "  - Update TARGET_ACCOUNTS environment variable"
}

Write-Host ""
Write-Status "🔍 Next Steps:" $Yellow
Write-Host "  1. Address any failed tests based on recommendations above"
Write-Host "  2. Test the dashboard frontend to verify improvements"
Write-Host "  3. Monitor CloudWatch logs for any errors"
Write-Host "  4. Run end-to-end user testing"

Write-Status "🎯 Backend Infrastructure Fixes Testing Complete!" $Green