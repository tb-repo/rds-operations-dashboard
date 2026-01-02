#!/usr/bin/env pwsh

<#
.SYNOPSIS
Comprehensive Discovery Trigger Script

.DESCRIPTION
Triggers discovery across all accounts and regions to populate the database
#>

param(
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Comprehensive Discovery Trigger ===" -ForegroundColor Cyan
Write-Info "Environment: $Environment"

try {
    # First, check what accounts are available
    Write-Info "Checking organization accounts..."
    $orgAccounts = aws organizations list-accounts --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
    
    if ($orgAccounts) {
        Write-Success "Found $($orgAccounts.Accounts.Count) accounts in organization"
        
        foreach ($account in $orgAccounts.Accounts | Where-Object { $_.Status -eq "ACTIVE" } | Select-Object -First 5) {
            Write-Info "  Account: $($account.Name) ($($account.Id))"
        }
    } else {
        Write-Warning "Could not list organization accounts, proceeding with single account discovery"
    }
    
    # Trigger discovery with comprehensive parameters
    Write-Info "Triggering comprehensive discovery..."
    
    $discoveryPayload = @{
        httpMethod = "POST"
        path = "/discovery/trigger"
        body = @{
            action = "discover_all"
            force_refresh = $true
            scan_all_regions = $true
            scan_all_accounts = $true
            include_stopped_instances = $true
            deep_scan = $true
        } | ConvertTo-Json
        headers = @{
            'Content-Type' = 'application/json'
        }
    } | ConvertTo-Json -Compress
    
    Write-Info "Calling discovery Lambda..."
    $discoveryResult = aws lambda invoke `
        --function-name "rds-discovery-$Environment" `
        --payload $discoveryPayload `
        --region ap-southeast-1 `
        discovery_comprehensive.json 2>&1
    
    if (Test-Path "discovery_comprehensive.json") {
        $result = Get-Content "discovery_comprehensive.json" | ConvertFrom-Json
        Write-Info "Discovery result: $($result | ConvertTo-Json -Depth 3)"
        Remove-Item "discovery_comprehensive.json" -Force
        
        if ($result.statusCode -eq 200) {
            Write-Success "Discovery triggered successfully"
            
            if ($result.body) {
                $body = $result.body | ConvertFrom-Json
                if ($body.instances_discovered) {
                    Write-Success "Discovered $($body.instances_discovered) instances"
                }
                if ($body.accounts_scanned) {
                    Write-Success "Scanned $($body.accounts_scanned) accounts"
                }
            }
        } else {
            Write-Warning "Discovery returned status: $($result.statusCode)"
            if ($result.body) {
                Write-Warning "Error: $($result.body)"
            }
        }
    }
    
    # Wait a moment for discovery to process
    Write-Info "Waiting for discovery to process..."
    Start-Sleep -Seconds 10
    
    # Check the results in DynamoDB
    Write-Info "Checking discovery results in database..."
    $instances = aws dynamodb scan `
        --table-name "RDSInstances-$Environment" `
        --region ap-southeast-1 `
        --max-items 10 `
        --output json 2>$null | ConvertFrom-Json
    
    if ($instances -and $instances.Items.Count -gt 0) {
        Write-Success "Found $($instances.Items.Count) instances in database"
        
        Write-Info "Instance details:"
        foreach ($instance in $instances.Items | Select-Object -First 5) {
            $instanceId = $instance.instance_id.S
            $accountId = $instance.account_id.S
            $region = $instance.region.S
            $status = $instance.status.S
            $engine = $instance.engine.S
            
            Write-Info "  $instanceId ($engine) - Account: $accountId, Region: $region, Status: $status"
        }
        
        # Test operations on one of the instances
        if ($instances.Items.Count -gt 0) {
            $testInstance = $instances.Items[0]
            $testInstanceId = $testInstance.instance_id.S
            $testAccountId = $testInstance.account_id.S
            
            Write-Info "Testing operations on instance: $testInstanceId"
            
            $operationsPayload = @{
                httpMethod = "POST"
                path = "/operations"
                body = @{
                    operation = "get_status"
                    instance_id = $testInstanceId
                    account_id = $testAccountId
                } | ConvertTo-Json
                headers = @{
                    'Content-Type' = 'application/json'
                }
            } | ConvertTo-Json -Compress
            
            $operationsResult = aws lambda invoke `
                --function-name "rds-operations-$Environment" `
                --payload $operationsPayload `
                --region ap-southeast-1 `
                operations_test.json 2>&1
            
            if (Test-Path "operations_test.json") {
                $opResult = Get-Content "operations_test.json" | ConvertFrom-Json
                Write-Info "Operations test result: $($opResult | ConvertTo-Json -Depth 2)"
                Remove-Item "operations_test.json" -Force
                
                if ($opResult.statusCode -eq 200) {
                    Write-Success "Operations test successful"
                } else {
                    Write-Warning "Operations test returned status: $($opResult.statusCode)"
                }
            }
        }
        
    } else {
        Write-Warning "No instances found in database after discovery"
        
        # Try alternative discovery approach
        Write-Info "Trying alternative discovery approach..."
        
        # Call discovery Lambda with simpler payload
        $simplePayload = @{
            action = "discover"
            force_refresh = $true
        } | ConvertTo-Json -Compress
        
        $simpleResult = aws lambda invoke `
            --function-name "rds-discovery-$Environment" `
            --payload $simplePayload `
            --region ap-southeast-1 `
            discovery_simple.json 2>&1
        
        if (Test-Path "discovery_simple.json") {
            $simpleRes = Get-Content "discovery_simple.json" | ConvertFrom-Json
            Write-Info "Simple discovery result: $($simpleRes | ConvertTo-Json -Depth 2)"
            Remove-Item "discovery_simple.json" -Force
        }
        
        # Check if there are any RDS instances in the current account
        Write-Info "Checking for RDS instances in current account..."
        $rdsInstances = aws rds describe-db-instances --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
        
        if ($rdsInstances -and $rdsInstances.DBInstances.Count -gt 0) {
            Write-Success "Found $($rdsInstances.DBInstances.Count) RDS instances in current account"
            
            foreach ($instance in $rdsInstances.DBInstances | Select-Object -First 3) {
                Write-Info "  Instance: $($instance.DBInstanceIdentifier) ($($instance.Engine)) - Status: $($instance.DBInstanceStatus)"
            }
        } else {
            Write-Info "No RDS instances found in current account/region"
        }
    }
    
} catch {
    Write-Error "Error in discovery process: $($_.Exception.Message)"
}

Write-Host "`n=== Discovery Process Completed ===" -ForegroundColor Cyan