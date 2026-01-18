#!/usr/bin/env pwsh

# Fix CORS for proxy resource (which handles all API routes)
$ApiGatewayId = "08mqqv008c"
$Region = "ap-southeast-1"
$Stage = "prod"
$ProxyResourceId = "ms0t5g"  # The {proxy+} resource ID

Write-Host "Fixing CORS for Proxy Resource" -ForegroundColor Cyan
Write-Host "API Gateway: $ApiGatewayId" -ForegroundColor Gray
Write-Host "Proxy Resource ID: $ProxyResourceId" -ForegroundColor Gray

# Check if OPTIONS method exists for proxy
Write-Host "Checking OPTIONS method for proxy..." -ForegroundColor Yellow
try {
    aws apigateway get-method --rest-api-id $ApiGatewayId --resource-id $ProxyResourceId --http-method OPTIONS --region $Region | Out-Null
    Write-Host "OPTIONS method exists for proxy" -ForegroundColor Green
} catch {
    Write-Host "Adding OPTIONS method for proxy..." -ForegroundColor Yellow
    
    # Add OPTIONS method
    aws apigateway put-method `
        --rest-api-id $ApiGatewayId `
        --resource-id $ProxyResourceId `
        --http-method OPTIONS `
        --authorization-type NONE `
        --region $Region
    
    # Add method response
    aws apigateway put-method-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $ProxyResourceId `
        --http-method OPTIONS `
        --status-code 200 `
        --response-parameters "method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Origin=true" `
        --region $Region
    
    # Add integration (MOCK for OPTIONS)
    aws apigateway put-integration `
        --rest-api-id $ApiGatewayId `
        --resource-id $ProxyResourceId `
        --http-method OPTIONS `
        --type MOCK `
        --request-templates '{"application/json":"{\"statusCode\":200}"}' `
        --region $Region
    
    # Add integration response
    aws apigateway put-integration-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $ProxyResourceId `
        --http-method OPTIONS `
        --status-code 200 `
        --response-parameters "method.response.header.Access-Control-Allow-Headers='Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',method.response.header.Access-Control-Allow-Methods='GET,POST,PUT,DELETE,OPTIONS',method.response.header.Access-Control-Allow-Origin='https://d2qvaswtmn22om.cloudfront.net'" `
        --region $Region
    
    Write-Host "OPTIONS method added for proxy" -ForegroundColor Green
}

# Update ANY method response headers (proxy uses ANY method)
Write-Host "Updating ANY method CORS headers for proxy..." -ForegroundColor Yellow

aws apigateway put-method-response `
    --rest-api-id $ApiGatewayId `
    --resource-id $ProxyResourceId `
    --http-method ANY `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Origin=true" `
    --region $Region

aws apigateway put-integration-response `
    --rest-api-id $ApiGatewayId `
    --resource-id $ProxyResourceId `
    --http-method ANY `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Origin='https://d2qvaswtmn22om.cloudfront.net'" `
    --region $Region

# Deploy changes
Write-Host "Deploying CORS fix..." -ForegroundColor Yellow
$deployment = aws apigateway create-deployment `
    --rest-api-id $ApiGatewayId `
    --stage-name $Stage `
    --description "Fix CORS for proxy resource - operations endpoint" `
    --region $Region | ConvertFrom-Json

Write-Host "CORS fix deployed! Deployment ID: $($deployment.id)" -ForegroundColor Green
Write-Host "Test URL: https://$ApiGatewayId.execute-api.$Region.amazonaws.com/$Stage/api/operations" -ForegroundColor Gray