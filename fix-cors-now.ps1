#!/usr/bin/env pwsh

# Simple CORS fix for operations endpoint
$ApiGatewayId = "08mqqv008c"
$Region = "ap-southeast-1"
$Stage = "prod"

Write-Host "Fixing CORS for Operations Endpoint" -ForegroundColor Cyan

# Get operations resource ID
$resources = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region | ConvertFrom-Json
$operationsResource = $resources.items | Where-Object { $_.pathPart -eq "operations" }
$resourceId = $operationsResource.id

Write-Host "Operations Resource ID: $resourceId" -ForegroundColor Gray

# Add CORS headers to POST method response
Write-Host "Adding CORS headers to POST method..." -ForegroundColor Yellow

aws apigateway put-method-response `
    --rest-api-id $ApiGatewayId `
    --resource-id $resourceId `
    --http-method POST `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Origin=true" `
    --region $Region

aws apigateway put-integration-response `
    --rest-api-id $ApiGatewayId `
    --resource-id $resourceId `
    --http-method POST `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Origin='https://d2qvaswtmn22om.cloudfront.net'" `
    --region $Region

# Deploy changes
Write-Host "Deploying changes..." -ForegroundColor Yellow
aws apigateway create-deployment `
    --rest-api-id $ApiGatewayId `
    --stage-name $Stage `
    --description "Fix CORS for operations" `
    --region $Region

Write-Host "CORS fix deployed!" -ForegroundColor Green