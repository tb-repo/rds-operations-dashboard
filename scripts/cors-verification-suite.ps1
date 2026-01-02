# CORS Verification Suite - Master Script
# Orchestrates all CORS verification and testing tools
# Requirements: 3.1, 3.2, 3.3, 3.4

param(
    [string]$Environment = "production",
    [string]$BffUrl = "",
    [string]$FrontendUrl = "",
    [switch]$SkipDiagnostics = $false,
    [switch]$SkipComprehensiveTest = $false,
    [switch]$SkipDeploymentVerification = $false,
    [switch]$OpenBrowserTest = $false,
    [switch]$Verbose = $false
)

Write-Host "=== CORS Verification Suite ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$overallSuccess = $true
$executedTests = @()

function Execute-VerificationScript {
    param(
        [string]$ScriptName,
        [string]$Description,
        [array]$Arguments = @(),
        [bool]$Required = $true
    )
    
    Write-Host "=== $Description ===" -ForegroundColor Magenta
    
    $scriptPath = Join-Path $scriptDir $ScriptName
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "❌ Script not found: $scriptPath" -ForegroundColor Red
        if ($Required) {
            $global:overallSuccess = $false
        }
        return $false
    }
    
    try {
        $startTime = Get-Date
        
        # Build argument string
        $argString = ""
        if ($Arguments.Count -gt 0) {
            $argString = " " + ($Arguments -join " ")
        }
        
        Write-Host "Executing: $ScriptName$argString" -ForegroundColor Gray
        
        # Execute the script
        $result = & $scriptPath @Arguments
        $exitCode = $LASTEXITCODE
        
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        $testResult = @{
            Script = $ScriptName
            Description = $Description
            Arguments = $Arguments
            ExitCode = $exitCode
            Duration = $duration
            StartTime = $startTime
            EndTime = $endTime
            Success = ($exitCode -eq 0)
        }
        
        $global:executedTests += $testResult
        
        if ($exitCode -eq 0) {
            Write-Host "✅ $Description completed successfully" -ForegroundColor Green
            Write-Host "   Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
        } else {
            Write-Host "❌ $Description failed (Exit code: $exitCode)" -ForegroundColor Red
            Write-Host "   Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
            if ($Required) {
                $global:overallSuccess = $false
            }
        }
        
        Write-Host ""
        return ($exitCode -eq 0)
        
    } catch {
        Write-Host "❌ Error executing $ScriptName`: $($_.Exception.Message)" -ForegroundColor Red
        if ($Required) {
            $global:overallSuccess = $false
        }
        return $false
    }
}

# Prepare common arguments
$commonArgs = @()
if ($BffUrl) { $commonArgs += "-BffUrl", $BffUrl }
if ($FrontendUrl) { $commonArgs += "-FrontendUrl", $FrontendUrl }
if ($Environment -ne "production") { $commonArgs += "-Environment", $Environment }
if ($Verbose) { $commonArgs += "-Verbose" }

Write-Host "🔍 Starting CORS verification suite..." -ForegroundColor Cyan
Write-Host ""

# 1. Run Diagnostics (unless skipped)
if (-not $SkipDiagnostics) {
    $diagArgs = $commonArgs + @("-CheckLambda", "-CheckApiGateway")
    Execute-VerificationScript -ScriptName "diagnose-cors-issues.ps1" -Description "CORS Issues Diagnostic" -Arguments $diagArgs -Required $false
} else {
    Write-Host "⏭️  Skipping CORS diagnostics" -ForegroundColor Yellow
}

# 2. Run Comprehensive Test (unless skipped)
if (-not $SkipComprehensiveTest) {
    $testArgs = $commonArgs
    if ($BffUrl -and $FrontendUrl) {
        $testArgs += "-AllowedOrigin", $FrontendUrl
        $testArgs += "-TestOrigin", "https://malicious-test.com"
    }
    Execute-VerificationScript -ScriptName "test-cors-comprehensive.ps1" -Description "Comprehensive CORS Testing" -Arguments $testArgs -Required $true
} else {
    Write-Host "⏭️  Skipping comprehensive CORS test" -ForegroundColor Yellow
}

# 3. Run Deployment Verification (unless skipped)
if (-not $SkipDeploymentVerification) {
    $deployArgs = $commonArgs + @("-Detailed")
    Execute-VerificationScript -ScriptName "verify-cors-deployment.ps1" -Description "CORS Deployment Verification" -Arguments $deployArgs -Required $true
} else {
    Write-Host "⏭️  Skipping deployment verification" -ForegroundColor Yellow
}

