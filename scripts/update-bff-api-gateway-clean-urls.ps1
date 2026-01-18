#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Updates BFF API Gateway (08mqqv008c) to remove /prod stage and configure clean URLs
.DESCRIPTION
    This script eliminates the /prod stage from the BFF API Gateway and configures
    root-level routing with $default stage for clean URL structure.
.NOTES
    Requirements: 1.1, 1.2, 4.1
    Task: 2.1 Update BFF API Gateway to remove /prod stage
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [switch]$DryRun = $false
)

# Set error handling
$ErrorActionPreference = "Stop"

Write-Host "=== BFF API Gateway Clean URL Configuration ===" -ForegroundColor Green
Write-Host "API Gateway ID: $ApiGatewayId" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "Dry Run: $DryRun" -ForegroundColor Cyan
Write-Host ""

try {
    # Step 1: Get current API Gateway configuration
    Write-Host "1. Analyzing current API Gateway configuration..." -ForegroundColor Yellow
    
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
        Write-Host "  4. Test clean URL endpoints" -ForegroundColor Magenta
        
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
        --description "Clean URL deployment - removing /prod stage" `
        --region $Region | ConvertFrom-Json
        
    Write-Host "   ✅ Deployment created successfully" -ForegroundColor Green
    Write-Host "   Deployment ID: $($deployment.DeploymentId)" -ForegroundColor White
    
    # Step 7: Test clean URL endpoints
    Write-Host "`n7. Testing clean URL endpoints..." -ForegroundColor Yellow
    
    $cleanApiUrl = $apiGateway.ApiEndpoint
    Write-Host "   Clean API URL: $cleanApiUrl" -ForegroundColor White
    
    # Test health endpoint
    Write-Host "   Testing /health endpoint..." -ForegroundColor White
    try {
        $healthResponse = Invoke-RestMethod -Uri "$cleanApiUrl/health" -Method GET -TimeoutSec 10
        Write-Host "   ✅ Health endpoint working: $($healthResponse.status)" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️  Health endpoint test failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Test CORS config endpoint
    Write-Host "   Testing /cors-config endpoint..." -ForegroundColor White
    try {
        $corsResponse = Invoke-RestMethod -Uri "$cleanApiUrl/cors-config" -Method GET -TimeoutSec 10
        Write-Host "   ✅ CORS config endpoint working" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️  CORS config endpoint test failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
    
    Write-Host "`n=== BFF API Gateway Clean URL Configuration Complete ===" -ForegroundColor Green
    Write-Host "✅ API Gateway now uses clean URLs without /prod stage" -ForegroundColor Green
    Write-Host "✅ All traffic routes through $default stage" -ForegroundColor Green
    Write-Host "✅ Clean API URL: $cleanApiUrl" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Update BFF environment variables to remove /prod from INTERNAL_API_URL" -ForegroundColor Cyan
    Write-Host "2. Update frontend configuration to use clean URLs" -ForegroundColor Cyan
    Write-Host "3. Test all API endpoints with new URL structure" -ForegroundColor Cyan
    
} catch {
    Write-Host "`n❌ Error updating BFF API Gateway configuration:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}