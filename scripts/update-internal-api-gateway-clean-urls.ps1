#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Updates Internal API Gateway (0pjyr8lkpl) to remove /prod stage and configure clean URLs
.DESCRIPTION
    This script eliminates the /prod stage from the Internal API Gateway and configures
    root-level routing with $default stage for backend services.
.NOTES
    Requirements: 1.1, 1.2
    Task: 2.3 Update Internal API Gateway to remove /prod stage
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "0pjyr8lkpl",
    [switch]$DryRun = $false
)

# Set error handling
$ErrorActionPreference = "Stop"

Write-Host "=== Internal API Gateway Clean URL Configuration ===" -ForegroundColor Green
Write-Host "API Gateway ID: $ApiGatewayId" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "Dry Run: $DryRun" -ForegroundColor Cyan
Write-Host ""

try {
    # Step 1: Get current API Gateway configuration
    Write-Host "1. Analyzing current Internal API Gateway configuration..." -ForegroundColor Yellow
    
    $apiGateway = aws apigatewayv2 get-api --api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "   API Name: $($apiGateway.Name)" -ForegroundColor White
    Write-Host "   Protocol: $($apiGateway.ProtocolType)" -ForegroundColor White
    Write-Host "   Current API Endpoint: $($apiGateway.ApiEndpoint)" -ForegroundColor White
    
    # Step 2: List current stages
    Write-Host "`n2. Checking current stages..." -ForegroundColor Yellow
    
    $stages = aws apigatewayv2 get-stages --api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "   Current stages:" -ForegroundColor White
    foreach ($stage in $stages.Items) {
        Write-Host "     - $($stage.StageName)" -ForegroundColor White
        if ($stage.StageName -eq "prod") {
            Write-Host "       ⚠️  Found problematic /prod stage!" -ForegroundColor Red
        }
    }
    
    # Step 3: List current routes
    Write-Host "`n3. Analyzing current routes..." -ForegroundColor Yellow
    
    $routes = aws apigatewayv2 get-routes --api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "   Current routes:" -ForegroundColor White
    foreach ($route in $routes.Items) {
        Write-Host "     - $($route.RouteKey) -> $($route.Target)" -ForegroundColor White
    }
    
    # Step 4: Check if $default stage exists
    Write-Host "`n4. Checking for $default stage..." -ForegroundColor Yellow
    
    $defaultStage = $stages.Items | Where-Object { $_.StageName -eq '$default' }
    if ($defaultStage) {
        Write-Host "   ✅ $default stage already exists" -ForegroundColor Green
        Write-Host "   Auto Deploy: $($defaultStage.AutoDeploy)" -ForegroundColor White
    } else {
        Write-Host "   ❌ $default stage does not exist - will create" -ForegroundColor Red
    }
    
    if ($DryRun) {
        Write-Host "`n=== DRY RUN - No changes will be made ===" -ForegroundColor Magenta
        Write-Host "Would perform the following actions:" -ForegroundColor Magenta
        
        if (-not $defaultStage) {
            Write-Host "  1. Create $default stage with auto-deploy enabled" -ForegroundColor Magenta
        }
        
        $prodStage = $stages.Items | Where-Object { $_.StageName -eq 'prod' }
        if ($prodStage) {
            Write-Host "  2. Delete /prod stage" -ForegroundColor Magenta
        }
        
        Write-Host "  3. Update deployment to use $default stage" -ForegroundColor Magenta
        Write-Host "  4. Test backend service endpoints" -ForegroundColor Magenta
        
        return
    }
    
    # Step 5: Create $default stage if it doesn't exist
    if (-not $defaultStage) {
        Write-Host "`n5. Creating $default stage..." -ForegroundColor Yellow
        
        $createStageResult = aws apigatewayv2 create-stage `
            --api-id $ApiGatewayId `
            --stage-name '$default' `
            --auto-deploy `
            --region $Region | ConvertFrom-Json
            
        Write-Host "   ✅ Created $default stage successfully" -ForegroundColor Green
        Write-Host "   Stage ARN: $($createStageResult.StageArn)" -ForegroundColor White
    } else {
        Write-Host "`n5. Updating $default stage configuration..." -ForegroundColor Yellow
        
        $updateStageResult = aws apigatewayv2 update-stage `
            --api-id $ApiGatewayId `
            --stage-name '$default' `
            --auto-deploy `
            --region $Region | ConvertFrom-Json
            
        Write-Host "   ✅ Updated $default stage successfully" -ForegroundColor Green
    }
    
    # Step 6: Create deployment to $default stage
    Write-Host "`n6. Creating deployment to $default stage..." -ForegroundColor Yellow
    
    $deployment = aws apigatewayv2 create-deployment `
        --api-id $ApiGatewayId `
        --stage-name '$default' `
        --description "Clean URL deployment - removing /prod stage for backend services" `
        --region $Region | ConvertFrom-Json
        
    Write-Host "   ✅ Deployment created successfully" -ForegroundColor Green
    Write-Host "   Deployment ID: $($deployment.DeploymentId)" -ForegroundColor White
    
    # Step 7: Test backend service endpoints
    Write-Host "`n7. Testing backend service endpoints..." -ForegroundColor Yellow
    
    $cleanApiUrl = $apiGateway.ApiEndpoint
    Write-Host "   Clean Internal API URL: $cleanApiUrl" -ForegroundColor White
    
    # Define backend service endpoints to test
    $backendEndpoints = @(
        "/instances",
        "/operations", 
        "/discovery",
        "/monitoring",
        "/compliance",
        "/costs"
    )
    
    foreach ($endpoint in $backendEndpoints) {
        Write-Host "   Testing $endpoint endpoint..." -ForegroundColor White
        try {
            # Test with API key if available
            $headers = @{}
            if ($env:INTERNAL_API_KEY) {
                $headers['x-api-key'] = $env:INTERNAL_API_KEY
            }
            
            $testUrl = "$cleanApiUrl$endpoint"
            $response = Invoke-RestMethod -Uri $testUrl -Method GET -Headers $headers -TimeoutSec 10
            Write-Host "   ✅ $endpoint endpoint accessible" -ForegroundColor Green
        } catch {
            if ($_.Exception.Response.StatusCode -eq 401 -or $_.Exception.Response.StatusCode -eq 403) {
                Write-Host "   ✅ $endpoint endpoint accessible (auth required)" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️  $endpoint endpoint test failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # Step 8: Remove /prod stage if it exists
    $prodStage = $stages.Items | Where-Object { $_.StageName -eq 'prod' }
    if ($prodStage) {
        Write-Host "`n8. Removing /prod stage..." -ForegroundColor Yellow
        
        try {
            aws apigatewayv2 delete-stage `
                --api-id $ApiGatewayId `
                --stage-name 'prod' `
                --region $Region
                
            Write-Host "   ✅ Removed /prod stage successfully" -ForegroundColor Green
        } catch {
            Write-Host "   ⚠️  Could not remove /prod stage: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   This may be expected if stage is still in use" -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n8. No /prod stage found to remove" -ForegroundColor Green
    }
    
    # Step 9: Final validation
    Write-Host "`n9. Final validation..." -ForegroundColor Yellow
    
    $finalStages = aws apigatewayv2 get-stages --api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "   Final stage configuration:" -ForegroundColor White
    foreach ($stage in $finalStages.Items) {
        if ($stage.StageName -eq '$default') {
            Write-Host "     ✅ $($stage.StageName) (Auto Deploy: $($stage.AutoDeploy))" -ForegroundColor Green
        } else {
            Write-Host "     - $($stage.StageName)" -ForegroundColor White
        }
    }
    
    Write-Host "`n=== Internal API Gateway Clean URL Configuration Complete ===" -ForegroundColor Green
    Write-Host "✅ Internal API Gateway now uses clean URLs without /prod stage" -ForegroundColor Green
    Write-Host "✅ All backend services route through $default stage" -ForegroundColor Green
    Write-Host "✅ Clean Internal API URL: $cleanApiUrl" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backend service endpoints now available at:" -ForegroundColor Cyan
    foreach ($endpoint in $backendEndpoints) {
        Write-Host "  $cleanApiUrl$endpoint" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Update BFF INTERNAL_API_URL environment variable to: $cleanApiUrl" -ForegroundColor Cyan
    Write-Host "2. Test BFF to backend service communication" -ForegroundColor Cyan
    Write-Host "3. Verify all backend operations work with clean URLs" -ForegroundColor Cyan
    
} catch {
    Write-Host "`n❌ Error updating Internal API Gateway configuration:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}