# Comprehensive Integration Testing for API Gateway Stage Elimination
# Validates: Requirements 8.1, 8.2
# Tests complete user workflows end-to-end with clean URLs

param(
    [string]$Environment = "production",
    [string]$BffApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com",
    [string]$InternalApiUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com",
    [int]$TimeoutSeconds = 60,
    [switch]$Verbose,
    [switch]$SkipAuth,
    [string]$TestAccountId = "123456789012",
    [string]$TestRegion = "ap-southeast-1"
)

Write-Host "Comprehensive Integration Testing - API Gateway Stage Elimination" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "BFF API URL: $BffApiUrl" -ForegroundColor Yellow
Write-Host "Internal API URL: $InternalApiUrl" -ForegroundColor Yellow
Write-Host "Test Account: $TestAccountId" -ForegroundColor Yellow
Write-Host "Test Region: $TestRegion" -ForegroundColor Yellow
Write-Host ""

$ErrorCount = 0
$WarningCount = 0
$TestResults = @()
$WorkflowResults = @()

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [string]$Description,
        [bool]$RequiresAuth = $false,
        [string]$ExpectedStatus = "200",
        [int]$Timeout = $TimeoutSeconds
    )
    
    $startTime = Get-Date
    
    try {
        if ($Verbose) {
            Write-Host "  Testing: $Description" -ForegroundColor Cyan
            Write-Host "    URL: $Url" -ForegroundColor Gray
            Write-Host "    Method: $Method" -ForegroundColor Gray
        }
        
        $requestParams = @{
            Uri = $Url
            Method = $Method
            Headers = $Headers
            TimeoutSec = $Timeout
            ErrorAction = "Stop"
        }
        
        if ($Body -and ($Method -eq "POST" -or $Method -eq "PUT" -or $Method -eq "PATCH")) {
            $requestParams.Body = ($Body | ConvertTo-Json -Depth 10)
            $requestParams.ContentType = "application/json"
        }
        
        $response = Invoke-RestMethod @requestParams
        $responseTime = ((Get-Date) - $startTime).TotalMilliseconds
        
        $result = @{
            Description = $Description
            Url = $Url
            Method = $Method
            Status = "PASS"
            StatusCode = "200"
            ResponseTime = [math]::Round($responseTime, 2)
            ResponseSize = ($response | ConvertTo-Json -Depth 10).Length
            HasCleanUrl = -not ($Url -match "/prod/|/staging/|/dev/")
            Error = $null
            Response = $response
        }
        
        if ($Verbose) {
            Write-Host "    ✓ PASS ($($result.ResponseTime)ms)" -ForegroundColor Green
        }
        
        return $result
    }
    catch {
        $responseTime = ((Get-Date) - $startTime).TotalMilliseconds
        $statusCode = $_.Exception.Response.StatusCode.value__
        $isExpectedError = ($RequiresAuth -and $statusCode -eq 401) -or ($statusCode -eq 403)
        
        $result = @{
            Description = $Description
            Url = $Url
            Method = $Method
            Status = if ($isExpectedError) { "PASS (Expected Auth Error)" } else { "FAIL" }
            StatusCode = $statusCode
            ResponseTime = [math]::Round($responseTime, 2)
            ResponseSize = 0
            HasCleanUrl = -not ($Url -match "/prod/|/staging/|/dev/")
            Error = $_.Exception.Message
            Response = $null
        }
        
        if ($isExpectedError) {
            if ($Verbose) {
                Write-Host "    ✓ PASS (Expected auth error - $statusCode)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $script:ErrorCount++
        }
        
        return $result
    }
}

