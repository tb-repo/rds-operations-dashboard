#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Verify CORS deployment in staging and production environments
    
.DESCRIPTION
    This script verifies that CORS configuration has been deployed correctly by:
    - Checking Lambda function environment variables
    - Testing CORS headers in responses
    - Validating origin validation behavior
    - Checking preflight request handling
    
.PARAMETER Environment
    Target environment to verify (staging, production, both)
    
.PARAMETER TestOrigin
    Origin to use for testing (defaults to environment-specific origin)
    
.EXAMPLE
    .\verify-cors-deployment.ps1 -Environment staging
    
.EXAMPLE
    .\verify-cors-deployment.ps1 -Environment production -TestOrigin "https://d2qvaswtmn22om.cloudfront.net"
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("staging", "production", "both")]
    [string]$Environment = "both",
    
    [Parameter(Mandatory = $false)]
    [string]$TestOrigin
)

# Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Lambda function names and test origins by environment
$Config = @{
    staging = @{
        FunctionName = "rds-dashboard-bff-staging"
        DefaultOrigin = "https://staging-d2qvaswtmn22om.cloudfront.net"
        ApiUrl = "https://staging-api.example.com"
    }
    production = @{
        FunctionName = "rds-dashboard-bff-prod"
        DefaultOrigin = "https://d2qvaswtmn22om.cloudfront.net"
        ApiUrl = "https://api.example.com"
    }
}

# Colors for output
$Colors = @{
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "=" * 60 -Color Header
    Write-ColorOutput "  $Title" -Color Header
    Write-ColorOutput "=" * 60 -Color Header
    Write-Host ""
}

function Test-LambdaEnvironmentVariables {
    param(
        [string]$FunctionName,
        [string]$Environment
    )
    
    Write-ColorOutput "Checking environment variables for $FunctionName..." -Color Info
    
    try {
        $config = aws lambda get-function-configuration --function-name $FunctionName --output json | ConvertFrom-Json
        $envVars = $config.Environment.Variables
        
        Write-ColorOutput "✓ Lambda function configuration retrieved" -Color Success
        
        # Check CORS_ORIGINS
        if ($envVars.CORS_ORIGINS) {
            Write-ColorOutput "✓ CORS_ORIGINS is set: $($envVars.CORS_ORIGINS)" -Color Success
            $origins = $envVars.CORS_ORIGINS -split ','
            Write-ColorOutput "  Configured origins:" -Color Info
            foreach ($origin in $origins) {
                Write-ColorOutput "    - $($origin.Trim())" -Color Info
            }
        }
        else {
            Write-ColorOutput "⚠ CORS_ORIGINS not set - using environment defaults" -Color Warning
        }
        
        # Check NODE_ENV
        if ($envVars.NODE_ENV) {
            Write-ColorOutput "✓ NODE_ENV is set: $($envVars.NODE_ENV)" -Color Success
            if ($envVars.NODE_ENV -eq $Environment) {
                Write-ColorOutput "✓ NODE_ENV matches target environment" -Color Success
            }
            else {
                Write-ColorOutput "⚠ NODE_ENV ($($envVars.NODE_ENV)) doesn't match target environment ($Environment)" -Color Warning
            }
        }
        else {
            Write-ColorOutput "⚠ NODE_ENV not set" -Color Warning
        }
        
        # Check other relevant variables
        $relevantVars = @("FRONTEND_URL", "LOG_LEVEL", "COGNITO_USER_POOL_ID")
        foreach ($var in $relevantVars) {
            if ($envVars.$var) {
                Write-ColorOutput "✓ $var is set: $($envVars.$var)" -Color Success
            }
            else {
                Write-ColorOutput "⚠ $var not set" -Color Warning
            }
        }
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ Failed to get Lambda configuration: $($_.Exception.Message)" -Color Error
        return $false
    }
}

