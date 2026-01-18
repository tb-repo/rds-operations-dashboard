#!/usr/bin/env pwsh

<#
.SYNOPSIS
Comprehensive CORS fix for all API endpoints

.DESCRIPTION
Fixes CORS configuration for all API endpoints to allow CloudFront origin access.
Adds OPTIONS methods and CORS headers to all endpoints.
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [string]$Stage = "prod",
    [string]$CloudFrontOrigin = "https://d2qvaswtmn22om.cloudfront.net"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Comprehensive CORS Fix for All Endpoints" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "API Gateway: $ApiGatewayId" -ForegroundColor Gray
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host "Stage: $Stage" -ForegroundColor Gray
Write-Host "Allowed Origin: $CloudFrontOrigin" -ForegroundColor Gray
Write-Host ""

# Endpoints to fix
$endpoints = @(
    @{ Path = "instances"; Methods = @("GET", "POST") },
    @{ Path = "operations"; Methods = @("POST") },
    @{ Path = "compliance"; Methods = @("GET") },
    @{ Path = "costs"; Methods = @("GET") },
    @{ Path = "health"; Methods = @("GET") }
)

function Add-CorsToEndpoint {
    param(
        [string]$ResourceId,
        [string]$Path,
        [string[]]$Methods
    )
    
    Write-Host "🔧 Fixing CORS for /$Path" -ForegroundColor Green
    
    # Add OPTIONS method
    Write-Host "  ➕ Adding OPTIONS method..." -ForegroundColor Yellow
    try {
        # Create OPTIONS method
        aws apigateway put-method `
            --rest-api-id $ApiGatewayId `
            --resource-id $ResourceId `
            --http-method OPTIONS `
            --authorization-type NONE `
            --region $Region 2>&1 | Out-Null
        
        # Add method response
        aws apigateway put-method-response `
            --rest-api-id $ApiGatewayId `
            --resource-id $ResourceId `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Origin=true" `
            --region $Region 2>&1 | Out-Null
        
        # Add integration
        $requestTemplate = '{"application/json":"{\"statusCode\":200}"}'
        aws apigateway put-integration `
            --rest-api-id $ApiGatewayId `
            --resource-id $ResourceId `
            --http-method OPTIONS `
            --type MOCK `
            --request-templates $requestTemplate `
            --region $Region 2>&1 | Out-Null
        
        # Add integration response
        $responseParams = @{
            "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
            "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
            "method.response.header.Access-Control-Allow-Origin" = "'$CloudFrontOrigin'"
        }
        $responseParamsJson = $responseParams | ConvertTo-Json -Compress
        
        aws apigateway put-integration-response `
            --rest-api-id $ApiGatewayId `
            --resource-id $ResourceId `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters $responseParamsJson `
            --region $Region 2>&1 | Out-Null
        
        Write-Host "  ✅ OPTIONS method configured" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️  OPTIONS method may already exist" -ForegroundColor Yellow
    }
    
    # Update each HTTP method with CORS headers
    foreach ($method in $Methods) {
        Write-Host "  🔧 Updating $method method CORS headers..." -ForegroundColor Yellow
        
        try {
            # Update method response
            aws apigateway put-method-response `
                --rest-api-id $ApiGatewayId `
                --resource-id $ResourceId `
                --http-method $method `
                --status-code 200 `
                --response-parameters "method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true" `
                --region $Region 2>&1 | Out-Null
            
            # Update integration response
            $methodResponseParams = @{
                "method.response.header.Access-Control-Allow-Origin" = "'$CloudFrontOrigin'"
                "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
                "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
            }
            $methodResponseParamsJson = $methodResponseParams | ConvertTo-Json -Compress
            
            aws apigateway put-integration-response `
                --rest-api-id $ApiGatewayId `
                --resource-id $ResourceId `
                --http-method $method `
                --status-code 200 `
                --response-parameters $methodResponseParamsJson `
                --region $Region 2>&1 | Out-Null
            
            Write-Host "  ✅ $method method CORS headers updated" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️  Could not update $method method (may not exist)" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}

try {
    # Get all resources
    Write-Host "🔍 Discovering API resources..." -ForegroundColor Green
    $resources = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "✅ Found $($resources.items.Count) resources" -ForegroundColor Green
    Write-Host ""
    
    # Fix CORS for each endpoint
    foreach ($endpoint in $endpoints) {
        $resource = $resources.items | Where-Object { $_.pathPart -eq $endpoint.Path }
        
        if ($resource) {
            Add-CorsToEndpoint -ResourceId $resource.id -Path $endpoint.Path -Methods $endpoint.Methods
        } else {
            Write-Host "⚠️  Resource /$($endpoint.Path) not found - skipping" -ForegroundColor Yellow
            Write-Host ""
        }
    }
    
    # Deploy changes
    Write-Host "🚀 Deploying changes to $Stage stage..." -ForegroundColor Green
    $deployment = aws apigateway create-deployment `
        --rest-api-id $ApiGatewayId `
        --stage-name $Stage `
        --description "Fix CORS for all endpoints - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        --region $Region | ConvertFrom-Json
    
    Write-Host "✅ Deployment created: $($deployment.id)" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "🎉 CORS Fix Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "✅ All endpoints configured with CORS headers" -ForegroundColor Green
    Write-Host "✅ CloudFront origin allowed: $CloudFrontOrigin" -ForegroundColor Green
    Write-Host "✅ API Gateway deployed to $Stage stage" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Wait 30-60 seconds for deployment to propagate" -ForegroundColor Gray
    Write-Host "2. Refresh dashboard: $CloudFrontOrigin" -ForegroundColor Gray
    Write-Host "3. Check browser console for CORS errors (should be gone)" -ForegroundColor Gray
    Write-Host "4. Verify all 3 instances appear on dashboard" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🔗 API Gateway URL:" -ForegroundColor Cyan
    Write-Host "   https://$ApiGatewayId.execute-api.$Region.amazonaws.com/$Stage/api/" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "❌ Error Occurred" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify AWS CLI is configured correctly" -ForegroundColor Gray
    Write-Host "2. Check you have permissions to modify API Gateway" -ForegroundColor Gray
    Write-Host "3. Verify API Gateway ID is correct: $ApiGatewayId" -ForegroundColor Gray
    Write-Host "4. Check region is correct: $Region" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