# 4. Open Browser Test (if requested)
if ($OpenBrowserTest) {
    Write-Host "=== Browser Test ===" -ForegroundColor Magenta
    
    $browserTestPath = Join-Path (Split-Path $scriptDir -Parent) "test-cors-browser-comprehensive.html"
    
    if (Test-Path $browserTestPath) {
        Write-Host "🌐 Opening browser test..." -ForegroundColor Cyan
        try {
            Start-Process $browserTestPath
            Write-Host "✅ Browser test opened successfully" -ForegroundColor Green
            Write-Host "   Please run the test from your frontend domain: $FrontendUrl" -ForegroundColor Yellow
        } catch {
            Write-Host "❌ Failed to open browser test: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Browser test file not found: $browserTestPath" -ForegroundColor Red
    }
    Write-Host ""
}

# Generate Summary Report
Write-Host "=== Verification Suite Summary ===" -ForegroundColor Cyan

$totalTests = $executedTests.Count
$successfulTests = ($executedTests | Where-Object { $_.Success }).Count
$failedTests = $totalTests - $successfulTests
$totalDuration = ($executedTests | Measure-Object -Property Duration -Sum).Sum

Write-Host "Total Tests Executed: $totalTests" -ForegroundColor White
Write-Host "Successful: $successfulTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor Red
Write-Host "Total Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
Write-Host ""

if ($executedTests.Count -gt 0) {
    Write-Host "=== Test Details ===" -ForegroundColor Cyan
    $executedTests | ForEach-Object {
        $status = if ($_.Success) { "✅ PASS" } else { "❌ FAIL" }
        $color = if ($_.Success) { "Green" } else { "Red" }
        
        Write-Host "$status $($_.Description)" -ForegroundColor $color
        Write-Host "   Script: $($_.Script)" -ForegroundColor Gray
        Write-Host "   Duration: $([math]::Round($_.Duration, 2))s" -ForegroundColor Gray
        if (-not $_.Success) {
            Write-Host "   Exit Code: $($_.ExitCode)" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

# Final Assessment
Write-Host "=== Final Assessment ===" -ForegroundColor Cyan

if ($overallSuccess -and $successfulTests -eq $totalTests) {
    Write-Host "🎉 All CORS verification tests passed!" -ForegroundColor Green
    Write-Host "✅ CORS configuration is working correctly" -ForegroundColor Green
    Write-Host "🚀 System is ready for production use" -ForegroundColor Green
} elseif ($successfulTests -gt 0) {
    Write-Host "⚠️  Some CORS tests passed, but issues were detected" -ForegroundColor Yellow
    Write-Host "🔧 Review failed tests and address issues before production deployment" -ForegroundColor Yellow
} else {
    Write-Host "❌ Critical CORS issues detected" -ForegroundColor Red
    Write-Host "🚫 Do not deploy to production until all issues are resolved" -ForegroundColor Red
}

Write-Host ""

# Provide next steps
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
if ($overallSuccess) {
    Write-Host "1. ✅ CORS verification complete - no action needed" -ForegroundColor Green
    Write-Host "2. 📊 Review generated reports for detailed information" -ForegroundColor White
    Write-Host "3. 🔄 Run this suite after any CORS configuration changes" -ForegroundColor White
} else {
    Write-Host "1. 🔍 Review failed test details above" -ForegroundColor White
    Write-Host "2. 🛠️  Address CORS configuration issues" -ForegroundColor White
    Write-Host "3. 🔄 Re-run this verification suite" -ForegroundColor White
    Write-Host "4. 📞 Contact support if issues persist" -ForegroundColor White
}

Write-Host ""
Write-Host "=== Available Tools ===" -ForegroundColor Cyan
Write-Host "• diagnose-cors-issues.ps1 - Detailed CORS diagnostics" -ForegroundColor White
Write-Host "• test-cors-comprehensive.ps1 - Comprehensive CORS testing" -ForegroundColor White
Write-Host "• verify-cors-deployment.ps1 - Post-deployment verification" -ForegroundColor White
Write-Host "• test-cors-browser-comprehensive.html - Browser-based testing" -ForegroundColor White
Write-Host "• cors-verification-suite.ps1 - This master script" -ForegroundColor White

# Export summary report
$reportData = @{
    VerificationSuite = "CORS Verification Suite"
    Environment = $Environment
    Timestamp = Get-Date
    BffUrl = $BffUrl
    FrontendUrl = $FrontendUrl
    OverallSuccess = $overallSuccess
    TotalTests = $totalTests
    SuccessfulTests = $successfulTests
    FailedTests = $failedTests
    TotalDuration = $totalDuration
    ExecutedTests = $executedTests
}

$reportPath = "cors-verification-suite-report-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$reportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "📊 Verification suite report saved to: $reportPath" -ForegroundColor Cyan

# Exit with appropriate code
if ($overallSuccess) {
    exit 0
} else {
    exit 1
}