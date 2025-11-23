# Test Discovery Lambda Resilience
# This script validates that the discovery Lambda handles failures gracefully

Write-Host "=== Testing Discovery Lambda Resilience ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Invoke discovery Lambda
Write-Host "Test 1: Invoking discovery Lambda..." -ForegroundColor Yellow
$result = aws lambda invoke `
    --function-name RDSDiscoveryFunction-prod `
    --payload '{}' `
    --cli-binary-format raw-in-base64-out `
    response.json

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Lambda invocation successful" -ForegroundColor Green
    
    # Parse response
    $response = Get-Content response.json | ConvertFrom-Json
    $body = $response.body | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "=== Discovery Results ===" -ForegroundColor Cyan
    Write-Host "Status Code: $($response.statusCode)"
    Write-Host "Total Instances: $($body.total_instances)"
    Write-Host "Accounts Attempted: $($body.accounts_attempted)"
    Write-Host "Accounts Scanned: $($body.accounts_scanned)"
    Write-Host "Regions Scanned: $($body.regions_scanned)"
    Write-Host "Errors: $($body.errors.Count)"
    Write-Host "Warnings: $($body.warnings.Count)"
    Write-Host "Execution Status: $($body.execution_status)"
    Write-Host ""
    
    # Show errors if any
    if ($body.errors.Count -gt 0) {
        Write-Host "=== Errors Encountered ===" -ForegroundColor Yellow
        foreach ($error in $body.errors) {
            Write-Host ""
            Write-Host "Error Type: $($error.type)" -ForegroundColor Red
            Write-Host "Severity: $($error.severity)"
            if ($error.account_id) {
                Write-Host "Account: $($error.account_id)"
            }
            if ($error.region) {
                Write-Host "Region: $($error.region)"
            }
            Write-Host "Error: $($error.error)"
            Write-Host "Remediation: $($error.remediation)"
        }
        Write-Host ""
    }
    
    # Show warnings if any
    if ($body.warnings.Count -gt 0) {
        Write-Host "=== Warnings ===" -ForegroundColor Yellow
        foreach ($warning in $body.warnings) {
            Write-Host ""
            Write-Host "Warning Type: $($warning.type)"
            Write-Host "Severity: $($warning.severity)"
            Write-Host "Message: $($warning.message)"
            Write-Host "Impact: $($warning.impact)"
        }
        Write-Host ""
    }
    
    # Validate resilience
    Write-Host "=== Resilience Validation ===" -ForegroundColor Cyan
    
    # Check 1: Lambda should always return 200 (unless catastrophic failure)
    if ($response.statusCode -eq 200) {
        Write-Host "✓ Lambda returned success status (200)" -ForegroundColor Green
    } else {
        Write-Host "✗ Lambda returned error status ($($response.statusCode))" -ForegroundColor Red
    }
    
    # Check 2: Should have attempted at least current account
    if ($body.accounts_attempted -ge 1) {
        Write-Host "✓ Attempted discovery in at least one account" -ForegroundColor Green
    } else {
        Write-Host "✗ No accounts attempted" -ForegroundColor Red
    }
    
    # Check 3: If errors exist, check they have proper structure
    if ($body.errors.Count -gt 0) {
        $allErrorsValid = $true
        foreach ($error in $body.errors) {
            if (-not $error.type -or -not $error.severity -or -not $error.error -or -not $error.remediation) {
                $allErrorsValid = $false
                break
            }
        }
        
        if ($allErrorsValid) {
            Write-Host "✓ All errors have proper structure with remediation" -ForegroundColor Green
        } else {
            Write-Host "✗ Some errors missing required fields" -ForegroundColor Red
        }
    }
    
    # Check 4: Execution status should be set
    if ($body.execution_status) {
        Write-Host "✓ Execution status is set: $($body.execution_status)" -ForegroundColor Green
    } else {
        Write-Host "✗ Execution status not set" -ForegroundColor Red
    }
    
    # Check 5: Discovery timestamp should exist
    if ($body.discovery_timestamp) {
        Write-Host "✓ Discovery timestamp recorded: $($body.discovery_timestamp)" -ForegroundColor Green
    } else {
        Write-Host "✗ Discovery timestamp missing" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    
    if ($body.accounts_scanned -gt 0) {
        $successRate = [math]::Round(($body.accounts_scanned / $body.accounts_attempted) * 100, 1)
        Write-Host "Success Rate: $successRate% ($($body.accounts_scanned)/$($body.accounts_attempted) accounts)" -ForegroundColor Green
    }
    
    if ($body.errors.Count -eq 0) {
        Write-Host "✓ Discovery completed without errors" -ForegroundColor Green
    } else {
        Write-Host "⚠ Discovery completed with $($body.errors.Count) error(s), but Lambda succeeded" -ForegroundColor Yellow
        Write-Host "  This is expected behavior - individual account/region failures don't fail the Lambda" -ForegroundColor Gray
    }
    
} else {
    Write-Host "✗ Lambda invocation failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan

# Cleanup
if (Test-Path response.json) {
    Remove-Item response.json
}
