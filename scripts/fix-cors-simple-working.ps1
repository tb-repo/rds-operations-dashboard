#!/usr/bin/env pwsh

<#
.SYNOPSIS
Simple CORS fix for API Gateway endpoints

.DESCRIPTION
Fixes CORS configuration for API Gateway to allow CloudFront origin access.
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [string]$Stage = "prod",
    [string]$CloudFrontOrigin = "https://d2qvaswtmn22om.cloudfront.net"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "Simple CORS Fix for API Gateway"
Write-Host "========================================"
Write-Host ""
Write-Host "API Gateway: $ApiGatewayId"
Write-Host "Region: $Region"
Write-Host "Stage: $Stage"
Write-Host "Allowed Origin: $CloudFrontOrigin"
Write-Host ""

# Endpoints to fix
$endpoints = @("instances", "operations", "compliance", "costs", "health")

try {
    # Get all resources
    Write-Host "Discovering API resources..."
    $resourcesJson = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region
    $resources = $resourcesJson | ConvertFrom-Json
    Write-Host "Found $($resources.items.Count) resources"
    Write-Host ""
    
    # Fix CORS for each endpoint
    foreach ($endpointPath in $endpoints) {
        $resource = $resources.items | Where-Object { $_.pathPart -eq $endpointPath }
        
        if (-not $resource) {
            Write-Host "WARNING: Resource /$endpointPath not found - skipping"
            continue
        }
        
        $resourceId = $resource.id
        Write-Host "Fixing CORS for /$endpointPath (Resource ID: $resourceId)"
        
        # Add OPTIONS method
        Write-Host "  Adding OPTIONS method..."
        try {
            aws apigateway put-method --rest-api-id $ApiGatewayId --resource-id $resourceId --http-method OPTIONS --authorization-type NONE --region $Region 2>&1 | Out-Null
            
            aws apigateway put-method-response --rest-api-id $ApiGatewayId --resource-id $resourceId --http-method OPTIONS --status-code 200 --response-parameters "method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Origin=true" --region $Region 2>&1 | Out-Null
            
            aws apigateway put-integration --rest-api-id $ApiGatewayId --resource-id $resourceId --http-method OPTIONS --type MOCK --region $Region 2>&1 | Out-Null
            
            # Create response parameters file
            $responseParamsFile = "cors-response-params-$resourceId.json"
            @{
                "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
                "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
                "method.response.header.Access-Control-Allow-Origin" = "'$CloudFrontOrigin'"
            } | ConvertTo-Json | Out-File -FilePath $responseParamsFile -Encoding utf8
            
            aws apigateway put-integration-response --rest-api-id $ApiGatewayId --resource-id $resourceId --http-method OPTIONS --status-code 200 --response-parameters file://$responseParamsFile --region $Region 2>&1 | Out-Null
            
            Remove-Item $responseParamsFile -ErrorAction SilentlyContinue
            
            Write-Host "  OPTIONS method configured"
        } catch {
            Write-Host "  OPTIONS method may already exist"
        }
        
        Write-Host ""
    }
    
    # Deploy changes
    Write-Host "Deploying changes to $Stage stage..."
    $deploymentJson = aws apigateway create-deployment --rest-api-id $ApiGatewayId --stage-name $Stage --description "Fix CORS - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" --region $Region
    $deployment = $deploymentJson | ConvertFrom-Json
    
    Write-Host "Deployment created: $($deployment.id)"
    Write-Host ""
    
    Write-Host "========================================"
    Write-Host "CORS Fix Complete!"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Wait 30-60 seconds for deployment to propagate"
    Write-Host "2. Refresh dashboard: $CloudFrontOrigin"
    Write-Host "3. Check browser console for CORS errors"
    Write-Host "4. Verify all 3 instances appear on dashboard"
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "Error Occurred"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "1. Verify AWS CLI is configured correctly"
    Write-Host "2. Check you have permissions to modify API Gateway"
    Write-Host "3. Verify API Gateway ID is correct: $ApiGatewayId"
    Write-Host "4. Check region is correct: $Region"
    Write-Host ""
    exit 1
}
