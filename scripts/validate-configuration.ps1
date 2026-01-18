#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Validates configuration for API Gateway Stage Elimination
.DESCRIPTION
    Validates all required environment variables and service endpoint accessibility
    for the clean URL API Gateway configuration.
.PARAMETER Environment
    Environment to validate (staging, production)
.EXAMPLE
    ./validate-configuration.ps1 -Environment production
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("staging", "production")]
    [string]$Environment
)

# Configuration validation results
$ValidationResults = @{
    EnvironmentVariables = @{}
    ServiceEndpoints = @{}
    OverallStatus = $true
}

Write-Host "🔍 Validating Configuration for API Gateway Stage Elimination" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

# Define required environment variables by service
$RequiredEnvVars = @{
    BFF = @(
        "NODE_ENV",
        "CORS_ORIGINS",
        "JWT_SECRET_NAME",
        "COGNITO_USER_POOL_ID",
        "COGNITO_CLIENT_ID"
    )
    Discovery = @(
        "AWS_ACCOUNT_ID",
        "INVENTORY_TABLE",
        "AUDIT_LOG_TABLE",
        "EXTERNAL_ID",
        "CROSS_ACCOUNT_ROLE_NAME",
        "TARGET_ACCOUNTS",
        "TARGET_REGIONS"
    )
    Operations = @(
        "AWS_ACCOUNT_ID",
        "INVENTORY_TABLE",
        "AUDIT_LOG_TABLE",
        "EXTERNAL_ID",
        "CROSS_ACCOUNT_ROLE_NAME",
        "SNS_TOPIC_ARN"
    )
}

# Define service endpoints to validate
$ServiceEndpoints = @{
    BFF = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com"
    Internal = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
    CloudFront = "https://d2qvaswtmn22om.cloudfront.net"
}

