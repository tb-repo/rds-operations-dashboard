#!/usr/bin/env pwsh

<#
.SYNOPSIS
Diagnose the ACTUAL production issue on CloudFront portal

.DESCRIPTION
The user reports that https://d2qvaswtmn22om.cloudfront.net/dashboard still shows:
"Error: Failed to load error monitoring data. Server error. Please try again later."

This script will diagnose what's really happening in production.
#>

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Diagnosing ACTUAL Production Issue ===" -ForegroundColor Cyan
Write-Info "CloudFront URL: https://d2qvaswtmn22om.cloudfront.net/dashboard"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Step 1: Check what the frontend is actually calling
Write-Host "`n--- Step 1: Analyzing Frontend API Calls ---" -ForegroundColor Yellow

# Check the frontend Dashboard component to see what API it's calling
Write-Info "Checking frontend Dashboard component..."
if (Test-Path "rds-operations-dashboard/frontend/src/pages/Dashboard.tsx") {
    $dashboardContent = Get-Content "rds-operations-dashboard/frontend/src/pages/Dashboard.tsx" -Raw
    
    # Look for API calls related to error monitoring
    if ($dashboardContent -match "/api/errors/") {
        Write-Warning "Frontend is calling /api/errors/ endpoints"
    }
    
    # Check for specific error monitoring calls
    $apiCalls = $dashboardContent | Select-String -Pattern "api\.get\(" -AllMatches
    foreach ($match in $apiCalls.Matches) {
        Write-Info "API Call found: $($match.Value)"
    }
    
    # Look for fetch calls
    $fetchCalls = $dashboardContent | Select-String -Pattern "fetch\(" -AllMatches
    foreach ($match in $fetchCalls.Matches) {
        Write-Info "Fetch call found: $($match.Value)"
    }
} else {
    Write-Warning "Dashboard.tsx not found"
}

# Step 2: Check the actual BFF deployment status
Write-Host "`n--- Step 2: Checking BFF Deployment Status ---" -ForegroundColor Yellow

# Check if BFF Lambda exists and is deployed
$bffLambda = aws lambda get-function --function-name "rds-dashboard-bff-prod" --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($bffLambda) {
    Write-Success "BFF Lambda exists: $($bffLambda.Configuration.FunctionName)"
    Write-Info "Last Modified: $($bffLambda.Configuration.LastModified)"
    Write-Info "Runtime: $($bffLambda.Configuration.Runtime)"
    Write-Info "Code Size: $($bffLambda.Configuration.CodeSize) bytes"
    
    # Check environment variables
    if ($bffLambda.Configuration.Environment.Variables) {
        Write-Info "Environment Variables:"
        $bffLambda.Configuration.Environment.Variables.PSObject.Properties | ForEach-Object {
            if ($_.Name -notmatch "SECRET|KEY|PASSWORD") {
                Write-Info "  $($_.Name) = $($_.Value)"
            } else {
                Write-Info "  $($_.Name) = [REDACTED]"
            }
        }
    }
} else {
    Write-Error "BFF Lambda not found!"
}

# Step 3: Test the actual BFF endpoints that the frontend calls
Write-Host "`n--- Step 3: Testing BFF Endpoints ---" -ForegroundColor Yellow

if ($bffLambda) {
    # Test the error dashboard endpoint
    Write-Info "Testing /api/errors/dashboard endpoint..."
    $testPayload = @{
        httpMethod = "GET"
        path = "/api/errors/dashboard"
        headers = @{
            "Content-Type" = "application/json"
        }
        queryStringParameters = $null
    } | ConvertTo-Json -Compress
    
    $testResult = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload --region ap-southeast-1 bff_dashboard_test.json 2>&1
    
    if (Test-Path "bff_dashboard_test.json") {
        $response = Get-Content "bff_dashboard_test.json" | ConvertFrom-Json
        Write-Info "Dashboard endpoint response:"
        Write-Info "Status Code: $($response.statusCode)"
        
        if ($response.body) {
            $body = $response.body | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($body) {
                Write-Info "Response Body: $($body | ConvertTo-Json -Compress)"
            } else {
                Write-Info "Raw Body: $($response.body)"
            }
        }
        
        Remove-Item "bff_dashboard_test.json" -Force
    }
    
    # Test the error statistics endpoint
    Write-Info "Testing /api/errors/statistics endpoint..."
    $testPayload2 = @{
        httpMethod = "GET"
        path = "/api/errors/statistics"
        headers = @{
            "Content-Type" = "application/json"
        }
        queryStringParameters = $null
    } | ConvertTo-Json -Compress
    
    $testResult2 = aws lambda invoke --function-name "rds-dashboard-bff-prod" --payload $testPayload2 --region ap-southeast-1 bff_statistics_test.json 2>&1
    
    if (Test-Path "bff_statistics_test.json") {
        $response2 = Get-Content "bff_statistics_test.json" | ConvertFrom-Json
        Write-Info "Statistics endpoint response:"
        Write-Info "Status Code: $($response2.statusCode)"
        
        if ($response2.body) {
            $body2 = $response2.body | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($body2) {
                Write-Info "Response Body: $($body2 | ConvertTo-Json -Compress)"
            } else {
                Write-Info "Raw Body: $($response2.body)"
            }
        }
        
        Remove-Item "bff_statistics_test.json" -Force
    }
}

