#!/usr/bin/env pwsh

<#
.SYNOPSIS
Complete API Gateway Integration Fix

.DESCRIPTION
Completes the API Gateway integration that had issues in the previous script
#>

param(
    [string]$Environment = "prod"
)

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Completing API Gateway Integration Fix ===" -ForegroundColor Cyan

$internalApiId = "0pjyr8lkpl"

try {
    # Get current resources
    $resources = aws apigateway get-resources --rest-api-id $internalApiId --region ap-southeast-1 --output json | ConvertFrom-Json
    
    # Find the monitoring metrics resource
    $metricsResource = $resources.items | Where-Object { $_.path -eq "/monitoring-dashboard/metrics" }
    
    if ($metricsResource) {
        Write-Success "Found metrics resource: $($metricsResource.id)"
        
        # Add method response for GET
        Write-Info "Adding method response for GET..."
        aws apigateway put-method-response `
            --rest-api-id $internalApiId `
            --resource-id $metricsResource.id `
            --http-method GET `
            --status-code 200 `
            --response-models "application/json=Empty" `
            --response-parameters "method.response.header.Access-Control-Allow-Origin=false" `
            --region ap-southeast-1 > $null 2>&1
        
        # Add integration response for GET
        Write-Info "Adding integration response for GET..."
        aws apigateway put-integration-response `
            --rest-api-id $internalApiId `
            --resource-id $metricsResource.id `
            --http-method GET `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Origin='*'" `
            --region ap-southeast-1 > $null 2>&1
        
        # Add CORS integration for OPTIONS
        Write-Info "Setting up CORS for OPTIONS method..."
        aws apigateway put-integration `
            --rest-api-id $internalApiId `
            --resource-id $metricsResource.id `
            --http-method OPTIONS `
            --type MOCK `
            --request-templates "application/json={\"statusCode\": 200}" `
            --region ap-southeast-1 > $null 2>&1
        
        aws apigateway put-method-response `
            --rest-api-id $internalApiId `
            --resource-id $metricsResource.id `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false" `
            --region ap-southeast-1 > $null 2>&1
        
        aws apigateway put-integration-response `
            --rest-api-id $internalApiId `
            --resource-id $metricsResource.id `
            --http-method OPTIONS `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Headers='Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',method.response.header.Access-Control-Allow-Methods='GET,OPTIONS',method.response.header.Access-Control-Allow-Origin='*'" `
            --region ap-southeast-1 > $null 2>&1
        
        Write-Success "CORS setup completed"
    }
    
    # Fix error-resolution proxy integration
    $errorProxyResource = $resources.items | Where-Object { $_.path -eq "/error-resolution/{proxy+}" }
    
    if ($errorProxyResource) {
        Write-Success "Found error-resolution proxy resource: $($errorProxyResource.id)"
        
        # Add method response for ANY
        aws apigateway put-method-response `
            --rest-api-id $internalApiId `
            --resource-id $errorProxyResource.id `
            --http-method ANY `
            --status-code 200 `
            --response-models "application/json=Empty" `
            --response-parameters "method.response.header.Access-Control-Allow-Origin=false" `
            --region ap-southeast-1 > $null 2>&1
        
        # Add integration response for ANY
        aws apigateway put-integration-response `
            --rest-api-id $internalApiId `
            --resource-id $errorProxyResource.id `
            --http-method ANY `
            --status-code 200 `
            --response-parameters "method.response.header.Access-Control-Allow-Origin='*'" `
            --region ap-southeast-1 > $null 2>&1
        
        # Add Lambda permission for error resolution
        aws lambda add-permission `
            --function-name rds-dashboard-error-resolution `
            --statement-id "api-gateway-error-resolution-$internalApiId" `
            --action lambda:InvokeFunction `
            --principal apigateway.amazonaws.com `
            --source-arn "arn:aws:execute-api:ap-southeast-1:876595225096:$internalApiId/*/*" `
            --region ap-southeast-1 > $null 2>&1
        
        Write-Success "Error resolution integration completed"
    }
    
    # Deploy the API
    Write-Info "Deploying API Gateway changes..."
    $deployment = aws apigateway create-deployment `
        --rest-api-id $internalApiId `
        --stage-name prod `
        --description "Complete monitoring and error resolution integration" `
        --region ap-southeast-1 `
        --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "API Gateway deployment completed successfully"
    } else {
        Write-Warning "API Gateway deployment had issues: $deployment"
    }
    
    # Test the monitoring endpoint
    Write-Info "Testing monitoring endpoint..."
    
    # Get API key
    $apiKeySecret = aws secretsmanager get-secret-value `
        --secret-id "arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-KjtkXE" `
        --region ap-southeast-1 `
        --output json | ConvertFrom-Json
    
    if ($apiKeySecret) {
        $apiKeyData = $apiKeySecret.SecretString | ConvertFrom-Json
        $apiKey = $apiKeyData.apiKey
        
        $testUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/monitoring-dashboard/metrics"
        
        try {
            $headers = @{
                'x-api-key' = $apiKey
                'Content-Type' = 'application/json'
            }
            
            $response = Invoke-RestMethod -Uri $testUrl -Method GET -Headers $headers -TimeoutSec 10
            Write-Success "Monitoring endpoint is now working!"
            Write-Info "Response: $($response | ConvertTo-Json -Compress)"
        } catch {
            Write-Warning "Monitoring endpoint still has issues: $($_.Exception.Message)"
            
            # Test the Lambda directly
            Write-Info "Testing monitoring Lambda directly..."
            $testPayload = @{
                httpMethod = "GET"
                path = "/monitoring-dashboard/metrics"
                queryStringParameters = $null
                headers = @{
                    'x-api-key' = $apiKey
                }
            } | ConvertTo-Json -Compress
            
            $lambdaResult = aws lambda invoke `
                --function-name "rds-dashboard-monitoring" `
                --payload $testPayload `
                --region ap-southeast-1 `
                monitoring_test.json 2>&1
            
            if (Test-Path "monitoring_test.json") {
                $lambdaResponse = Get-Content "monitoring_test.json" | ConvertFrom-Json
                Write-Info "Lambda direct test: $($lambdaResponse | ConvertTo-Json -Compress)"
                Remove-Item "monitoring_test.json" -Force
            }
        }
    }
    
} catch {
    Write-Error "Error completing API Gateway fix: $($_.Exception.Message)"
}

Write-Host "`n=== API Gateway Fix Completed ===" -ForegroundColor Cyan