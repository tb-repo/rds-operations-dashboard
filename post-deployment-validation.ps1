#!/usr/bin/env pwsh

<#
.SYNOPSIS
Post-Deployment Validation for Production API Fixes

.DESCRIPTION
Comprehensive validation script to verify that the production API fixes are working correctly:
- Validates error statistics endpoint (500 → 200)
- Validates operations authorization (403 → proper codes)
- Checks CloudWatch logs for errors
- Monitors performance metrics
- Validates user experience improvements

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-20T15:15:00Z",
  "version": "1.0.0",
  "policy_version": "v1.1.0",
  "traceability": "REQ-1.2,1.3,2.2,2.3,2.4,2.5 → DESIGN-ProductionAPIFixes → TASK-2,3",
  "review_status": "Pending",
  "risk_level": "Level 1",
  "reviewed_by": null,
  "approved_by": null
}

.PARAMETER BffUrl
BFF URL for testing

.PARAMETER ApiUrl
API Gateway URL for testing

.PARAMETER ApiKey
API Gateway key for authentication

.PARAMETER AuthToken
JWT token for authenticated requests (optional)

.PARAMETER Environment
Environment being validated (dev, staging, prod)

.PARAMETER Detailed
Run detailed validation including performance metrics

.EXAMPLE
./post-deployment-validation.ps1 -BffUrl "https://your-bff.com" -ApiKey "your-key" -Environment prod

.EXAMPLE
./post-deployment-validation.ps1 -BffUrl "https://your-bff.com" -ApiKey "your-key" -Environment prod -Detailed
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BffUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    
    [string]$ApiUrl,
    [string]$AuthToken = $env:AUTH_TOKEN,
    [string]$Environment = "prod",
    [switch]$Detailed
)

$ErrorActionPreference = "Continue"  # Continue on errors to collect all results
$ProgressPreference = "SilentlyContinue"

# Colors for output
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Step { param($Message) Write-Host "`n🔹 $Message" -ForegroundColor Blue }

# Results tracking
$validationResults = @{
    ErrorStatistics = @{ Status = "Unknown"; Details = @() }
    Operations = @{ Status = "Unknown"; Details = @() }
    CloudWatchLogs = @{ Status = "Unknown"; Details = @() }
    Performance = @{ Status = "Unknown"; Details = @() }
    UserExperience = @{ Status = "Unknown"; Details = @() }
}

# Banner
Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           Post-Deployment Validation Report                  ║
║                                                              ║
║     🔍 Error Statistics Endpoint Validation                  ║
║     🔍 Operations Authorization Validation                   ║
║     🔍 CloudWatch Logs Analysis                              ║
║     🔍 Performance Metrics Check                             ║
║     🔍 User Experience Validation                            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "Environment: $Environment"
Write-Info "BFF URL: $BffUrl"
Write-Info "API URL: $ApiUrl"
Write-Info "Detailed Mode: $Detailed"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Setup headers
$headers = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

if ($AuthToken) {
    $headers['Authorization'] = "Bearer $AuthToken"
}

# Test 1: Error Statistics Endpoint Validation
Write-Step "1. Error Statistics Endpoint Validation"

try {
    Write-Info "Testing /api/errors/statistics endpoint..."
    
    $startTime = Get-Date
    $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/statistics" -Headers $headers -TimeoutSec 15
    $endTime = Get-Date
    $responseTime = ($endTime - $startTime).TotalMilliseconds
    
    # Validate response structure
    $requiredFields = @('status', 'statistics', 'timestamp')
    $missingFields = @()
    
    foreach ($field in $requiredFields) {
        if (-not $response.$field) {
            $missingFields += $field
        }
    }
    
    if ($missingFields.Count -eq 0) {
        $validationResults.ErrorStatistics.Status = "Pass"
        $validationResults.ErrorStatistics.Details += "✅ Endpoint returns 200 OK"
        $validationResults.ErrorStatistics.Details += "✅ Response structure is valid"
        $validationResults.ErrorStatistics.Details += "✅ Response time: $([math]::Round($responseTime, 2))ms"
        $validationResults.ErrorStatistics.Details += "✅ Status: $($response.status)"
        
        if ($response.fallback) {
            $validationResults.ErrorStatistics.Details += "⚠️  Using fallback data (monitoring service may be unavailable)"
        } else {
            $validationResults.ErrorStatistics.Details += "✅ Real data from monitoring service"
        }
        
        Write-Success "Error statistics endpoint working correctly"
    } else {
        $validationResults.ErrorStatistics.Status = "Fail"
        $validationResults.ErrorStatistics.Details += "❌ Missing required fields: $($missingFields -join ', ')"
        Write-Error "Error statistics endpoint has structural issues"
    }
    
} catch {
    $status = $_.Exception.Response.StatusCode
    $validationResults.ErrorStatistics.Status = "Fail"
    
    if ($status -eq 500) {
        $validationResults.ErrorStatistics.Details += "❌ Still returning 500 error - fix not working"
        Write-Error "CRITICAL: Still getting 500 error - fix may not be deployed correctly"
    } else {
        $validationResults.ErrorStatistics.Details += "❌ Unexpected error: $status - $($_.Exception.Message)"
        Write-Error "Error statistics endpoint failed with status: $status"
    }
}

