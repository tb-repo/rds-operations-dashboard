#!/usr/bin/env pwsh

<#
.SYNOPSIS
Fix CORS configuration for the operations endpoint in API Gateway

.DESCRIPTION
The operations backend is working correctly and returning proper CORS headers,
but API Gateway is not configured to handle CORS for the /prod/api/operations endpoint.
This script fixes the CORS configuration specifically for the operations endpoint.

.NOTES
This addresses the CORS error:
"Access to XMLHttpRequest at 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations' 
from origin 'https://d2qvaswtmn22om.cloudfront.net' has been blocked by CORS policy: 
No 'Access-Control-Allow-Origin' header is present on the requested resource."
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$ApiGatewayId = "08mqqv008c",
    [string]$Stage = "prod",
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

Write-Host "🔧 Fixing CORS Configuration for Operations Endpoint" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host "API Gateway ID: $ApiGatewayId" -ForegroundColor Gray
Write-Host "Stage: $Stage" -ForegroundColor Gray
Write-Host "CloudFront Origin: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "🧪 DRY RUN MODE - No changes will be made" -ForegroundColor Yellow
}

try {
    # Step 1: Get current API Gateway configuration
    Write-Host "`n📋 Step 1: Getting current API Gateway configuration..." -ForegroundColor Green
    
    $apiInfo = aws apigateway get-rest-api --rest-api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    Write-Host "API Name: $($apiInfo.name)" -ForegroundColor Gray
    Write-Host "API Description: $($apiInfo.description)" -ForegroundColor Gray
    
    # Step 2: Find the operations resource
    Write-Host "`n🔍 Step 2: Finding operations resource..." -ForegroundColor Green
    
    $resources = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region | ConvertFrom-Json
    $operationsResource = $resources.items | Where-Object { $_.pathPart -eq "operations" }
    
    if (-not $operationsResource) {
        Write-Host "❌ Operations resource not found in API Gateway" -ForegroundColor Red
        Write-Host "Available resources:" -ForegroundColor Gray
        $resources.items | ForEach-Object {
            Write-Host "  - $($_.path) (ID: $($_.id))" -ForegroundColor Gray
        }
        exit 1
    }
    
    Write-Host "✅ Found operations resource: $($operationsResource.path) (ID: $($operationsResource.id))" -ForegroundColor Green
    
    # Step 3: Check current CORS configuration
    Write-Host "`n🔍 Step 3: Checking current CORS configuration..." -ForegroundColor Green
    
    try {
        $optionsMethod = aws apigateway get-method --rest-api-id $ApiGatewayId --resource-id $operationsResource.id --http-method OPTIONS --region $Region 2>$null | ConvertFrom-Json
        Write-Host "✅ OPTIONS method exists for operations resource" -ForegroundColor Green
        Write-Host "Current OPTIONS method configuration:" -ForegroundColor Gray
        Write-Host ($optionsMethod | ConvertTo-Json -Depth 3) -ForegroundColor Gray
    } catch {
        Write-Host "❌ No OPTIONS method found for operations resource" -ForegroundColor Red
        $optionsMethod = $null
    }
    
    # Step 4: Check POST method CORS headers
    Write-Host "`n🔍 Step 4: Checking POST method configuration..." -ForegroundColor Green
    
    try {
        $postMethod = aws apigateway get-method --rest-api-id $ApiGatewayId --resource-id $operationsResource.id --http-method POST --region $Region | ConvertFrom-Json
        Write-Host "✅ POST method exists for operations resource" -ForegroundColor Green
        
        # Check method response headers
        if ($postMethod.methodResponses."200".responseParameters) {
            Write-Host "Current POST method response headers:" -ForegroundColor Gray
            $postMethod.methodResponses."200".responseParameters | ConvertTo-Json -Depth 2 | Write-Host -ForegroundColor Gray
        } else {
            Write-Host "❌ No response headers configured for POST method" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ POST method not found for operations resource" -ForegroundColor Red
        exit 1
    }
    
    # Step 5: Fix CORS configuration
    Write-Host "`n🔧 Step 5: Fixing CORS configuration..." -ForegroundColor Green
    
    if (-not $DryRun) {
        # Add OPTIONS method if it doesn't exist
        if (-not $optionsMethod) {
            Write-Host "➕ Adding OPTIONS method for CORS preflight..." -ForegroundColor Yellow
            
            $optionsMethodParams = @{
                "rest-api-id" = $ApiGatewayId
                "resource-id" = $operationsResource.id
                "http-method" = "OPTIONS"
                "authorization-type" = "NONE"
                "region" = $Region
            }
            
            aws apigateway put-method @optionsMethodParams
            
            # Add method response for OPTIONS
            $optionsResponseParams = @{
                "rest-api-id" = $ApiGatewayId
                "resource-id" = $operationsResource.id
                "http-method" = "OPTIONS"
                "status-code" = "200"
                "response-parameters" = (@{
                    "method.response.header.Access-Control-Allow-Headers" = $true
                    "method.response.header.Access-Control-Allow-Methods" = $true
                    "method.response.header.Access-Control-Allow-Origin" = $true
                } | ConvertTo-Json -Compress)
                "region" = $Region
            }
            
            aws apigateway put-method-response @optionsResponseParams
            
            # Add integration for OPTIONS
            $optionsIntegrationParams = @{
                "rest-api-id" = $ApiGatewayId
                "resource-id" = $operationsResource.id
                "http-method" = "OPTIONS"
                "type" = "MOCK"
                "integration-http-method" = "OPTIONS"
                "request-templates" = '{"application/json": "{\"statusCode\": 200}"}' 
                "region" = $Region
            }
            
            aws apigateway put-integration @optionsIntegrationParams
            
            # Add integration response for OPTIONS
            $optionsIntegrationResponseParams = @{
                "rest-api-id" = $ApiGatewayId
                "resource-id" = $operationsResource.id
                "http-method" = "OPTIONS"
                "status-code" = "200"
                "response-parameters" = (@{
                    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
                    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
                    "method.response.header.Access-Control-Allow-Origin" = "'https://d2qvaswtmn22om.cloudfront.net'"
                } | ConvertTo-Json -Compress)
                "region" = $Region
            }
            
            aws apigateway put-integration-response @optionsIntegrationResponseParams
            
            Write-Host "✅ OPTIONS method added successfully" -ForegroundColor Green
        } else {
            Write-Host "✅ OPTIONS method already exists" -ForegroundColor Green
        }
        
        # Update POST method response headers
        Write-Host "🔧 Updating POST method CORS headers..." -ForegroundColor Yellow
        
        # Add CORS headers to POST method response
        $postResponseParams = @{
            "rest-api-id" = $ApiGatewayId
            "resource-id" = $operationsResource.id
            "http-method" = "POST"
            "status-code" = "200"
            "response-parameters" = (@{
                "method.response.header.Access-Control-Allow-Origin" = $true
                "method.response.header.Access-Control-Allow-Headers" = $true
                "method.response.header.Access-Control-Allow-Methods" = $true
            } | ConvertTo-Json -Compress)
            "region" = $Region
        }
        
        aws apigateway put-method-response @postResponseParams
        
        # Update integration response headers for POST
        $postIntegrationResponseParams = @{
            "rest-api-id" = $ApiGatewayId
            "resource-id" = $operationsResource.id
            "http-method" = "POST"
            "status-code" = "200"
            "response-parameters" = (@{
                "method.response.header.Access-Control-Allow-Origin" = "'https://d2qvaswtmn22om.cloudfront.net'"
                "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
                "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
            } | ConvertTo-Json -Compress)
            "region" = $Region
        }
        
        aws apigateway put-integration-response @postIntegrationResponseParams
        
        Write-Host "✅ POST method CORS headers updated successfully" -ForegroundColor Green
        
        # Step 6: Deploy changes
        Write-Host "`n🚀 Step 6: Deploying changes to $Stage stage..." -ForegroundColor Green
        
        $deploymentParams = @{
            "rest-api-id" = $ApiGatewayId
            "stage-name" = $Stage
            "description" = "Fix CORS configuration for operations endpoint - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "region" = $Region
        }
        
        $deployment = aws apigateway create-deployment @deploymentParams | ConvertFrom-Json
        Write-Host "✅ Deployment created: $($deployment.id)" -ForegroundColor Green
        
        # Step 7: Verify the fix
        Write-Host "`n✅ Step 7: Verifying CORS fix..." -ForegroundColor Green
        
        $testUrl = "https://$ApiGatewayId.execute-api.$Region.amazonaws.com/$Stage/api/operations"
        Write-Host "Testing CORS preflight request to: $testUrl" -ForegroundColor Gray
        
        # Test OPTIONS request
        try {
            $optionsResponse = curl -s -X OPTIONS $testUrl `
                -H "Origin: https://d2qvaswtmn22om.cloudfront.net" `
                -H "Access-Control-Request-Method: POST" `
                -H "Access-Control-Request-Headers: Content-Type,Authorization" `
                -i
            
            if ($optionsResponse -match "Access-Control-Allow-Origin") {
                Write-Host "✅ CORS preflight request successful" -ForegroundColor Green
                Write-Host "CORS headers found in response" -ForegroundColor Gray
            } else {
                Write-Host "⚠️  CORS headers may not be properly configured" -ForegroundColor Yellow
                Write-Host "Response preview:" -ForegroundColor Gray
                Write-Host ($optionsResponse | Select-Object -First 10) -ForegroundColor Gray
            }
        } catch {
            Write-Host "⚠️  Could not test CORS preflight (this is normal if authentication is required)" -ForegroundColor Yellow
        }
        
        Write-Host "`n🎉 CORS Configuration Fix Complete!" -ForegroundColor Green
        Write-Host "✅ Operations endpoint should now work from CloudFront origin" -ForegroundColor Green
        Write-Host "✅ API Gateway URL: $testUrl" -ForegroundColor Green
        Write-Host "✅ Allowed Origin: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Green
        
    } else {
        Write-Host "🧪 DRY RUN: Would fix CORS configuration for operations endpoint" -ForegroundColor Yellow
        Write-Host "  - Add/update OPTIONS method for CORS preflight" -ForegroundColor Gray
        Write-Host "  - Update POST method response headers" -ForegroundColor Gray
        Write-Host "  - Deploy changes to $Stage stage" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "`n❌ Error fixing CORS configuration: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Gray
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Test operations from the dashboard UI" -ForegroundColor Gray
Write-Host "2. Check browser console for any remaining CORS errors" -ForegroundColor Gray
Write-Host "3. If issues persist, check CloudWatch logs for the operations Lambda" -ForegroundColor Gray
Write-Host "4. Proceed with Phase 2: Cross-Account Discovery Fix" -ForegroundColor Gray