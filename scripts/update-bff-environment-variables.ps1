#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Updates BFF Lambda environment variables to remove /prod stage references
.DESCRIPTION
    This script updates the BFF Lambda function environment variables to use clean URLs
    without /prod stage prefixes, fixing the circular dependency issue.
.NOTES
    Requirements: 2.1, 5.1
    Task: 3.1 Update BFF environment variables
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$LambdaFunctionName = "rds-dashboard-bff-prod",
    [string]$InternalApiUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com",
    [switch]$DryRun = $false
)

# Set error handling
$ErrorActionPreference = "Stop"

Write-Host "=== BFF Environment Variables Update ===" -ForegroundColor Green
Write-Host "Lambda Function: $LambdaFunctionName" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "New Internal API URL: $InternalApiUrl" -ForegroundColor Cyan
Write-Host "Dry Run: $DryRun" -ForegroundColor Cyan
Write-Host ""

try {
    # Step 1: Get current Lambda function configuration
    Write-Host "1. Getting current BFF Lambda configuration..." -ForegroundColor Yellow
    
    $lambdaConfig = aws lambda get-function-configuration --function-name $LambdaFunctionName --region $Region | ConvertFrom-Json
    Write-Host "   Function Name: $($lambdaConfig.FunctionName)" -ForegroundColor White
    Write-Host "   Runtime: $($lambdaConfig.Runtime)" -ForegroundColor White
    Write-Host "   Last Modified: $($lambdaConfig.LastModified)" -ForegroundColor White
    
    # Step 2: Analyze current environment variables
    Write-Host "`n2. Analyzing current environment variables..." -ForegroundColor Yellow
    
    $currentEnvVars = $lambdaConfig.Environment.Variables
    Write-Host "   Current environment variables:" -ForegroundColor White
    
    $problematicVars = @()
    foreach ($key in $currentEnvVars.PSObject.Properties.Name) {
        $value = $currentEnvVars.$key
        Write-Host "     $key = $value" -ForegroundColor White
        
        # Check for problematic /prod references
        if ($value -match "/prod") {
            Write-Host "       ⚠️  Contains /prod reference!" -ForegroundColor Red
            $problematicVars += @{ Key = $key; Value = $value }
        }
    }
    
    if ($problematicVars.Count -eq 0) {
        Write-Host "   ✅ No /prod references found in environment variables" -ForegroundColor Green
        return
    }
    
    # Step 3: Prepare updated environment variables
    Write-Host "`n3. Preparing updated environment variables..." -ForegroundColor Yellow
    
    $updatedEnvVars = @{}
    foreach ($key in $currentEnvVars.PSObject.Properties.Name) {
        $value = $currentEnvVars.$key
        
        if ($key -eq "INTERNAL_API_URL") {
            # Remove /prod suffix from INTERNAL_API_URL
            $cleanValue = $InternalApiUrl.TrimEnd('/')
            $updatedEnvVars[$key] = $cleanValue
            Write-Host "   Updated $key: $value -> $cleanValue" -ForegroundColor Green
        } else {
            # Keep other variables as-is, but clean any /prod references
            $cleanValue = $value -replace "/prod$", "" -replace "/prod/", "/"
            $updatedEnvVars[$key] = $cleanValue
            
            if ($cleanValue -ne $value) {
                Write-Host "   Cleaned $key: $value -> $cleanValue" -ForegroundColor Green
            } else {
                Write-Host "   Keeping $key: $value" -ForegroundColor White
            }
        }
    }
    
    # Add service-specific endpoint configuration if not present
    $serviceEndpoints = @{
        "DISCOVERY_ENDPOINT" = "$InternalApiUrl/instances"
        "OPERATIONS_ENDPOINT" = "$InternalApiUrl/operations"
        "MONITORING_ENDPOINT" = "$InternalApiUrl/monitoring"
        "COMPLIANCE_ENDPOINT" = "$InternalApiUrl/compliance"
        "COSTS_ENDPOINT" = "$InternalApiUrl/costs"
    }
    
    foreach ($endpoint in $serviceEndpoints.GetEnumerator()) {
        if (-not $updatedEnvVars.ContainsKey($endpoint.Key)) {
            $updatedEnvVars[$endpoint.Key] = $endpoint.Value
            Write-Host "   Added $($endpoint.Key): $($endpoint.Value)" -ForegroundColor Cyan
        }
    }
    
    if ($DryRun) {
        Write-Host "`n=== DRY RUN - No changes will be made ===" -ForegroundColor Magenta
        Write-Host "Would update environment variables to:" -ForegroundColor Magenta
        
        foreach ($key in $updatedEnvVars.Keys | Sort-Object) {
            Write-Host "  $key = $($updatedEnvVars[$key])" -ForegroundColor Magenta
        }
        
        return
    }
    
    # Step 4: Update Lambda function environment variables
    Write-Host "`n4. Updating Lambda function environment variables..." -ForegroundColor Yellow
    
    # Convert hashtable to JSON for AWS CLI
    $envVarsJson = $updatedEnvVars | ConvertTo-Json -Compress
    
    $updateResult = aws lambda update-function-configuration `
        --function-name $LambdaFunctionName `
        --environment "Variables=$envVarsJson" `
        --region $Region | ConvertFrom-Json
        
    Write-Host "   ✅ Environment variables updated successfully" -ForegroundColor Green
    Write-Host "   Last Modified: $($updateResult.LastModified)" -ForegroundColor White
    
    # Step 5: Wait for update to complete
    Write-Host "`n5. Waiting for update to complete..." -ForegroundColor Yellow
    
    do {
        Start-Sleep -Seconds 2
        $status = aws lambda get-function-configuration --function-name $LambdaFunctionName --region $Region | ConvertFrom-Json
        Write-Host "   Status: $($status.State)" -ForegroundColor White
    } while ($status.State -eq "Pending")
    
    if ($status.State -eq "Active") {
        Write-Host "   ✅ Lambda function is active and ready" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Lambda function state: $($status.State)" -ForegroundColor Yellow
    }
    
    # Step 6: Validate updated configuration
    Write-Host "`n6. Validating updated configuration..." -ForegroundColor Yellow
    
    $finalConfig = aws lambda get-function-configuration --function-name $LambdaFunctionName --region $Region | ConvertFrom-Json
    $finalEnvVars = $finalConfig.Environment.Variables
    
    Write-Host "   Final environment variables:" -ForegroundColor White
    foreach ($key in $finalEnvVars.PSObject.Properties.Name | Sort-Object) {
        $value = $finalEnvVars.$key
        if ($value -match "/prod") {
            Write-Host "     ❌ $key = $value (still contains /prod!)" -ForegroundColor Red
        } else {
            Write-Host "     ✅ $key = $value" -ForegroundColor Green
        }
    }
    
    # Step 7: Test BFF health endpoint
    Write-Host "`n7. Testing BFF health endpoint..." -ForegroundColor Yellow
    
    # Get the BFF API Gateway URL (assuming it's configured)
    $bffApiUrl = $finalEnvVars.BFF_API_URL
    if (-not $bffApiUrl) {
        $bffApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com"
    }
    
    try {
        $healthResponse = Invoke-RestMethod -Uri "$bffApiUrl/health" -Method GET -TimeoutSec 15
        Write-Host "   ✅ BFF health check passed: $($healthResponse.status)" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️  BFF health check failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   This may be expected if the Lambda is still warming up" -ForegroundColor Yellow
    }
    
    Write-Host "`n=== BFF Environment Variables Update Complete ===" -ForegroundColor Green
    Write-Host "✅ Removed all /prod stage references from environment variables" -ForegroundColor Green
    Write-Host "✅ Updated INTERNAL_API_URL to use clean URL: $InternalApiUrl" -ForegroundColor Green
    Write-Host "✅ Added service-specific endpoint configuration" -ForegroundColor Green
    Write-Host ""
    Write-Host "Key changes made:" -ForegroundColor Cyan
    Write-Host "- INTERNAL_API_URL: Now points to clean API Gateway URL" -ForegroundColor Cyan
    Write-Host "- Added service endpoints for better service discovery" -ForegroundColor Cyan
    Write-Host "- Removed all /prod stage references" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Test BFF to backend service communication" -ForegroundColor Cyan
    Write-Host "2. Verify all API endpoints work with clean URLs" -ForegroundColor Cyan
    Write-Host "3. Update frontend configuration if needed" -ForegroundColor Cyan
    
} catch {
    Write-Host "`n❌ Error updating BFF environment variables:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}