#!/usr/bin/env pwsh

# Test Fixed Operations and Discovery
# This script tests the Lambda functions directly with proper payloads

$ErrorActionPreference = "Stop"

Write-Host "Testing Fixed Operations and Discovery..." -ForegroundColor Cyan

# Test 1: Test Discovery Lambda with proper payload
Write-Host "`nTest 1: Testing Discovery Lambda" -ForegroundColor Yellow

try {
    $discoveryPayload = @{
        trigger = "manual"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    # Convert to base64 for AWS CLI
    $discoveryPayloadJson = $discoveryPayload | ConvertTo-Json -Compress
    $discoveryPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($discoveryPayloadJson))
    
    Write-Host "Invoking discovery Lambda..."
    
    $discoveryResult = aws lambda invoke --function-name "rds-discovery-prod" --payload $discoveryPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Discovery Lambda Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Discovery Results:" -ForegroundColor Green
            Write-Host "  Total Instances: $($bodyContent.total_instances)"
            Write-Host "  Accounts Scanned: $($bodyContent.accounts_scanned)"
            Write-Host "  Regions Scanned: $($bodyContent.regions_scanned)"
            Write-Host "  Execution Status: $($bodyContent.execution_status)"
            
            if ($bodyContent.errors -and $bodyContent.errors.Count -gt 0) {
                Write-Host "  Errors: $($bodyContent.errors.Count)" -ForegroundColor Yellow
                $bodyContent.errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Discovery Lambda invocation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Discovery Lambda Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Test Operations Lambda with proper payload
Write-Host "`nTest 2: Testing Operations Lambda" -ForegroundColor Yellow

try {
    $operationsPayload = @{
        body = (@{
            instance_id = "tb-pg-db1"
            operation = "create_snapshot"
            region = "ap-southeast-1"
            account_id = "876595225096"
            parameters = @{
                snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            user_id = "test-user"
            requested_by = "test@example.com"
            user_groups = @("Admin")
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json -Compress)
        requestContext = @{
            identity = @{
                sourceIp = "127.0.0.1"
                userAgent = "test-script"
            }
        }
    }
    
    # Convert to base64 for AWS CLI
    $operationsPayloadJson = $operationsPayload | ConvertTo-Json -Depth 5 -Compress
    $operationsPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($operationsPayloadJson))
    
    Write-Host "Invoking operations Lambda..."
    
    $operationsResult = aws lambda invoke --function-name "rds-operations-prod" --payload $operationsPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Operations Lambda Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Operations Results:" -ForegroundColor Green
            
            if ($bodyContent.operation) {
                Write-Host "  Operation: $($bodyContent.operation)"
                Write-Host "  Instance ID: $($bodyContent.instance_id)"
                Write-Host "  Status: $($bodyContent.status)"
                Write-Host "  Success: $($bodyContent.success)"
                
                if ($bodyContent.account_id) {
                    Write-Host "  Account ID: $($bodyContent.account_id)"
                }
                if ($bodyContent.region) {
                    Write-Host "  Region: $($bodyContent.region)"
                }
                if ($bodyContent.cross_account) {
                    Write-Host "  Cross Account: $($bodyContent.cross_account)"
                }
            } else {
                Write-Host "  Error: $($bodyContent.error)" -ForegroundColor Red
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Operations Lambda invocation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Operations Lambda Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Test a simple reboot operation
Write-Host "`nTest 3: Testing Reboot Operation" -ForegroundColor Yellow

try {
    $rebootPayload = @{
        body = (@{
            instance_id = "tb-pg-db1"
            operation = "reboot"
            region = "ap-southeast-1"
            account_id = "876595225096"
            parameters = @{
                force_failover = $false
            }
            user_id = "test-user"
            requested_by = "test@example.com"
            user_groups = @("Admin")
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json -Compress)
        requestContext = @{
            identity = @{
                sourceIp = "127.0.0.1"
                userAgent = "test-script"
            }
        }
    }
    
    # Convert to base64 for AWS CLI
    $rebootPayloadJson = $rebootPayload | ConvertTo-Json -Depth 5 -Compress
    $rebootPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($rebootPayloadJson))
    
    Write-Host "Testing reboot operation..."
    
    $rebootResult = aws lambda invoke --function-name "rds-operations-prod" --payload $rebootPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Reboot Operation Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Reboot Results:" -ForegroundColor Green
            
            if ($bodyContent.operation) {
                Write-Host "  Operation: $($bodyContent.operation)"
                Write-Host "  Instance ID: $($bodyContent.instance_id)"
                Write-Host "  Status: $($bodyContent.status)"
                Write-Host "  Success: $($bodyContent.success)"
            } else {
                Write-Host "  Error: $($bodyContent.error)" -ForegroundColor Red
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Reboot operation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Reboot Operation Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Check if instances are in inventory
Write-Host "`nTest 4: Checking Instance Inventory" -ForegroundColor Yellow

try {
    Write-Host "Checking DynamoDB inventory table..."
    
    $inventoryItems = aws dynamodb scan --table-name "rds-inventory-prod" --select "COUNT" --output json | ConvertFrom-Json
    
    Write-Host "Total items in inventory: $($inventoryItems.Count)" -ForegroundColor Green
    
    # Get a few sample items
    $sampleItems = aws dynamodb scan --table-name "rds-inventory-prod" --limit 3 --output json | ConvertFrom-Json
    
    if ($sampleItems.Items -and $sampleItems.Items.Count -gt 0) {
        Write-Host "Sample instances in inventory:" -ForegroundColor Green
        $sampleItems.Items | ForEach-Object {
            $instanceId = $_.instance_id.S
            $region = $_.region.S
            $status = $_.status.S
            Write-Host "  - $instanceId ($region) - $status"
        }
    }
    
} catch {
    Write-Host "Inventory check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nFixed Operations and Discovery Testing Complete!" -ForegroundColor Cyan
Write-Host "Check the results above to verify operations and discovery are working." -ForegroundColor Yellow