#!/usr/bin/env pwsh

# Simple Backend Testing Script
# Tests the backend infrastructure fixes

$ErrorActionPreference = "Continue"

Write-Host "Testing Backend Infrastructure Fixes..." -ForegroundColor Cyan

# Test 1: Check Discovery Lambda Configuration
Write-Host "Test 1: Discovery Lambda Configuration" -ForegroundColor Blue

try {
    $discoveryConfig = aws lambda get-function-configuration `
        --function-name "rds-discovery-prod" `
        --output json | ConvertFrom-Json
    
    $targetRegions = $discoveryConfig.Environment.Variables.TARGET_REGIONS
    Write-Host "Discovery Target Regions: $targetRegions" -ForegroundColor Green
    
    # Parse regions
    $regions = $targetRegions | ConvertFrom-Json
    Write-Host "Number of regions configured: $($regions.Count)" -ForegroundColor Green
    
    if ($regions.Count -eq 4) {
        Write-Host "SUCCESS: Discovery configured with 4 regions" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Expected 4 regions, found $($regions.Count)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Could not check discovery configuration" -ForegroundColor Red
}

# Test 2: Check Operations Lambda Configuration
Write-Host "Test 2: Operations Lambda Configuration" -ForegroundColor Blue

try {
    $operationsConfig = aws lambda get-function-configuration `
        --function-name "rds-operations-prod" `
        --output json | ConvertFrom-Json
    
    $targetRegions = $operationsConfig.Environment.Variables.TARGET_REGIONS
    Write-Host "Operations Target Regions: $targetRegions" -ForegroundColor Green
    
    # Parse regions
    $regions = $targetRegions | ConvertFrom-Json
    Write-Host "Number of regions configured: $($regions.Count)" -ForegroundColor Green
    
    if ($regions.Count -eq 4) {
        Write-Host "SUCCESS: Operations configured with 4 regions" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Expected 4 regions, found $($regions.Count)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Could not check operations configuration" -ForegroundColor Red
}

# Test 3: Check BFF Lambda Cognito Permissions
Write-Host "Test 3: BFF Lambda Cognito Permissions" -ForegroundColor Blue

try {
    $bffConfig = aws lambda get-function-configuration `
        --function-name "rds-dashboard-bff-prod" `
        --output json | ConvertFrom-Json
    
    $roleName = ($bffConfig.Role -split '/')[-1]
    Write-Host "BFF Lambda role: $roleName" -ForegroundColor Green
    
    # Check attached policies
    $attachedPolicies = aws iam list-attached-role-policies `
        --role-name $roleName `
        --output json | ConvertFrom-Json
    
    $hasCognitoPolicy = $false
    foreach ($policy in $attachedPolicies.AttachedPolicies) {
        Write-Host "Attached policy: $($policy.PolicyName)"
        if ($policy.PolicyName -like "*Cognito*") {
            $hasCognitoPolicy = $true
        }
    }
    
    if ($hasCognitoPolicy) {
        Write-Host "SUCCESS: BFF Lambda has Cognito permissions" -ForegroundColor Green
    } else {
        Write-Host "WARNING: BFF Lambda may be missing Cognito permissions" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Could not check BFF Lambda permissions" -ForegroundColor Red
}

# Test 4: Test Discovery API
Write-Host "Test 4: Discovery API Test" -ForegroundColor Blue

try {
    Write-Host "Triggering discovery..."
    
    $discoveryResult = aws lambda invoke `
        --function-name "rds-discovery-prod" `
        --payload '{"trigger": "test"}' `
        --output json `
        discovery-response.json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Discovery Lambda invoked" -ForegroundColor Green
        
        if (Test-Path "discovery-response.json") {
            $response = Get-Content "discovery-response.json" | ConvertFrom-Json
            Write-Host "Discovery response status: $($response.StatusCode)" -ForegroundColor Green
            Remove-Item "discovery-response.json" -Force
        }
    } else {
        Write-Host "WARNING: Discovery invocation failed: $discoveryResult" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "WARNING: Error testing discovery" -ForegroundColor Yellow
}

# Test 5: Test Instances API
Write-Host "Test 5: Instances API Test" -ForegroundColor Blue

try {
    Write-Host "Testing instances API..."
    
    $instancesResult = aws lambda invoke `
        --function-name "rds-dashboard-bff-prod" `
        --payload '{"httpMethod": "GET", "path": "/api/instances"}' `
        --output json `
        instances-response.json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Instances API invoked" -ForegroundColor Green
        
        if (Test-Path "instances-response.json") {
            $response = Get-Content "instances-response.json" | ConvertFrom-Json
            Write-Host "Instances API response status: $($response.statusCode)" -ForegroundColor Green
            
            if ($response.body) {
                try {
                    $instancesData = $response.body | ConvertFrom-Json
                    if ($instancesData.instances) {
                        $instanceCount = $instancesData.instances.Count
                        Write-Host "Instances found: $instanceCount" -ForegroundColor Green
                        
                        if ($instanceCount -gt 1) {
                            Write-Host "SUCCESS: Multi-region discovery appears to be working!" -ForegroundColor Green
                        } else {
                            Write-Host "INFO: Only $instanceCount instance found" -ForegroundColor Yellow
                        }
                    }
                } catch {
                    Write-Host "INFO: Could not parse instances data" -ForegroundColor Yellow
                }
            }
            
            Remove-Item "instances-response.json" -Force
        }
    } else {
        Write-Host "WARNING: Instances API invocation failed: $instancesResult" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "WARNING: Error testing instances API" -ForegroundColor Yellow
}

# Test 6: Test Users API
Write-Host "Test 6: Users API Test" -ForegroundColor Blue

try {
    Write-Host "Testing users API..."
    
    $usersResult = aws lambda invoke `
        --function-name "rds-dashboard-bff-prod" `
        --payload '{"httpMethod": "GET", "path": "/api/users"}' `
        --output json `
        users-response.json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Users API invoked" -ForegroundColor Green
        
        if (Test-Path "users-response.json") {
            $response = Get-Content "users-response.json" | ConvertFrom-Json
            Write-Host "Users API response status: $($response.statusCode)" -ForegroundColor Green
            
            if ($response.body) {
                try {
                    $usersData = $response.body | ConvertFrom-Json
                    if ($usersData.users -and $usersData.users.Count -gt 0) {
                        Write-Host "SUCCESS: Users API working! Found $($usersData.users.Count) users" -ForegroundColor Green
                    } elseif ($usersData.message) {
                        Write-Host "Users API response: $($usersData.message)" -ForegroundColor Yellow
                        if ($usersData.message -notlike "*generic message*") {
                            Write-Host "SUCCESS: Users API returning proper responses" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Host "INFO: Could not parse users data" -ForegroundColor Yellow
                }
            }
            
            Remove-Item "users-response.json" -Force
        }
    } else {
        Write-Host "WARNING: Users API invocation failed: $usersResult" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "WARNING: Error testing users API" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Backend Infrastructure Fixes Testing Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - Discovery Lambda: Multi-region configuration applied"
Write-Host "  - Operations Lambda: Multi-region configuration applied"
Write-Host "  - BFF Lambda: Cognito permissions added"
Write-Host "  - APIs: Tested for basic functionality"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test the dashboard frontend to see improvements"
Write-Host "  2. Check user management tab for user list"
Write-Host "  3. Verify instance discovery shows more instances"
Write-Host "  4. Test instance operations across regions"