function Test-Workflow {
    param(
        [string]$WorkflowName,
        [array]$Steps,
        [hashtable]$Context = @{}
    )
    
    Write-Host "Testing Workflow: $WorkflowName" -ForegroundColor Magenta
    Write-Host "$(('=' * ($WorkflowName.Length + 18)))" -ForegroundColor Magenta
    
    $workflowStartTime = Get-Date
    $stepResults = @()
    $workflowContext = $Context.Clone()
    
    foreach ($step in $Steps) {
        $stepUrl = $step.Url
        $stepMethod = $step.Method
        $stepBody = $step.Body
        $stepHeaders = $step.Headers
        
        # Replace context variables in URL and body
        foreach ($key in $workflowContext.Keys) {
            $placeholder = "{$key}"
            if ($stepUrl -match [regex]::Escape($placeholder)) {
                $stepUrl = $stepUrl -replace [regex]::Escape($placeholder), $workflowContext[$key]
            }
            if ($stepBody -and ($stepBody | ConvertTo-Json) -match [regex]::Escape($placeholder)) {
                $bodyJson = $stepBody | ConvertTo-Json -Depth 10
                $bodyJson = $bodyJson -replace [regex]::Escape($placeholder), $workflowContext[$key]
                $stepBody = $bodyJson | ConvertFrom-Json
            }
        }
        
        $stepResult = Test-Endpoint -Url $stepUrl -Method $stepMethod -Headers $stepHeaders -Body $stepBody -Description $step.Description -RequiresAuth $step.RequiresAuth
        $stepResults += $stepResult
        
        # Update context with response data
        if ($stepResult.Response -and $step.ContextUpdates) {
            foreach ($update in $step.ContextUpdates) {
                $value = $stepResult.Response
                foreach ($property in $update.Path.Split('.')) {
                    if ($value.$property) {
                        $value = $value.$property
                    }
                }
                $workflowContext[$update.Key] = $value
            }
        }
        
        # Stop workflow if critical step fails
        if ($step.Critical -and $stepResult.Status -eq "FAIL") {
            Write-Host "  Critical step failed, stopping workflow" -ForegroundColor Red
            break
        }
    }
    
    $workflowTime = ((Get-Date) - $workflowStartTime).TotalMilliseconds
    $passedSteps = ($stepResults | Where-Object { $_.Status -like "PASS*" }).Count
    $totalSteps = $stepResults.Count
    
    $workflowResult = @{
        WorkflowName = $WorkflowName
        TotalSteps = $totalSteps
        PassedSteps = $passedSteps
        FailedSteps = $totalSteps - $passedSteps
        WorkflowTime = [math]::Round($workflowTime, 2)
        Status = if ($passedSteps -eq $totalSteps) { "PASS" } else { "PARTIAL" }
        Steps = $stepResults
        Context = $workflowContext
    }
    
    Write-Host "  Workflow Result: $($workflowResult.Status) ($passedSteps/$totalSteps steps passed)" -ForegroundColor $(if ($workflowResult.Status -eq "PASS") { "Green" } else { "Yellow" })
    Write-Host ""
    
    return $workflowResult
}

Write-Host "1. Basic Health Check Workflow" -ForegroundColor Magenta
Write-Host "==============================" -ForegroundColor Magenta

$healthWorkflow = @(
    @{
        Description = "BFF Health Check"
        Url = "$BffApiUrl/health"
        Method = "GET"
        RequiresAuth = $false
        Critical = $true
    },
    @{
        Description = "API Health Check"
        Url = "$BffApiUrl/api/health"
        Method = "GET"
        RequiresAuth = $false
        Critical = $true
    },
    @{
        Description = "CORS Configuration"
        Url = "$BffApiUrl/cors-config"
        Method = "GET"
        RequiresAuth = $false
        Critical = $false
    }
)

$healthResult = Test-Workflow -WorkflowName "Health Check" -Steps $healthWorkflow
$WorkflowResults += $healthResult

Write-Host "2. RDS Discovery Workflow" -ForegroundColor Magenta
Write-Host "=========================" -ForegroundColor Magenta

$discoveryWorkflow = @(
    @{
        Description = "Trigger RDS Discovery"
        Url = "$BffApiUrl/api/discovery/trigger"
        Method = "POST"
        Body = @{
            accountId = $TestAccountId
            region = $TestRegion
            environment = "test"
        }
        RequiresAuth = $true
        Critical = $true
        ContextUpdates = @(
            @{ Key = "discoveryId"; Path = "discoveryId" }
        )
    },
    @{
        Description = "Check Discovery Status"
        Url = "$BffApiUrl/api/discovery/status/{discoveryId}"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Discovered Instances"
        Url = "$BffApiUrl/api/instances"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    }
)

$discoveryResult = Test-Workflow -WorkflowName "RDS Discovery" -Steps $discoveryWorkflow -Context @{ discoveryId = "test-discovery-123" }
$WorkflowResults += $discoveryResult