function Test-CorsHeaders {
    param(
        [string]$FunctionName,
        [string]$TestOrigin
    )
    
    Write-ColorOutput "Testing CORS headers with origin: $TestOrigin" -Color Info
    
    # Test GET request
    $testEvent = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{
            Origin = $TestOrigin
            "Content-Type" = "application/json"
        }
        body = $null
        isBase64Encoded = $false
    } | ConvertTo-Json -Depth 3
    
    try {
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $testEvent `
            --output json `
            response.json | ConvertFrom-Json
            
        if ($result.StatusCode -eq 200) {
            $response = Get-Content response.json | ConvertFrom-Json
            Write-ColorOutput "✓ Lambda invocation successful" -Color Success
            
            # Check response status
            if ($response.statusCode -eq 200) {
                Write-ColorOutput "✓ HTTP response status: $($response.statusCode)" -Color Success
            }
            else {
                Write-ColorOutput "⚠ HTTP response status: $($response.statusCode)" -Color Warning
            }
            
            # Check CORS headers
            $headers = $response.headers
            if ($headers) {
                if ($headers."Access-Control-Allow-Origin") {
                    Write-ColorOutput "✓ Access-Control-Allow-Origin: $($headers.'Access-Control-Allow-Origin')" -Color Success
                    
                    if ($headers."Access-Control-Allow-Origin" -eq $TestOrigin) {
                        Write-ColorOutput "✓ Origin matches request origin" -Color Success
                    }
                    else {
                        Write-ColorOutput "⚠ Origin doesn't match request origin" -Color Warning
                    }
                }
                else {
                    Write-ColorOutput "✗ Access-Control-Allow-Origin header missing" -Color Error
                }
                
                if ($headers."Access-Control-Allow-Credentials") {
                    Write-ColorOutput "✓ Access-Control-Allow-Credentials: $($headers.'Access-Control-Allow-Credentials')" -Color Success
                }
                else {
                    Write-ColorOutput "⚠ Access-Control-Allow-Credentials header missing" -Color Warning
                }
                
                if ($headers."Access-Control-Expose-Headers") {
                    Write-ColorOutput "✓ Access-Control-Expose-Headers: $($headers.'Access-Control-Expose-Headers')" -Color Success
                }
                else {
                    Write-ColorOutput "⚠ Access-Control-Expose-Headers header missing" -Color Warning
                }
            }
            else {
                Write-ColorOutput "✗ No headers in response" -Color Error
            }
            
            return $true
        }
        else {
            Write-ColorOutput "✗ Lambda invocation failed with status: $($result.StatusCode)" -Color Error
            if ($result.FunctionError) {
                Write-ColorOutput "  Error: $($result.FunctionError)" -Color Error
            }
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ CORS header test failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
    }
}

