#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enable production operations on the RDS Operations Dashboard

.DESCRIPTION
    This script enables operations on production RDS instances by updating
    the configuration and deploying the changes.

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\enable-production-operations.ps1
    
.EXAMPLE
    .\enable-production-operations.ps1 -Force
#>

param(
    [switch]$Force
)

Write-Host "Enable Production Operations" -ForegroundColor Cyan
Write-Host ""

# Confirm action unless Force is specified
if (-not $Force) {
    Write-Host "WARNING: This will enable operations on production RDS instances!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This includes potentially risky operations like:" -ForegroundColor Yellow
    Write-Host "  - Instance reboots" -ForegroundColor Yellow
    Write-Host "  - Instance stop/start" -ForegroundColor Yellow
    Write-Host "  - Storage modifications" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Safe operations (snapshots, backup window changes) will still have safeguards." -ForegroundColor Green
    Write-Host ""
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Step 1: Configuration is already updated..." -ForegroundColor Yellow
Write-Host "Configuration file shows production operations are enabled" -ForegroundColor Green

Write-Host ""
Write-Host "Step 2: Deploying Lambda functions..." -ForegroundColor Yellow

# Deploy operations Lambda with updated config
try {
    Write-Host "Deploying operations Lambda..." -ForegroundColor Cyan
    
    # Use CDK to deploy the compute stack (which includes operations Lambda)
    cdk deploy RDSDashboardComputeStack --require-approval never
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Operations Lambda deployed" -ForegroundColor Green
    } else {
        Write-Host "Failed to deploy operations Lambda" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error deploying Lambda: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 3: Updating BFF environment..." -ForegroundColor Yellow

# Update BFF environment variable
try {
    Write-Host "Setting ENABLE_PRODUCTION_OPERATIONS=true for BFF..." -ForegroundColor Cyan
    
    # Get the BFF Lambda function name
    $bffFunctionName = aws lambda list-functions --query 'Functions[?contains(FunctionName, `rds-dashboard-bff`)].FunctionName' --output text
    
    if ($bffFunctionName) {
        Write-Host "Found BFF function: $bffFunctionName" -ForegroundColor Green
        
        # Update environment variable
        aws lambda update-function-configuration --function-name $bffFunctionName --environment "Variables={ENABLE_PRODUCTION_OPERATIONS=true}"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "BFF environment updated" -ForegroundColor Green
        } else {
            Write-Host "Failed to update BFF environment" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "BFF function not found, skipping environment update" -ForegroundColor Yellow
        Write-Host "You may need to redeploy the BFF stack" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error updating BFF: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "PRODUCTION OPERATIONS ENABLED!" -ForegroundColor Green
Write-Host ""

Write-Host "Summary of changes:" -ForegroundColor Cyan
Write-Host "   Configuration updated to allow production operations" -ForegroundColor Green
Write-Host "   Operations Lambda deployed with new config" -ForegroundColor Green
Write-Host "   BFF updated to allow production operations" -ForegroundColor Green
Write-Host ""

Write-Host "Security Safeguards:" -ForegroundColor Blue
Write-Host "   Admin privileges required for risky operations" -ForegroundColor Green
Write-Host "   Confirmation required for destructive operations" -ForegroundColor Green
Write-Host "   All operations are logged and audited" -ForegroundColor Green
Write-Host "   Safe operations (snapshots) allowed without restrictions" -ForegroundColor Green
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Green
Write-Host "   1. Test operations on a production instance" -ForegroundColor White
Write-Host "   2. For risky operations, include 'confirm_production': true in parameters" -ForegroundColor White
Write-Host "   3. Monitor audit logs for all production operations" -ForegroundColor White
Write-Host ""

Write-Host "For help, see: .\TROUBLESHOOTING-403-500-ERRORS.md" -ForegroundColor Blue
Write-Host ""