#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple CORS fix for operations endpoint

.DESCRIPTION
Fixes CORS configuration for the operations endpoint using AWS CLI commands.
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [string]$Stage = "prod"
)

$ErrorActionPreference = "Stop"

Write-Host "🔧 Fixing CORS for Operations Endpoint" -ForegroundColor Cyan
Write-Host "API Gateway: $ApiGatewayId" -ForegroundColor Gray
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host "Stage: $Stage" -ForegroundColor Gray

try {
    # Get resources to find operations resource ID
    Write-Host "`n🔍 Finding operations resource..." -ForegroundColor Green
    $resources = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    $operationsResource = $resources.items | Where-Object { $_.pathPart -eq "operations" }
    
    if (-not $operationsResource) {
        Write-Host "❌ Operations resource not found" -ForegroundColor Red
        exit 1
    }
    
    $resourceId = $operationsResource.id
    Write-Host "✅ Found operations resource ID: $resourceId" -ForegroundColor Green
    
    # Check if OPTIONS method exists
    Write-Host "`n🔍 Checking OPTIONS method..." -ForegroundColor Green
    try {
        aws apigateway get-method --rest-api-id $ApiGatewayId --resource-id $resourceId --http-method OPTIONS --region $Region | Out-Null
        Write-Host "✅ OPTIONS method exists" -ForegroundColor Green
    } catch {
        Write-Host "➕ Adding OPTIONS method..." -ForegroundColor Yellow
        
        # Create OPTIONS method
        aws apigateway put-method `
            --rest-api-id $ApiGatewayId `
            --resource-id $resourceId `
            --http-method OPTIONS `
            --authorization-type NONE `
            --region $Region
        
        # Add method response
        aws apigateway put-method-response `
            --rest-api-id $ApiGatewayId `
            --resource-id $resourceId `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Origin=true" `
            --region $Region
        
        # Add integration
        aws apigateway put-integration `
            --rest-api-id $ApiGatewayId `
            --resource-id $resourceId `
            --http-method OPTIONS `
            --type MOCK `
            --request-templates '{"application/json":"{\"statusCode\":200}"}' `
            --region $Region
        
        # Add integration response
        aws apigateway put-integration-response `
            --rest-api-id $ApiGatewayId `
            --resource-id $resourceId `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Headers='Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',method.response.header.Access-Control-Allow-Methods='GET,POST,PUT,DELETE,OPTIONS',method.response.header.Access-Control-Allow-Origin='https://d2qvaswtmn22om.cloudfront.net'" `
            --region $Region
        
        Write-Host "✅ OPTIONS method added" -ForegroundColor Green
    }
    
    # Update POST method response headers
    Write-Host "`n🔧 Updating POST method CORS headers..." -ForegroundColor Green
    
    # Update method response for POST
    aws apigateway put-method-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $resourceId `
        --http-method POST `
        --status-code 200 `
        --response-parameters "method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true" `
        --region $Region
    
    # Update integration response for POST
    aws apigateway put-integration-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $resourceId `
        --http-method POST `
        --status-code 200 `
        --response-parameters "method.response.header.Access-Control-Allow-Origin='https://d2qvaswtmn22om.cloudfront.net',method.response.header.Access-Control-Allow-Headers='Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',method.response.header.Access-Control-Allow-Methods='GET,POST,PUT,DELETE,OPTIONS'" `
        --region $Region
    
    Write-Host "✅ POST method CORS headers updated" -ForegroundColor Green
    
    # Deploy changes
    Write-Host "`n🚀 Deploying changes..." -ForegroundColor Green
    $deployment = aws apigateway create-deployment `
        --rest-api-id $ApiGatewayId `
        --stage-name $Stage `
        --description "Fix CORS for operations endpoint - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        --region $Region | ConvertFrom-Json
    
    Write-Host "✅ Deployment created: $($deployment.id)" -ForegroundColor Green
    
    Write-Host "`n🎉 CORS Fix Complete!" -ForegroundColor Green
    Write-Host "✅ Operations endpoint should now work from CloudFront" -ForegroundColor Green
    Write-Host "✅ Test URL: https://$ApiGatewayId.execute-api.$Region.amazonaws.com/$Stage/api/operations" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Test operations from the dashboard UI" -ForegroundColor Gray
Write-Host "2. Run: ./scripts/test-cors-operations-fix.ps1" -ForegroundColor Gray