function Test-PreflightRequest {
    param(
        [string]$FunctionName,
        [string]$TestOrigin
    )
    
    Write-ColorOutput "Testing preflight OPTIONS request..." -Color Info
    
    $testEvent = @{
        httpMethod = "OPTIONS"
        path = "/api/test"
        headers = @{
            Origin = $TestOrigin
            "Access-Control-Request-Method" = "POST"
            "Access-Control-Request-Headers" = "Content-Type,Authorization"
        }
        body = $null
        isBase64Encoded = $false
    } | ConvertTo-Json -Depth 3
    
    try {
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $testEvent `
            --output json `
            response.json | ConvertFrom-Json
            
        if ($result.StatusCode -eq 200) {
            $response = Get-Content response.json | ConvertFrom-Json
            Write-ColorOutput "✓ OPTIONS request successful" -Color Success
            
            # Check preflight headers
            $headers = $response.headers
            if ($headers) {
                if ($headers."Access-Control-Allow-Methods") {
                    Write-ColorOutput "✓ Access-Control-Allow-Methods: $($headers.'Access-Control-Allow-Methods')" -Color Success
                    
                    if ($headers."Access-Control-Allow-Methods" -match "POST") {
                        Write-ColorOutput "✓ POST method allowed" -Color Success
                    }
                    else {
                        Write-ColorOutput "⚠ POST method not in allowed methods" -Color Warning
                    }
                }
                else {
                    Write-ColorOutput "✗ Access-Control-Allow-Methods header missing" -Color Error
                }
                
                if ($headers."Access-Control-Allow-Headers") {
                    Write-ColorOutput "✓ Access-Control-Allow-Headers: $($headers.'Access-Control-Allow-Headers')" -Color Success
                    
                    $allowedHeaders = $headers."Access-Control-Allow-Headers"
                    if ($allowedHeaders -match "Content-Type" -and $allowedHeaders -match "Authorization") {
                        Write-ColorOutput "✓ Required headers allowed" -Color Success
                    }
                    else {
                        Write-ColorOutput "⚠ Some required headers may not be allowed" -Color Warning
                    }
                }
                else {
                    Write-ColorOutput "✗ Access-Control-Allow-Headers header missing" -Color Error
                }
                
                if ($headers."Access-Control-Max-Age") {
                    Write-ColorOutput "✓ Access-Control-Max-Age: $($headers.'Access-Control-Max-Age')" -Color Success
                }
                else {
                    Write-ColorOutput "⚠ Access-Control-Max-Age header missing" -Color Warning
                }
            }
            
            return $true
        }
        else {
            Write-ColorOutput "✗ OPTIONS request failed with status: $($result.StatusCode)" -Color Error
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ Preflight test failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
    }
}

function Test-InvalidOrigin {
    param(
        [string]$FunctionName
    )
    
    Write-ColorOutput "Testing invalid origin rejection..." -Color Info
    
    $testEvent = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{
            Origin = "https://malicious.com"
            "Content-Type" = "application/json"
        }
        body = $null
        isBase64Encoded = $false
    } | ConvertTo-Json -Depth 3
    
    try {
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $testEvent `
            --output json `
            response.json | ConvertFrom-Json
            
        if ($result.StatusCode -eq 200) {
            $response = Get-Content response.json | ConvertFrom-Json
            
            # For invalid origins, we expect either:
            # 1. No CORS headers (origin rejected)
            # 2. Error response
            # 3. Status code indicating rejection
            
            if ($response.statusCode -ge 400) {
                Write-ColorOutput "✓ Invalid origin correctly rejected (status: $($response.statusCode))" -Color Success
                return $true
            }
            elseif (-not $response.headers -or -not $response.headers."Access-Control-Allow-Origin") {
                Write-ColorOutput "✓ Invalid origin correctly rejected (no CORS headers)" -Color Success
                return $true
            }
            elseif ($response.headers."Access-Control-Allow-Origin" -eq "https://malicious.com") {
                Write-ColorOutput "✗ Invalid origin was incorrectly allowed!" -Color Error
                return $false
            }
            else {
                Write-ColorOutput "✓ Invalid origin handled appropriately" -Color Success
                return $true
            }
        }
        else {
            Write-ColorOutput "✗ Lambda invocation failed: $($result.StatusCode)" -Color Error
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ Invalid origin test failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
    }
}

function Test-Environment {
    param(
        [string]$Environment
    )
    
    Write-Header "Verifying CORS Deployment - $($Environment.ToUpper())"
    
    $config = $Config[$Environment]
    $functionName = $config.FunctionName
    $testOrigin = if ($TestOrigin) { $TestOrigin } else { $config.DefaultOrigin }
    
    Write-ColorOutput "Environment: $Environment" -Color Info
    Write-ColorOutput "Function: $functionName" -Color Info
    Write-ColorOutput "Test Origin: $testOrigin" -Color Info
    Write-Host ""
    
    $allTestsPassed = $true
    
    # Test 1: Environment Variables
    Write-ColorOutput "Test 1: Environment Variables" -Color Header
    $result = Test-LambdaEnvironmentVariables -FunctionName $functionName -Environment $Environment
    if (-not $result) { $allTestsPassed = $false }
    Write-Host ""
    
    # Test 2: CORS Headers
    Write-ColorOutput "Test 2: CORS Headers" -Color Header
    $result = Test-CorsHeaders -FunctionName $functionName -TestOrigin $testOrigin
    if (-not $result) { $allTestsPassed = $false }
    Write-Host ""
    
    # Test 3: Preflight Requests
    Write-ColorOutput "Test 3: Preflight Requests" -Color Header
    $result = Test-PreflightRequest -FunctionName $functionName -TestOrigin $testOrigin
    if (-not $result) { $allTestsPassed = $false }
    Write-Host ""
    
    # Test 4: Invalid Origin Rejection
    Write-ColorOutput "Test 4: Invalid Origin Rejection" -Color Header
    $result = Test-InvalidOrigin -FunctionName $functionName
    if (-not $result) { $allTestsPassed = $false }
    Write-Host ""
    
    # Summary
    if ($allTestsPassed) {
        Write-ColorOutput "✓ All tests passed for $Environment environment!" -Color Success
    }
    else {
        Write-ColorOutput "✗ Some tests failed for $Environment environment" -Color Error
    }
    
    return $allTestsPassed
}

# Main verification logic
function Start-Verification {
    Write-Header "CORS Deployment Verification"
    
    # Check AWS credentials
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-ColorOutput "✓ AWS credentials valid - Account: $($identity.Account)" -Color Success
    }
    catch {
        Write-ColorOutput "✗ AWS credentials not configured or invalid" -Color Error
        Write-ColorOutput "Please run 'aws configure' or set AWS environment variables" -Color Error
        exit 1
    }
    
    $overallSuccess = $true
    
    if ($Environment -eq "both") {
        $stagingResult = Test-Environment -Environment "staging"
        $productionResult = Test-Environment -Environment "production"
        $overallSuccess = $stagingResult -and $productionResult
    }
    else {
        $overallSuccess = Test-Environment -Environment $Environment
    }
    
    Write-Header "Verification Summary"
    
    if ($overallSuccess) {
        Write-ColorOutput "🎉 All CORS deployment verifications passed!" -Color Success
        Write-ColorOutput "The CORS configuration is working correctly." -Color Success
    }
    else {
        Write-ColorOutput "❌ Some verifications failed." -Color Error
        Write-ColorOutput "Please check the Lambda function configuration and logs." -Color Error
        Write-ColorOutput "Consider rolling back if issues persist." -Color Error
    }
    
    Write-Host ""
    Write-ColorOutput "Next steps:" -Color Header
    Write-ColorOutput "1. Test CORS functionality from actual frontend applications" -Color Info
    Write-ColorOutput "2. Monitor Lambda function logs for any CORS-related errors" -Color Info
    Write-ColorOutput "3. Verify all critical user journeys work correctly" -Color Info
    
    if (-not $overallSuccess) {
        exit 1
    }
}

# Run verification
try {
    Start-Verification
}
catch {
    Write-ColorOutput "Verification failed with error: $($_.Exception.Message)" -Color Error
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" -Color Error
    exit 1
}