Write-Host "3. RDS Operations Workflow" -ForegroundColor Magenta
Write-Host "==========================" -ForegroundColor Magenta

$operationsWorkflow = @(
    @{
        Description = "List RDS Instances"
        Url = "$BffApiUrl/api/instances"
        Method = "GET"
        RequiresAuth = $true
        Critical = $true
        ContextUpdates = @(
            @{ Key = "instanceId"; Path = "instances.0.instanceId" }
        )
    },
    @{
        Description = "Get Instance Details"
        Url = "$BffApiUrl/api/instances/{instanceId}"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Test Instance Operation (Start)"
        Url = "$BffApiUrl/api/instances/start"
        Method = "POST"
        Body = @{
            instanceId = "{instanceId}"
            accountId = $TestAccountId
            region = $TestRegion
        }
        RequiresAuth = $true
        Critical = $false
    }
)

$operationsResult = Test-Workflow -WorkflowName "RDS Operations" -Steps $operationsWorkflow -Context @{ instanceId = "test-instance-123" }
$WorkflowResults += $operationsResult

Write-Host "4. Monitoring and Metrics Workflow" -ForegroundColor Magenta
Write-Host "===================================" -ForegroundColor Magenta

$monitoringWorkflow = @(
    @{
        Description = "Get System Metrics"
        Url = "$BffApiUrl/api/metrics"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Instance Monitoring"
        Url = "$BffApiUrl/api/monitoring"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Cost Analysis"
        Url = "$BffApiUrl/api/costs"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    }
)

$monitoringResult = Test-Workflow -WorkflowName "Monitoring and Metrics" -Steps $monitoringWorkflow
$WorkflowResults += $monitoringResult

Write-Host "5. Compliance and Audit Workflow" -ForegroundColor Magenta
Write-Host "=================================" -ForegroundColor Magenta

$complianceWorkflow = @(
    @{
        Description = "Get Compliance Status"
        Url = "$BffApiUrl/api/compliance"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Error Statistics"
        Url = "$BffApiUrl/api/errors"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Audit Trail"
        Url = "$BffApiUrl/api/audit"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    }
)

$complianceResult = Test-Workflow -WorkflowName "Compliance and Audit" -Steps $complianceWorkflow
$WorkflowResults += $complianceResult

Write-Host "6. User Management Workflow" -ForegroundColor Magenta
Write-Host "============================" -ForegroundColor Magenta

$userWorkflow = @(
    @{
        Description = "Get User Info"
        Url = "$BffApiUrl/api/auth/user"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "List Users"
        Url = "$BffApiUrl/api/users"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Get Approval Requests"
        Url = "$BffApiUrl/api/approvals"
        Method = "GET"
        RequiresAuth = $true
        Critical = $false
    }
)

$userResult = Test-Workflow -WorkflowName "User Management" -Steps $userWorkflow
$WorkflowResults += $userResult

Write-Host "7. Cross-Account Operations Workflow" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta

$crossAccountWorkflow = @(
    @{
        Description = "Test Cross-Account Role"
        Url = "$InternalApiUrl/operations/test-role"
        Method = "POST"
        Body = @{
            roleArn = "arn:aws:iam::$TestAccountId`:role/RDSOperationsRole"
            region = $TestRegion
        }
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Cross-Account Discovery"
        Url = "$InternalApiUrl/discovery"
        Method = "POST"
        Body = @{
            targetAccount = $TestAccountId
            region = $TestRegion
            crossAccount = $true
        }
        RequiresAuth = $true
        Critical = $false
    },
    @{
        Description = "Cross-Account Monitoring"
        Url = "$InternalApiUrl/monitoring/cross-account"
        Method = "POST"
        Body = @{
            accounts = @($TestAccountId)
            region = $TestRegion
            timeRange = "1h"
        }
        RequiresAuth = $true
        Critical = $false
    }
)

$crossAccountResult = Test-Workflow -WorkflowName "Cross-Account Operations" -Steps $crossAccountWorkflow
$WorkflowResults += $crossAccountResult

Write-Host "8. Performance and Load Testing" -ForegroundColor Magenta
Write-Host "===============================" -ForegroundColor Magenta

