#!/usr/bin/env pwsh

<#
.SYNOPSIS
Trace Actual Request Flow

.DESCRIPTION
Trace the actual request flow from CloudFront to find where the 500 error is coming from
#>

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Tracing Actual Request Flow ===" -ForegroundColor Cyan

# Step 1: Check what API URL the frontend is actually using
Write-Host "`n--- Step 1: Frontend Configuration ---" -ForegroundColor Yellow

if (Test-Path "frontend/.env") {
    Write-Info "Frontend .env file:"
    Get-Content "frontend/.env" | ForEach-Object { Write-Info "  $_" }
} else {
    Write-Warning "No frontend .env file found"
}

# Check the built frontend for API URLs
if (Test-Path "frontend/dist") {
    Write-Info "Checking built frontend for API URLs..."
    $jsFiles = Get-ChildItem "frontend/dist" -Recurse -Filter "*.js" | Select-Object -First 3
    foreach ($file in $jsFiles) {
        $content = Get-Content $file.FullName -Raw
        if ($content -match "https://[^/]+\.execute-api\.[^/]+\.amazonaws\.com") {
            Write-Info "Found API URL in $($file.Name): $($matches[0])"
        }
    }
}

# Step 2: Check CloudFront distribution configuration
Write-Host "`n--- Step 2: CloudFront Configuration ---" -ForegroundColor Yellow

$distributions = aws cloudfront list-distributions --output json 2>$null | ConvertFrom-Json

if ($distributions) {
    $targetDist = $distributions.DistributionList.Items | Where-Object { 
        $_.DomainName -eq "d2qvaswtmn22om.cloudfront.net" 
    }
    
    if ($targetDist) {
        Write-Success "Found CloudFront distribution: $($targetDist.Id)"
        
        # Check origins
        Write-Info "Origins:"
        foreach ($origin in $targetDist.Origins.Items) {
            Write-Info "  $($origin.Id): $($origin.DomainName)"
        }
        
        # Check cache behaviors
        Write-Info "Cache Behaviors:"
        if ($targetDist.DefaultCacheBehavior) {
            Write-Info "  Default (/*): -> $($targetDist.DefaultCacheBehavior.TargetOriginId)"
        }
        
        if ($targetDist.CacheBehaviors.Items) {
            foreach ($behavior in $targetDist.CacheBehaviors.Items) {
                Write-Info "  $($behavior.PathPattern): -> $($behavior.TargetOriginId)"
            }
        }
    }
}

# Step 3: Test the actual API Gateway that the frontend calls
Write-Host "`n--- Step 3: Testing Frontend API Calls ---" -ForegroundColor Yellow

# The frontend is likely calling the main API Gateway, not the BFF
$mainApiId = "km9ww1hh3k"  # From the error message
$apiUrl = "https://$mainApiId.execute-api.ap-southeast-1.amazonaws.com/prod"

Write-Info "Testing main API Gateway: $apiUrl"

# Test the error endpoints that are failing
$endpoints = @(
    "/api/errors/dashboard",
    "/api/errors/statistics"
)

foreach ($endpoint in $endpoints) {
    Write-Info "Testing: $apiUrl$endpoint"
    
    try {
        $response = Invoke-RestMethod -Uri "$apiUrl$endpoint" -Method GET -Headers @{
            "Content-Type" = "application/json"
        } -ErrorAction Stop
        
        Write-Success "✅ $endpoint returned data"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Error "❌ $endpoint failed with status: $statusCode"
        Write-Error "Error: $($_.Exception.Message)"
        
        if ($_.Exception.Response) {
            try {
                $errorBody = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorBody)
                $errorContent = $reader.ReadToEnd()
                Write-Error "Response body: $errorContent"
            } catch {
                Write-Warning "Could not read error response body"
            }
        }
    }
}

# Step 4: Check API Gateway resources and methods
Write-Host "`n--- Step 4: API Gateway Resources ---" -ForegroundColor Yellow

$resources = aws apigateway get-resources --rest-api-id $mainApiId --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($resources) {
    Write-Info "API Gateway Resources for ${mainApiId}:"
    foreach ($resource in $resources.items) {
        Write-Info "  $($resource.path)"
        
        if ($resource.resourceMethods) {
            $resource.resourceMethods.PSObject.Properties | ForEach-Object {
                Write-Info "    $($_.Name)"
            }
        }
    }
    
    # Check if error endpoints exist
    $errorResources = $resources.items | Where-Object { $_.path -match "error" }
    if ($errorResources.Count -eq 0) {
        Write-Error "❌ No error-related resources found in API Gateway!"
        Write-Warning "This is likely the root cause - the API Gateway doesn't have the error endpoints"
    }
}

# Step 5: Check what Lambda functions are integrated
Write-Host "`n--- Step 5: Lambda Integrations ---" -ForegroundColor Yellow

# Check if there are Lambda functions for error handling
$lambdaFunctions = aws lambda list-functions --region ap-southeast-1 --output json | ConvertFrom-Json

$errorLambdas = $lambdaFunctions.Functions | Where-Object { $_.FunctionName -match "error|monitoring" }

if ($errorLambdas.Count -gt 0) {
    Write-Info "Found error/monitoring Lambda functions:"
    foreach ($lambda in $errorLambdas) {
        Write-Info "  $($lambda.FunctionName) - $($lambda.Runtime)"
    }
} else {
    Write-Warning "No error/monitoring Lambda functions found"
}

# Step 6: Check recent API Gateway logs
Write-Host "`n--- Step 6: API Gateway Logs ---" -ForegroundColor Yellow

# Check if API Gateway logging is enabled
$stage = aws apigateway get-stage --rest-api-id $mainApiId --stage-name prod --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($stage) {
    if ($stage.accessLogSettings) {
        Write-Info "API Gateway logging is enabled"
        Write-Info "Log destination: $($stage.accessLogSettings.destinationArn)"
    } else {
        Write-Warning "API Gateway logging is not enabled"
    }
} else {
    Write-Warning "Could not get API Gateway stage information"
}

Write-Host "`n=== Analysis Complete ===" -ForegroundColor Cyan
Write-Host "Key Findings:" -ForegroundColor Yellow
Write-Host "1. Check if the main API Gateway (${mainApiId}) has error endpoints" -ForegroundColor White
Write-Host "2. Verify Lambda integrations for error handling" -ForegroundColor White
Write-Host "3. The BFF might not be the issue - the main API might be missing endpoints" -ForegroundColor White