# Step 4: Check API Gateway configuration
Write-Host "`n--- Step 4: Checking API Gateway Configuration ---" -ForegroundColor Yellow

# Find the API Gateway that CloudFront is using
$apis = aws apigateway get-rest-apis --region ap-southeast-1 --output json | ConvertFrom-Json
$dashboardApi = $apis.items | Where-Object { $_.name -like "*dashboard*" -or $_.name -like "*rds*" }

if ($dashboardApi) {
    Write-Success "Found API Gateway: $($dashboardApi.name) (ID: $($dashboardApi.id))"
    
    # Check resources
    $resources = aws apigateway get-resources --rest-api-id $dashboardApi.id --region ap-southeast-1 --output json | ConvertFrom-Json
    
    Write-Info "API Gateway Resources:"
    foreach ($resource in $resources.items) {
        Write-Info "  $($resource.path)"
        
        # Check if this resource has the error endpoints
        if ($resource.path -match "/api/errors") {
            Write-Success "  Found error endpoint: $($resource.path)"
            
            # Check methods
            if ($resource.resourceMethods) {
                $resource.resourceMethods.PSObject.Properties | ForEach-Object {
                    Write-Info "    Method: $($_.Name)"
                }
            }
        }
    }
    
    # Check if there's a catch-all proxy
    $proxyResource = $resources.items | Where-Object { $_.path -eq "/{proxy+}" }
    if ($proxyResource) {
        Write-Success "Found proxy resource: /{proxy+}"
    } else {
        Write-Warning "No proxy resource found - this might be the issue!"
    }
} else {
    Write-Error "No API Gateway found!"
}

# Step 5: Check CloudFront distribution
Write-Host "`n--- Step 5: Checking CloudFront Distribution ---" -ForegroundColor Yellow

# Get CloudFront distributions
$distributions = aws cloudfront list-distributions --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($distributions) {
    $targetDistribution = $distributions.DistributionList.Items | Where-Object { 
        $_.DomainName -eq "d2qvaswtmn22om.cloudfront.net" -or 
        $_.Aliases.Items -contains "d2qvaswtmn22om.cloudfront.net" 
    }
    
    if ($targetDistribution) {
        Write-Success "Found CloudFront distribution: $($targetDistribution.Id)"
        Write-Info "Domain: $($targetDistribution.DomainName)"
        Write-Info "Status: $($targetDistribution.Status)"
        
        # Check origins
        Write-Info "Origins:"
        foreach ($origin in $targetDistribution.Origins.Items) {
            Write-Info "  $($origin.Id): $($origin.DomainName)"
        }
        
        # Check behaviors
        Write-Info "Cache Behaviors:"
        if ($targetDistribution.DefaultCacheBehavior) {
            Write-Info "  Default: -> $($targetDistribution.DefaultCacheBehavior.TargetOriginId)"
        }
        
        if ($targetDistribution.CacheBehaviors.Items) {
            foreach ($behavior in $targetDistribution.CacheBehaviors.Items) {
                Write-Info "  $($behavior.PathPattern): -> $($behavior.TargetOriginId)"
            }
        }
    } else {
        Write-Warning "CloudFront distribution not found for d2qvaswtmn22om.cloudfront.net"
    }
} else {
    Write-Warning "Could not list CloudFront distributions"
}

# Step 6: Check recent BFF logs for actual errors
Write-Host "`n--- Step 6: Checking Recent BFF Logs ---" -ForegroundColor Yellow

$logGroup = "/aws/lambda/rds-dashboard-bff-prod"
$streams = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 3 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json

if ($streams -and $streams.logStreams.Count -gt 0) {
    Write-Success "Found $($streams.logStreams.Count) recent log streams"
    
    foreach ($stream in $streams.logStreams) {
        Write-Info "Checking log stream: $($stream.logStreamName)"
        
        $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $stream.logStreamName --limit 20 --region ap-southeast-1 --output json 2>$null | ConvertFrom-Json
        
        if ($events -and $events.events.Count -gt 0) {
            $errorEvents = $events.events | Where-Object { $_.message -match "ERROR|error|Error|500|fail" }
            
            if ($errorEvents.Count -gt 0) {
                Write-Warning "Found $($errorEvents.Count) error events in this stream:"
                foreach ($errorEvent in $errorEvents | Select-Object -First 5) {
                    Write-Warning "  $(Get-Date $errorEvent.timestamp -UFormat '%Y-%m-%d %H:%M:%S'): $($errorEvent.message)"
                }
            } else {
                Write-Info "No error events found in this stream"
            }
        }
    }
} else {
    Write-Warning "No recent log streams found for BFF"
}

Write-Host "`n=== Diagnosis Complete ===" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Check if the BFF is actually receiving requests from CloudFront" -ForegroundColor White
Write-Host "2. Verify API Gateway routing is correct" -ForegroundColor White
Write-Host "3. Check if the frontend is calling the right endpoints" -ForegroundColor White
Write-Host "4. Test the actual API endpoints that are failing" -ForegroundColor White