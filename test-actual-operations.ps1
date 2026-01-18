#!/usr/bin/env pwsh

# Test Actual Operations - Instance Start/Stop and Discovery Trigger
# This script tests the specific functionality the user reported as not working

$ErrorActionPreference = "Stop"

Write-Host "Testing Actual Operations - Instance Start/Stop and Discovery Trigger" -ForegroundColor Cyan

# Test 1: Test Instance Stop Operation
Write-Host "`nTest 1: Testing Instance Stop Operation" -ForegroundColor Yellow

try {
    $stopPayload = @{
        body = (@{
            instance_id = "tb-pg-db1"
            operation = "stop_instance"
            region = "ap-southeast-1"
            account_id = "876595225096"
            parameters = @{
                snapshot_id = "stop-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
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
    
    $stopPayloadJson = $stopPayload | ConvertTo-Json -Depth 5 -Compress
    $stopPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($stopPayloadJson))
    
    Write-Host "Testing stop instance operation..."
    
    $stopResult = aws lambda invoke --function-name "rds-operations-prod" --payload $stopPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Stop Instance Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Stop Instance Results:" -ForegroundColor Green
            
            if ($bodyContent.operation) {
                Write-Host "  Operation: $($bodyContent.operation)"
                Write-Host "  Instance ID: $($bodyContent.instance_id)"
                Write-Host "  Status: $($bodyContent.status)"
                Write-Host "  Success: $($bodyContent.success)"
                Write-Host "  Account ID: $($bodyContent.account_id)"
                Write-Host "  Region: $($bodyContent.region)"
                Write-Host "  Cross Account: $($bodyContent.cross_account)"
                Write-Host "  Duration: $($bodyContent.duration_seconds) seconds"
            } else {
                Write-Host "  Error: $($bodyContent.error)" -ForegroundColor Red
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Stop instance operation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Stop Instance Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Test Instance Start Operation
Write-Host "`nTest 2: Testing Instance Start Operation" -ForegroundColor Yellow

try {
    $startPayload = @{
        body = (@{
            instance_id = "tb-pg-db1"
            operation = "start_instance"
            region = "ap-southeast-1"
            account_id = "876595225096"
            parameters = @{}
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
    
    $startPayloadJson = $startPayload | ConvertTo-Json -Depth 5 -Compress
    $startPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($startPayloadJson))
    
    Write-Host "Testing start instance operation..."
    
    $startResult = aws lambda invoke --function-name "rds-operations-prod" --payload $startPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Start Instance Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Start Instance Results:" -ForegroundColor Green
            
            if ($bodyContent.operation) {
                Write-Host "  Operation: $($bodyContent.operation)"
                Write-Host "  Instance ID: $($bodyContent.instance_id)"
                Write-Host "  Status: $($bodyContent.status)"
                Write-Host "  Success: $($bodyContent.success)"
                Write-Host "  Account ID: $($bodyContent.account_id)"
                Write-Host "  Region: $($bodyContent.region)"
                Write-Host "  Cross Account: $($bodyContent.cross_account)"
                Write-Host "  Duration: $($bodyContent.duration_seconds) seconds"
            } else {
                Write-Host "  Error: $($bodyContent.error)" -ForegroundColor Red
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Start instance operation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Start Instance Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Test Discovery Trigger (Direct Lambda)
Write-Host "`nTest 3: Testing Discovery Trigger (Direct Lambda)" -ForegroundColor Yellow

try {
    $discoveryPayload = @{
        trigger = "manual"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        source = "test-script"
    }
    
    $discoveryPayloadJson = $discoveryPayload | ConvertTo-Json -Compress
    $discoveryPayloadBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($discoveryPayloadJson))
    
    Write-Host "Testing discovery trigger..."
    
    $discoveryResult = aws lambda invoke --function-name "rds-discovery-prod" --payload $discoveryPayloadBase64 --output json response.json
    
    if ($LASTEXITCODE -eq 0) {
        $responseContent = Get-Content response.json -Raw | ConvertFrom-Json
        Write-Host "Discovery Trigger Response Status: $($responseContent.statusCode)" -ForegroundColor Green
        
        if ($responseContent.body) {
            $bodyContent = $responseContent.body | ConvertFrom-Json
            Write-Host "Discovery Trigger Results:" -ForegroundColor Green
            Write-Host "  Total Instances: $($bodyContent.total_instances)"
            Write-Host "  Accounts Scanned: $($bodyContent.accounts_scanned)"
            Write-Host "  Regions Scanned: $($bodyContent.regions_scanned)"
            Write-Host "  Execution Status: $($bodyContent.execution_status)"
            Write-Host "  Cross Account Enabled: $($bodyContent.cross_account_enabled)"
            
            if ($bodyContent.errors -and $bodyContent.errors.Count -gt 0) {
                Write-Host "  Errors: $($bodyContent.errors.Count)" -ForegroundColor Yellow
                $bodyContent.errors | ForEach-Object { 
                    Write-Host "    - $($_.type): $($_.error)" -ForegroundColor Yellow 
                }
            }
            
            if ($bodyContent.persistence) {
                Write-Host "  Persistence Results:" -ForegroundColor Green
                Write-Host "    New Instances: $($bodyContent.persistence.new_instances)"
                Write-Host "    Updated Instances: $($bodyContent.persistence.updated_instances)"
                Write-Host "    Deleted Instances: $($bodyContent.persistence.deleted_instances)"
            }
        }
        
        Remove-Item response.json -ErrorAction SilentlyContinue
    } else {
        Write-Host "Discovery trigger failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Discovery Trigger Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Check Current Instance Status
Write-Host "`nTest 4: Checking Current Instance Status" -ForegroundColor Yellow

try {
    Write-Host "Checking current status of tb-pg-db1..."
    
    $instanceStatus = aws dynamodb get-item --table-name "rds-inventory-prod" --key '{"instance_id":{"S":"tb-pg-db1"}}' --output json | ConvertFrom-Json
    
    if ($instanceStatus.Item) {
        Write-Host "Instance Status:" -ForegroundColor Green
        Write-Host "  Instance ID: $($instanceStatus.Item.instance_id.S)"
        Write-Host "  Status: $($instanceStatus.Item.status.S)"
        Write-Host "  Region: $($instanceStatus.Item.region.S)"
        Write-Host "  Account: $($instanceStatus.Item.account_id.S)"
        Write-Host "  Engine: $($instanceStatus.Item.engine.S)"
        Write-Host "  Instance Class: $($instanceStatus.Item.instance_class.S)"
        Write-Host "  Last Updated: $($instanceStatus.Item.last_updated.S)"
    } else {
        Write-Host "Instance tb-pg-db1 not found in inventory" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Instance status check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Check Lambda Function Environment Variables
Write-Host "`nTest 5: Checking Lambda Environment Variables" -ForegroundColor Yellow

try {
    Write-Host "Checking operations Lambda environment..."
    $opsEnv = aws lambda get-function-configuration --function-name "rds-operations-prod" --output json | ConvertFrom-Json
    
    if ($opsEnv.Environment.Variables) {
        Write-Host "Operations Lambda Environment Variables:" -ForegroundColor Green
        $opsEnv.Environment.Variables.PSObject.Properties | ForEach-Object {
            if ($_.Name -like "*TABLE*" -or $_.Name -like "*ACCOUNT*" -or $_.Name -like "*REGION*") {
                Write-Host "  $($_.Name): $($_.Value)"
            }
        }
    }
    
    Write-Host "`nChecking discovery Lambda environment..."
    $discEnv = aws lambda get-function-configuration --function-name "rds-discovery-prod" --output json | ConvertFrom-Json
    
    if ($discEnv.Environment.Variables) {
        Write-Host "Discovery Lambda Environment Variables:" -ForegroundColor Green
        $discEnv.Environment.Variables.PSObject.Properties | ForEach-Object {
            if ($_.Name -like "*TABLE*" -or $_.Name -like "*ACCOUNT*" -or $_.Name -like "*REGION*") {
                Write-Host "  $($_.Name): $($_.Value)"
            }
        }
    }
    
} catch {
    Write-Host "Environment check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nActual Operations Testing Complete!" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "- Instance operations (start/stop) should now work with proper environment variables" -ForegroundColor Yellow
Write-Host "- Discovery trigger should work and update the inventory" -ForegroundColor Yellow
Write-Host "- Check the results above to verify functionality" -ForegroundColor Yellow