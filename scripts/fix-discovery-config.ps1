#!/usr/bin/env pwsh

<#
.SYNOPSIS
Fix Discovery Lambda Configuration

.DESCRIPTION
Fixes the discovery Lambda configuration to use the correct table name and config
#>

param(
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Fixing Discovery Lambda Configuration ===" -ForegroundColor Cyan

try {
    # Update Lambda environment variables
    Write-Info "Updating Lambda environment variables..."
    
    $envVars = @{
        'DYNAMODB_TABLE' = "rds-inventory-$Environment"
        'TARGET_REGIONS' = '["ap-southeast-1", "us-east-1", "us-west-2"]'
        'LOG_LEVEL' = 'INFO'
    }
    
    $envVarsJson = $envVars | ConvertTo-Json -Compress
    
    $updateResult = aws lambda update-function-configuration `
        --function-name "rds-discovery-$Environment" `
        --environment "Variables=$envVarsJson" `
        --region ap-southeast-1 `
        --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Lambda environment variables updated"
    } else {
        Write-Warning "Failed to update environment variables: $updateResult"
    }
    
    # Test the table access
    Write-Info "Testing table access..."
    
    $tableInfo = aws dynamodb describe-table `
        --table-name "rds-inventory-$Environment" `
        --region ap-southeast-1 `
        --output json 2>$null | ConvertFrom-Json
    
    if ($tableInfo) {
        Write-Success "Table accessible: $($tableInfo.Table.TableName)"
        Write-Info "Table status: $($tableInfo.Table.TableStatus)"
        Write-Info "Item count: $($tableInfo.Table.ItemCount)"
    }
    
    # Create a simple test payload and run discovery
    Write-Info "Testing discovery with correct configuration..."
    
    $testPayload = @{
        action = "discover"
        force_refresh = $true
    } | ConvertTo-Json -Compress
    
    # Save to file
    $testPayload | Out-File -FilePath "test_payload.json" -Encoding UTF8
    
    # Invoke Lambda
    $invokeResult = aws lambda invoke `
        --function-name "rds-discovery-$Environment" `
        --payload file://test_payload.json `
        --region ap-southeast-1 `
        test_response.json 2>&1
    
    Write-Info "Lambda invoke result: $invokeResult"
    
    if (Test-Path "test_response.json") {
        $response = Get-Content "test_response.json" | ConvertFrom-Json
        Write-Info "Discovery response:"
        Write-Host ($response | ConvertTo-Json -Depth 3) -ForegroundColor White
        
        Remove-Item "test_response.json" -Force
    }
    
    Remove-Item "test_payload.json" -Force
    
    # Wait a moment and check the table
    Write-Info "Waiting for discovery to complete..."
    Start-Sleep -Seconds 5
    
    # Check table contents
    $items = aws dynamodb scan `
        --table-name "rds-inventory-$Environment" `
        --region ap-southeast-1 `
        --max-items 5 `
        --output json 2>$null | ConvertFrom-Json
    
    if ($items -and $items.Items.Count -gt 0) {
        Write-Success "Found $($items.Items.Count) items in inventory table"
        
        foreach ($item in $items.Items | Select-Object -First 3) {
            $instanceId = $item.instance_id.S
            $engine = $item.engine.S
            $status = $item.status.S
            Write-Info "  Instance: $instanceId ($engine) - Status: $status"
        }
    } else {
        Write-Warning "No items found in inventory table"
    }
    
} catch {
    Write-Error "Error fixing discovery configuration: $($_.Exception.Message)"
}

Write-Host "`n=== Discovery Configuration Fix Completed ===" -ForegroundColor Cyan