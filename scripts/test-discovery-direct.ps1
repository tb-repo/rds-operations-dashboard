#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test Discovery Lambda Directly

.DESCRIPTION
Tests the discovery Lambda with a simple payload to see what's happening
#>

param(
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Testing Discovery Lambda Directly ===" -ForegroundColor Cyan

try {
    # Test with minimal payload
    Write-Info "Testing discovery with minimal payload..."
    
    $minimalPayload = @{
        action = "discover"
    } | ConvertTo-Json -Compress
    
    # Save payload to file for Lambda invoke
    $minimalPayload | Out-File -FilePath "discovery_payload.json" -Encoding UTF8
    
    # Invoke Lambda
    $result = aws lambda invoke `
        --function-name "rds-discovery-$Environment" `
        --payload file://discovery_payload.json `
        --region ap-southeast-1 `
        discovery_response.json 2>&1
    
    Write-Info "Lambda invoke result: $result"
    
    if (Test-Path "discovery_response.json") {
        $response = Get-Content "discovery_response.json" | ConvertFrom-Json
        Write-Info "Discovery response:"
        Write-Host ($response | ConvertTo-Json -Depth 5) -ForegroundColor White
        
        # Clean up
        Remove-Item "discovery_response.json" -Force
    }
    
    # Clean up payload file
    Remove-Item "discovery_payload.json" -Force
    
    # Check Lambda logs
    Write-Info "Checking recent Lambda logs..."
    
    $logStreams = aws logs describe-log-streams `
        --log-group-name "/aws/lambda/rds-discovery-$Environment" `
        --order-by LastEventTime `
        --descending `
        --max-items 1 `
        --region ap-southeast-1 `
        --output json 2>$null | ConvertFrom-Json
    
    if ($logStreams -and $logStreams.logStreams.Count -gt 0) {
        $latestStream = $logStreams.logStreams[0].logStreamName
        Write-Info "Latest log stream: $latestStream"
        
        $logEvents = aws logs get-log-events `
            --log-group-name "/aws/lambda/rds-discovery-$Environment" `
            --log-stream-name $latestStream `
            --region ap-southeast-1 `
            --output json 2>$null | ConvertFrom-Json
        
        if ($logEvents -and $logEvents.events.Count -gt 0) {
            Write-Info "Recent log events:"
            foreach ($event in $logEvents.events | Select-Object -Last 10) {
                $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($event.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
                Write-Host "[$timestamp] $($event.message)" -ForegroundColor Gray
            }
        }
    }
    
    # Check DynamoDB table structure
    Write-Info "Checking DynamoDB table structure..."
    
    $tableInfo = aws dynamodb describe-table `
        --table-name "RDSInstances-$Environment" `
        --region ap-southeast-1 `
        --output json 2>$null | ConvertFrom-Json
    
    if ($tableInfo) {
        Write-Success "DynamoDB table exists: $($tableInfo.Table.TableName)"
        Write-Info "Table status: $($tableInfo.Table.TableStatus)"
        Write-Info "Item count: $($tableInfo.Table.ItemCount)"
        
        # Check table schema
        Write-Info "Key schema:"
        foreach ($key in $tableInfo.Table.KeySchema) {
            Write-Info "  $($key.AttributeName) ($($key.KeyType))"
        }
    } else {
        Write-Error "DynamoDB table not found or not accessible"
    }
    
    # Test DynamoDB write permissions
    Write-Info "Testing DynamoDB write permissions..."
    
    $testItem = @{
        instance_id = @{ S = "test-instance-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
        account_id = @{ S = "876595225096" }
        region = @{ S = "ap-southeast-1" }
        engine = @{ S = "test" }
        status = @{ S = "test" }
        discovered_at = @{ S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        last_updated = @{ S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    }
    
    $putResult = aws dynamodb put-item `
        --table-name "RDSInstances-$Environment" `
        --item ($testItem | ConvertTo-Json -Compress) `
        --region ap-southeast-1 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "DynamoDB write test successful"
        
        # Clean up test item
        aws dynamodb delete-item `
            --table-name "RDSInstances-$Environment" `
            --key "{\"instance_id\":{\"S\":\"$($testItem.instance_id.S)\"}}" `
            --region ap-southeast-1 > $null 2>&1
    } else {
        Write-Warning "DynamoDB write test failed: $putResult"
    }
    
} catch {
    Write-Error "Error testing discovery: $($_.Exception.Message)"
}

Write-Host "`n=== Discovery Test Completed ===" -ForegroundColor Cyan