function Test-LambdaEnvironmentVariables {
    param(
        [string]$FunctionName,
        [string[]]$RequiredVars,
        [string]$ServiceName
    )
    
    Write-Host "📋 Validating $ServiceName Lambda Environment Variables..." -ForegroundColor Blue
    
    try {
        $config = aws lambda get-function-configuration --function-name $FunctionName --query 'Environment.Variables' --output json | ConvertFrom-Json
        
        $missing = @()
        $present = @()
        
        foreach ($var in $RequiredVars) {
            if ($config.PSObject.Properties.Name -contains $var) {
                $present += $var
                Write-Host "  ✅ $var" -ForegroundColor Green
            } else {
                $missing += $var
                Write-Host "  ❌ $var (MISSING)" -ForegroundColor Red
            }
        }
        
        $ValidationResults.EnvironmentVariables[$ServiceName] = @{
            Present = $present
            Missing = $missing
            Status = ($missing.Count -eq 0)
        }
        
        if ($missing.Count -gt 0) {
            $ValidationResults.OverallStatus = $false
            Write-Host "  ⚠️  Missing $($missing.Count) required environment variables" -ForegroundColor Yellow
        } else {
            Write-Host "  ✅ All required environment variables present" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "  ❌ Failed to get Lambda configuration: $($_.Exception.Message)" -ForegroundColor Red
        $ValidationResults.EnvironmentVariables[$ServiceName] = @{
            Present = @()
            Missing = $RequiredVars
            Status = $false
            Error = $_.Exception.Message
        }
        $ValidationResults.OverallStatus = $false
    }
    
    Write-Host ""
}

function Test-ServiceEndpoint {
    param(
        [string]$Url,
        [string]$ServiceName,
        [string]$ExpectedPath = "/health"
    )
    
    Write-Host "🌐 Testing $ServiceName Endpoint..." -ForegroundColor Blue
    Write-Host "  URL: $Url$ExpectedPath" -ForegroundColor Gray
    
    try {
        $response = Invoke-RestMethod -Uri "$Url$ExpectedPath" -Method GET -TimeoutSec 10
        
        $ValidationResults.ServiceEndpoints[$ServiceName] = @{
            Url = $Url
            Status = $true
            ResponseTime = (Measure-Command { Invoke-RestMethod -Uri "$Url$ExpectedPath" -Method GET -TimeoutSec 10 }).TotalMilliseconds
        }
        
        Write-Host "  ✅ Endpoint accessible" -ForegroundColor Green
        Write-Host "  📊 Response time: $($ValidationResults.ServiceEndpoints[$ServiceName].ResponseTime)ms" -ForegroundColor Gray
        
    } catch {
        $ValidationResults.ServiceEndpoints[$ServiceName] = @{
            Url = $Url
            Status = $false
            Error = $_.Exception.Message
        }
        $ValidationResults.OverallStatus = $false
        
        Write-Host "  ❌ Endpoint not accessible: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

function Test-CleanUrlStructure {
    Write-Host "🔗 Testing Clean URL Structure..." -ForegroundColor Blue
    
    $testEndpoints = @(
        @{ Url = "$($ServiceEndpoints.BFF)/api/instances"; Name = "BFF Instances" },
        @{ Url = "$($ServiceEndpoints.BFF)/api/health"; Name = "BFF Health" },
        @{ Url = "$($ServiceEndpoints.Internal)/instances"; Name = "Internal Instances" },
        @{ Url = "$($ServiceEndpoints.Internal)/discovery"; Name = "Internal Discovery" }
    )
    
    $cleanUrlResults = @()
    
    foreach ($endpoint in $testEndpoints) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint.Url -Method GET -TimeoutSec 10
            Write-Host "  ✅ $($endpoint.Name): $($endpoint.Url)" -ForegroundColor Green
            $cleanUrlResults += @{ Name = $endpoint.Name; Status = $true; Url = $endpoint.Url }
        } catch {
            Write-Host "  ❌ $($endpoint.Name): $($endpoint.Url) - $($_.Exception.Message)" -ForegroundColor Red
            $cleanUrlResults += @{ Name = $endpoint.Name; Status = $false; Url = $endpoint.Url; Error = $_.Exception.Message }
            $ValidationResults.OverallStatus = $false
        }
    }
    
    $ValidationResults.CleanUrls = $cleanUrlResults
    Write-Host ""
}

# Main validation execution
Write-Host "🚀 Starting Configuration Validation..." -ForegroundColor Green
Write-Host ""

# Validate Lambda environment variables
if ($Environment -eq "production") {
    Test-LambdaEnvironmentVariables -FunctionName "rds-dashboard-bff-prod" -RequiredVars $RequiredEnvVars.BFF -ServiceName "BFF"
    Test-LambdaEnvironmentVariables -FunctionName "rds-discovery-prod" -RequiredVars $RequiredEnvVars.Discovery -ServiceName "Discovery"
    Test-LambdaEnvironmentVariables -FunctionName "rds-operations-prod" -RequiredVars $RequiredEnvVars.Operations -ServiceName "Operations"
} else {
    Test-LambdaEnvironmentVariables -FunctionName "rds-dashboard-bff-staging" -RequiredVars $RequiredEnvVars.BFF -ServiceName "BFF"
    Test-LambdaEnvironmentVariables -FunctionName "rds-discovery-staging" -RequiredVars $RequiredEnvVars.Discovery -ServiceName "Discovery"
    Test-LambdaEnvironmentVariables -FunctionName "rds-operations-staging" -RequiredVars $RequiredEnvVars.Operations -ServiceName "Operations"
}

# Test service endpoints
Test-ServiceEndpoint -Url $ServiceEndpoints.BFF -ServiceName "BFF"
Test-ServiceEndpoint -Url $ServiceEndpoints.Internal -ServiceName "Internal"
Test-ServiceEndpoint -Url $ServiceEndpoints.CloudFront -ServiceName "CloudFront" -ExpectedPath "/"

# Test clean URL structure
Test-CleanUrlStructure

# Generate validation report
Write-Host "📊 VALIDATION REPORT" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Environment Variables:" -ForegroundColor Yellow
foreach ($service in $ValidationResults.EnvironmentVariables.Keys) {
    $result = $ValidationResults.EnvironmentVariables[$service]
    $status = if ($result.Status) { "✅ PASS" } else { "❌ FAIL" }
    Write-Host "  $service`: $status" -ForegroundColor $(if ($result.Status) { "Green" } else { "Red" })
    
    if ($result.Missing.Count -gt 0) {
        Write-Host "    Missing: $($result.Missing -join ', ')" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Service Endpoints:" -ForegroundColor Yellow
foreach ($service in $ValidationResults.ServiceEndpoints.Keys) {
    $result = $ValidationResults.ServiceEndpoints[$service]
    $status = if ($result.Status) { "✅ PASS" } else { "❌ FAIL" }
    Write-Host "  $service`: $status" -ForegroundColor $(if ($result.Status) { "Green" } else { "Red" })
    
    if ($result.ResponseTime) {
        Write-Host "    Response Time: $($result.ResponseTime)ms" -ForegroundColor Gray
    }
    if ($result.Error) {
        Write-Host "    Error: $($result.Error)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Clean URL Structure:" -ForegroundColor Yellow
if ($ValidationResults.CleanUrls) {
    foreach ($result in $ValidationResults.CleanUrls) {
        $status = if ($result.Status) { "✅ PASS" } else { "❌ FAIL" }
        Write-Host "  $($result.Name): $status" -ForegroundColor $(if ($result.Status) { "Green" } else { "Red" })
    }
}

Write-Host ""
Write-Host "OVERALL STATUS:" -ForegroundColor Yellow
if ($ValidationResults.OverallStatus) {
    Write-Host "✅ CONFIGURATION VALID - Ready for deployment" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ CONFIGURATION INVALID - Issues must be resolved" -ForegroundColor Red
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Fix missing environment variables" -ForegroundColor White
    Write-Host "2. Ensure all service endpoints are accessible" -ForegroundColor White
    Write-Host "3. Verify clean URL structure is working" -ForegroundColor White
    Write-Host "4. Re-run validation after fixes" -ForegroundColor White
    exit 1
}