#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple Production Issues Diagnostic Script

.DESCRIPTION
Quick diagnostic for the three main production issues
#>

param(
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Production Issues Diagnostic ===" -ForegroundColor Cyan
Write-Info "Environment: $Environment"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$issuesFound = 0

# Issue 1: Check Error Statistics Lambda
Write-Host "`n--- Issue 1: Error Statistics 500 Errors ---"
try {
    $monitoringLambda = aws lambda get-function --function-name "rds-monitoring-dashboard-$Environment" --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
    
    if ($monitoringLambda) {
        Write-Success "Monitoring Lambda exists: $($monitoringLambda.Configuration.FunctionName)"
        
        # Check logs for errors
        $logGroup = "/aws/lambda/rds-monitoring-dashboard-$Environment"
        $streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
        
        if ($streams -and $streams.logStreams.Count -gt 0) {
            $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $streams.logStreams[0].logStreamName --limit 5 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
            
            $errors = $events.events | Where-Object { $_.message -match "ERROR|Exception|ImportError" }
            
            if ($errors.Count -gt 0) {
                Write-Error "Found $($errors.Count) errors in monitoring Lambda"
                $issuesFound++
                foreach ($error in $errors | Select-Object -First 2) {
                    Write-Warning "  Error: $($error.message.Substring(0, [Math]::Min(100, $error.message.Length)))..."
                }
            } else {
                Write-Success "No recent errors in monitoring Lambda logs"
            }
        }
    } else {
        Write-Error "Monitoring Lambda function not found"
        $issuesFound++
    }
} catch {
    Write-Error "Failed to check monitoring Lambda: $($_.Exception.Message)"
    $issuesFound++
}

# Issue 2: Check Discovery Lambda
Write-Host "`n--- Issue 2: Account Discovery Issues ---"
try {
    $discoveryLambda = aws lambda get-function --function-name "rds-discovery-$Environment" --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
    
    if ($discoveryLambda) {
        Write-Success "Discovery Lambda exists: $($discoveryLambda.Configuration.FunctionName)"
        
        # Check DynamoDB for recent discoveries
        $accounts = aws dynamodb scan --table-name "RDSInstances-$Environment" --region ap-southeast-1 --max-items 3 --output json 2>$null | ConvertFrom-Json
        
        if ($accounts -and $accounts.Items.Count -gt 0) {
            Write-Success "Found $($accounts.Items.Count) instances in database"
            
            # Check for recent updates
            $recentInstances = $accounts.Items | Where-Object { 
                $_.last_updated -and $_.last_updated.S -and 
                [DateTime]::Parse($_.last_updated.S) -gt (Get-Date).AddDays(-1)
            }
            
            if ($recentInstances.Count -eq 0) {
                Write-Warning "No instances discovered in the last 24 hours"
                $issuesFound++
            } else {
                Write-Success "Found $($recentInstances.Count) recently discovered instances"
            }
        } else {
            Write-Warning "No instances found in database"
            $issuesFound++
        }
    } else {
        Write-Error "Discovery Lambda function not found"
        $issuesFound++
    }
} catch {
    Write-Error "Failed to check discovery: $($_.Exception.Message)"
    $issuesFound++
}

# Issue 3: Check Operations Lambda
Write-Host "`n--- Issue 3: Instance Operations Issues ---"
try {
    $operationsLambda = aws lambda get-function --function-name "rds-operations-$Environment" --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
    
    if ($operationsLambda) {
        Write-Success "Operations Lambda exists: $($operationsLambda.Configuration.FunctionName)"
        
        # Check logs for "not found" errors
        $logGroup = "/aws/lambda/rds-operations-$Environment"
        $streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
        
        if ($streams -and $streams.logStreams.Count -gt 0) {
            $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $streams.logStreams[0].logStreamName --limit 5 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
            
            $notFoundErrors = $events.events | Where-Object { $_.message -match "not found|InvalidDBInstanceIdentifier" }
            
            if ($notFoundErrors.Count -gt 0) {
                Write-Error "Found $($notFoundErrors.Count) 'instance not found' errors"
                $issuesFound++
                foreach ($error in $notFoundErrors | Select-Object -First 2) {
                    Write-Warning "  Error: $($error.message.Substring(0, [Math]::Min(100, $error.message.Length)))..."
                }
            } else {
                Write-Success "No recent 'instance not found' errors"
            }
        }
    } else {
        Write-Error "Operations Lambda function not found"
        $issuesFound++
    }
} catch {
    Write-Error "Failed to check operations Lambda: $($_.Exception.Message)"
    $issuesFound++
}

# Summary
Write-Host "`n=== Diagnostic Summary ===" -ForegroundColor Cyan
if ($issuesFound -eq 0) {
    Write-Success "No issues detected!"
} else {
    Write-Warning "Found $issuesFound issues that need attention"
}

Write-Host "`nRecommended Actions:" -ForegroundColor Yellow
Write-Host "1. For error statistics 500 errors: Check monitoring Lambda dependencies" -ForegroundColor White
Write-Host "2. For discovery issues: Run manual discovery and check permissions" -ForegroundColor White
Write-Host "3. For operations issues: Verify instance IDs and cross-account access" -ForegroundColor White

exit $issuesFound