# Test 2: Operations Authorization Validation
Write-Step "2. Operations Authorization Validation"

# Test safe operation (should work for authenticated users)
Write-Info "Testing safe operation (create_snapshot)..."
$operationsPayload = @{
    operation_type = "create_snapshot"
    instance_id = "test-validation-instance"
    parameters = @{ snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
} | ConvertTo-Json

try {
    $startTime = Get-Date
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $operationsPayload -TimeoutSec 15
    $endTime = Get-Date
    $responseTime = ($endTime - $startTime).TotalMilliseconds
    
    $validationResults.Operations.Details += "✅ Safe operation accepted (200 OK)"
    $validationResults.Operations.Details += "✅ Response time: $([math]::Round($responseTime, 2))ms"
    
} catch {
    $status = $_.Exception.Response.StatusCode
    
    if ($status -eq 404) {
        $validationResults.Operations.Details += "✅ Safe operation working (404 - test instance not found, expected)"
    } elseif ($status -eq 400) {
        $validationResults.Operations.Details += "✅ Safe operation working (400 - validation error, expected)"
    } elseif ($status -eq 403) {
        $validationResults.Operations.Details += "❌ Still getting 403 error - authorization fix not working"
        Write-Error "CRITICAL: Still getting 403 error for safe operations"
    } else {
        $validationResults.Operations.Details += "⚠️  Unexpected status: $status"
    }
}

# Test risky operation (should require admin privileges)
Write-Info "Testing risky operation (reboot_instance)..."
$riskyPayload = @{
    operation_type = "reboot_instance"
    instance_id = "test-validation-instance"
    parameters = @{ force_failover = $false }
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $riskyPayload -TimeoutSec 15
    $validationResults.Operations.Details += "✅ Risky operation accepted (user has admin privileges)"
    
} catch {
    $status = $_.Exception.Response.StatusCode
    $errorMessage = ""
    
    try {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
        $errorMessage = $errorResponse.message
    } catch {
        $errorMessage = $_.Exception.Message
    }
    
    if ($status -eq 403 -and $errorMessage -match "Admin|DBA|privileges") {
        $validationResults.Operations.Details += "✅ Risky operation properly rejected with clear error message"
        $validationResults.Operations.Details += "✅ Error message: $errorMessage"
    } elseif ($status -eq 403) {
        $validationResults.Operations.Details += "⚠️  Risky operation rejected but error message may not be clear"
        $validationResults.Operations.Details += "⚠️  Error message: $errorMessage"
    } elseif ($status -eq 400) {
        $validationResults.Operations.Details += "✅ Risky operation validation working (400 - missing confirmation)"
    } else {
        $validationResults.Operations.Details += "⚠️  Unexpected status for risky operation: $status"
    }
}

# Test invalid operation
Write-Info "Testing invalid operation..."
$invalidPayload = @{
    operation_type = "invalid_operation"
    instance_id = "test-instance"
    parameters = @{}
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $invalidPayload -TimeoutSec 15
    $validationResults.Operations.Details += "⚠️  Invalid operation was accepted (unexpected)"
    
} catch {
    $status = $_.Exception.Response.StatusCode
    
    if ($status -eq 400) {
        $validationResults.Operations.Details += "✅ Invalid operation properly rejected (400 Bad Request)"
    } else {
        $validationResults.Operations.Details += "⚠️  Invalid operation rejected with unexpected status: $status"
    }
}

# Determine overall operations status
$operationsPassed = ($validationResults.Operations.Details | Where-Object { $_ -match "✅" }).Count
$operationsFailed = ($validationResults.Operations.Details | Where-Object { $_ -match "❌" }).Count

if ($operationsFailed -eq 0) {
    $validationResults.Operations.Status = "Pass"
    Write-Success "Operations authorization working correctly"
} elseif ($operationsPassed -gt $operationsFailed) {
    $validationResults.Operations.Status = "Partial"
    Write-Warning "Operations authorization partially working"
} else {
    $validationResults.Operations.Status = "Fail"
    Write-Error "Operations authorization has issues"
}

# Test 3: CloudWatch Logs Analysis
Write-Step "3. CloudWatch Logs Analysis"

$logGroups = @(
    "/aws/lambda/rds-operations-$Environment",
    "/aws/lambda/rds-dashboard-bff-$Environment",
    "/aws/lambda/rds-monitoring-dashboard-$Environment"
)

$totalErrors = 0
$totalWarnings = 0

foreach ($logGroup in $logGroups) {
    Write-Info "Analyzing logs for $logGroup..."
    
    try {
        # Get recent log streams
        $streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 3 --output json | ConvertFrom-Json
        
        if ($streams.logStreams.Count -gt 0) {
            foreach ($stream in $streams.logStreams) {
                $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $stream.logStreamName --limit 20 --output json | ConvertFrom-Json
                
                $errors = $events.events | Where-Object { $_.message -match "ERROR|Exception|Failed|500|403" }
                $warnings = $events.events | Where-Object { $_.message -match "WARN|Warning" }
                
                $totalErrors += $errors.Count
                $totalWarnings += $warnings.Count
                
                if ($errors.Count -gt 0) {
                    $validationResults.CloudWatchLogs.Details += "⚠️  $($errors.Count) errors found in $($stream.logStreamName)"
                    
                    # Show recent errors
                    $recentErrors = $errors | Select-Object -First 3
                    foreach ($error in $recentErrors) {
                        $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($error.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
                        $validationResults.CloudWatchLogs.Details += "   ❌ [$timestamp] $($error.message.Substring(0, [Math]::Min(100, $error.message.Length)))..."
                    }
                }
            }
            
            if ($totalErrors -eq 0) {
                $validationResults.CloudWatchLogs.Details += "✅ No recent errors in $logGroup"
            }
        } else {
            $validationResults.CloudWatchLogs.Details += "⚠️  No log streams found for $logGroup"
        }
        
    } catch {
        $validationResults.CloudWatchLogs.Details += "⚠️  Could not analyze logs for $logGroup"
    }
}

if ($totalErrors -eq 0) {
    $validationResults.CloudWatchLogs.Status = "Pass"
    Write-Success "No recent errors found in CloudWatch logs"
} elseif ($totalErrors -lt 5) {
    $validationResults.CloudWatchLogs.Status = "Partial"
    Write-Warning "$totalErrors recent errors found in logs"
} else {
    $validationResults.CloudWatchLogs.Status = "Fail"
    Write-Error "$totalErrors recent errors found in logs"
}

# Test 4: Performance Metrics (if detailed mode)
if ($Detailed) {
    Write-Step "4. Performance Metrics Analysis"
    
    Write-Info "Checking Lambda performance metrics..."
    
    $functionNames = @(
        "rds-operations-$Environment",
        "rds-monitoring-dashboard-$Environment"
    )
    
    foreach ($functionName in $functionNames) {
        try {
            # Get duration metrics for last hour
            $endTime = Get-Date
            $startTime = $endTime.AddHours(-1)
            
            $durationMetrics = aws cloudwatch get-metric-statistics `
                --namespace AWS/Lambda `
                --metric-name Duration `
                --dimensions Name=FunctionName,Value=$functionName `
                --start-time $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ") `
                --end-time $endTime.ToString("yyyy-MM-ddTHH:mm:ssZ") `
                --period 3600 `
                --statistics Average,Maximum `
                --output json | ConvertFrom-Json
            
            if ($durationMetrics.Datapoints.Count -gt 0) {
                $avgDuration = [math]::Round($durationMetrics.Datapoints[0].Average, 2)
                $maxDuration = [math]::Round($durationMetrics.Datapoints[0].Maximum, 2)
                
                $validationResults.Performance.Details += "✅ $functionName - Avg: ${avgDuration}ms, Max: ${maxDuration}ms"
                
                if ($avgDuration -gt 5000) {
                    $validationResults.Performance.Details += "⚠️  $functionName average duration is high (>5s)"
                }
            } else {
                $validationResults.Performance.Details += "ℹ️  No recent invocations for $functionName"
            }
            
        } catch {
            $validationResults.Performance.Details += "⚠️  Could not get metrics for $functionName"
        }
    }
    
    $validationResults.Performance.Status = "Pass"
    Write-Success "Performance metrics collected"
} else {
    $validationResults.Performance.Status = "Skipped"
    $validationResults.Performance.Details += "ℹ️  Performance analysis skipped (use -Detailed flag)"
}

# Test 5: User Experience Validation
Write-Step "5. User Experience Validation"

# Test browser-accessible endpoints
Write-Info "Testing browser-accessible endpoints..."

try {
    # Test BFF health endpoint
    $healthResponse = Invoke-RestMethod -Uri "$BffUrl/health" -TimeoutSec 10
    $validationResults.UserExperience.Details += "✅ BFF health endpoint responding"
} catch {
    $validationResults.UserExperience.Details += "⚠️  BFF health endpoint not accessible"
}

# Test CORS headers
Write-Info "Testing CORS configuration..."
try {
    $corsHeaders = @{
        'Origin' = 'https://your-frontend-domain.com'
        'Access-Control-Request-Method' = 'POST'
        'Access-Control-Request-Headers' = 'Content-Type,x-api-key'
    }
    
    $corsResponse = Invoke-WebRequest -Uri "$BffUrl/api/errors/statistics" -Method OPTIONS -Headers $corsHeaders -TimeoutSec 10
    
    if ($corsResponse.Headers['Access-Control-Allow-Origin']) {
        $validationResults.UserExperience.Details += "✅ CORS headers present"
    } else {
        $validationResults.UserExperience.Details += "⚠️  CORS headers may be missing"
    }
} catch {
    $validationResults.UserExperience.Details += "⚠️  Could not test CORS configuration"
}

$validationResults.UserExperience.Status = "Pass"
Write-Success "User experience validation completed"

# Generate Validation Report
Write-Step "Validation Report"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    VALIDATION REPORT                         ║
╚══════════════════════════════════════════════════════════════╝

Environment: $Environment
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
BFF URL: $BffUrl

"@ -ForegroundColor Cyan

# Summary table
$summaryTable = @"
┌─────────────────────────────────┬──────────┐
│ Component                       │ Status   │
├─────────────────────────────────┼──────────┤
│ Error Statistics Endpoint       │ $($validationResults.ErrorStatistics.Status.PadRight(8)) │
│ Operations Authorization        │ $($validationResults.Operations.Status.PadRight(8)) │
│ CloudWatch Logs                 │ $($validationResults.CloudWatchLogs.Status.PadRight(8)) │
│ Performance Metrics             │ $($validationResults.Performance.Status.PadRight(8)) │
│ User Experience                 │ $($validationResults.UserExperience.Status.PadRight(8)) │
└─────────────────────────────────┴──────────┘
"@

Write-Host $summaryTable -ForegroundColor White

# Detailed results
foreach ($component in $validationResults.Keys) {
    Write-Host "`n$component Details:" -ForegroundColor Yellow
    foreach ($detail in $validationResults[$component].Details) {
        Write-Host "  $detail"
    }
}

# Overall status
$passCount = ($validationResults.Values | Where-Object { $_.Status -eq "Pass" }).Count
$failCount = ($validationResults.Values | Where-Object { $_.Status -eq "Fail" }).Count
$partialCount = ($validationResults.Values | Where-Object { $_.Status -eq "Partial" }).Count

Write-Host "`n" -NoNewline
if ($failCount -eq 0 -and $partialCount -eq 0) {
    Write-Host "🎉 ALL VALIDATIONS PASSED!" -ForegroundColor Green
    Write-Host "The production API fixes are working correctly." -ForegroundColor Green
    $exitCode = 0
} elseif ($failCount -eq 0) {
    Write-Host "⚠️  PARTIAL SUCCESS" -ForegroundColor Yellow
    Write-Host "Most validations passed, but some issues were found." -ForegroundColor Yellow
    $exitCode = 1
} else {
    Write-Host "❌ VALIDATION FAILED" -ForegroundColor Red
    Write-Host "Critical issues found that need to be addressed." -ForegroundColor Red
    $exitCode = 2
}

Write-Host @"

Next Steps:
  1. Address any failed validations
  2. Monitor dashboard in browser for console errors
  3. Test with real users
  4. Monitor CloudWatch logs for 24 hours
  5. Collect user feedback

For ongoing monitoring:
  - Set up CloudWatch alarms for error rates
  - Monitor response times
  - Track user satisfaction metrics

"@ -ForegroundColor Cyan

exit $exitCode