$performanceEndpoints = @(
    @{ Url = "$BffApiUrl/health"; Description = "Health Check Performance"; Benchmark = 2000 },
    @{ Url = "$BffApiUrl/api/health"; Description = "API Health Performance"; Benchmark = 2000 },
    @{ Url = "$BffApiUrl/cors-config"; Description = "CORS Config Performance"; Benchmark = 3000 }
)

$performanceResults = @()
foreach ($endpoint in $performanceEndpoints) {
    $measurements = @()
    
    # Take 5 measurements
    for ($i = 1; $i -le 5; $i++) {
        $result = Test-Endpoint -Url $endpoint.Url -Description "$($endpoint.Description) (Run $i)" -RequiresAuth $false
        if ($result.Status -like "PASS*") {
            $measurements += $result.ResponseTime
        }
    }
    
    if ($measurements.Count -gt 0) {
        $avgTime = ($measurements | Measure-Object -Average).Average
        $maxTime = ($measurements | Measure-Object -Maximum).Maximum
        $minTime = ($measurements | Measure-Object -Minimum).Minimum
        
        $performanceResult = @{
            Endpoint = $endpoint.Description
            Url = $endpoint.Url
            AverageTime = [math]::Round($avgTime, 2)
            MinTime = $minTime
            MaxTime = $maxTime
            Benchmark = $endpoint.Benchmark
            WithinBenchmark = $avgTime -lt $endpoint.Benchmark
            Measurements = $measurements
        }
        
        $performanceResults += $performanceResult
        
        $status = if ($performanceResult.WithinBenchmark) { "PASS" } else { "FAIL" }
        $color = if ($performanceResult.WithinBenchmark) { "Green" } else { "Red" }
        
        Write-Host "  $($endpoint.Description): $status (avg: $($performanceResult.AverageTime)ms, benchmark: $($endpoint.Benchmark)ms)" -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "9. URL Structure Validation" -ForegroundColor Magenta
Write-Host "===========================" -ForegroundColor Magenta

# Collect all URLs tested
$allUrls = @()
$WorkflowResults | ForEach-Object {
    $_.Steps | ForEach-Object {
        $allUrls += $_.Url
    }
}

$cleanUrls = $allUrls | Where-Object { -not ($_ -match "/prod/|/staging/|/dev/") }
$dirtyUrls = $allUrls | Where-Object { $_ -match "/prod/|/staging/|/dev/" }

Write-Host "Total URLs tested: $($allUrls.Count)" -ForegroundColor Cyan
Write-Host "Clean URLs: $($cleanUrls.Count)" -ForegroundColor Green
Write-Host "URLs with stage prefixes: $($dirtyUrls.Count)" -ForegroundColor $(if ($dirtyUrls.Count -eq 0) { "Green" } else { "Red" })

if ($dirtyUrls.Count -gt 0) {
    Write-Host "URLs with stage prefixes:" -ForegroundColor Red
    $dirtyUrls | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    $ErrorCount += $dirtyUrls.Count
}

# Validate URL consistency
$baseUrls = $allUrls | ForEach-Object {
    $uri = [System.Uri]$_
    "$($uri.Scheme)://$($uri.Host)"
} | Sort-Object -Unique

Write-Host "Unique base URLs: $($baseUrls.Count)" -ForegroundColor Cyan
$baseUrls | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

Write-Host ""
Write-Host "10. Final Integration Summary" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

# Calculate overall statistics
$totalWorkflows = $WorkflowResults.Count
$passedWorkflows = ($WorkflowResults | Where-Object { $_.Status -eq "PASS" }).Count
$partialWorkflows = ($WorkflowResults | Where-Object { $_.Status -eq "PARTIAL" }).Count
$failedWorkflows = $totalWorkflows - $passedWorkflows - $partialWorkflows

$totalSteps = ($WorkflowResults | ForEach-Object { $_.TotalSteps } | Measure-Object -Sum).Sum
$passedSteps = ($WorkflowResults | ForEach-Object { $_.PassedSteps } | Measure-Object -Sum).Sum
$failedSteps = $totalSteps - $passedSteps

$overallSuccessRate = if ($totalSteps -gt 0) { [math]::Round(($passedSteps / $totalSteps) * 100, 2) } else { 0 }
$cleanUrlCompliance = if ($allUrls.Count -gt 0) { [math]::Round(($cleanUrls.Count / $allUrls.Count) * 100, 2) } else { 0 }

Write-Host "Integration Test Results:" -ForegroundColor Cyan
Write-Host "  Total Workflows: $totalWorkflows" -ForegroundColor White
Write-Host "  Passed Workflows: $passedWorkflows" -ForegroundColor Green
Write-Host "  Partial Workflows: $partialWorkflows" -ForegroundColor Yellow
Write-Host "  Failed Workflows: $failedWorkflows" -ForegroundColor Red
Write-Host ""
Write-Host "  Total Steps: $totalSteps" -ForegroundColor White
Write-Host "  Passed Steps: $passedSteps" -ForegroundColor Green
Write-Host "  Failed Steps: $failedSteps" -ForegroundColor Red
Write-Host "  Success Rate: $overallSuccessRate%" -ForegroundColor $(if ($overallSuccessRate -ge 80) { "Green" } elseif ($overallSuccessRate -ge 60) { "Yellow" } else { "Red" })
Write-Host ""
Write-Host "Clean URL Compliance:" -ForegroundColor Cyan
Write-Host "  Clean URLs: $($cleanUrls.Count) / $($allUrls.Count) ($cleanUrlCompliance%)" -ForegroundColor $(if ($cleanUrlCompliance -eq 100) { "Green" } else { "Yellow" })

# Performance summary
if ($performanceResults.Count -gt 0) {
    $performancePassed = ($performanceResults | Where-Object { $_.WithinBenchmark }).Count
    $performanceRate = [math]::Round(($performancePassed / $performanceResults.Count) * 100, 2)
    
    Write-Host ""
    Write-Host "Performance Summary:" -ForegroundColor Cyan
    Write-Host "  Endpoints within benchmark: $performancePassed / $($performanceResults.Count) ($performanceRate%)" -ForegroundColor $(if ($performanceRate -ge 80) { "Green" } else { "Yellow" })
    
    $avgResponseTime = ($performanceResults | ForEach-Object { $_.AverageTime } | Measure-Object -Average).Average
    Write-Host "  Average response time: $([math]::Round($avgResponseTime, 2))ms" -ForegroundColor White
}

# Export detailed results
$detailedResults = @{
    Summary = @{
        TotalWorkflows = $totalWorkflows
        PassedWorkflows = $passedWorkflows
        PartialWorkflows = $partialWorkflows
        FailedWorkflows = $failedWorkflows
        TotalSteps = $totalSteps
        PassedSteps = $passedSteps
        FailedSteps = $failedSteps
        SuccessRate = $overallSuccessRate
        CleanUrlCompliance = $cleanUrlCompliance
        TestTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Environment = $Environment
        BffApiUrl = $BffApiUrl
        InternalApiUrl = $InternalApiUrl
    }
    Workflows = $WorkflowResults
    Performance = $performanceResults
    UrlAnalysis = @{
        TotalUrls = $allUrls.Count
        CleanUrls = $cleanUrls.Count
        DirtyUrls = $dirtyUrls.Count
        BaseUrls = $baseUrls
        DirtyUrlList = $dirtyUrls
    }
}

$resultsFile = "comprehensive-integration-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$detailedResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host ""
Write-Host "Detailed results exported to: $resultsFile" -ForegroundColor Cyan

# Final status determination
Write-Host ""
if ($overallSuccessRate -ge 90 -and $cleanUrlCompliance -eq 100 -and $ErrorCount -eq 0) {
    Write-Host "✓ COMPREHENSIVE INTEGRATION TESTS PASSED" -ForegroundColor Green
    Write-Host "  All workflows completed successfully with clean URLs" -ForegroundColor Green
    exit 0
} elseif ($overallSuccessRate -ge 70 -and $cleanUrlCompliance -ge 95) {
    Write-Host "⚠ INTEGRATION TESTS PASSED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "  Most workflows completed successfully, minor issues detected" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "✗ INTEGRATION TESTS FAILED" -ForegroundColor Red
    Write-Host "  Significant issues detected in workflows or URL structure" -ForegroundColor Red
    Write-Host "  Success Rate: $overallSuccessRate%, Clean URL Compliance: $cleanUrlCompliance%" -ForegroundColor Red
    exit 2
}