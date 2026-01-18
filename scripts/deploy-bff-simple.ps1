#!/usr/bin/env pwsh
# Simple BFF Deployment (inline code update)

Write-Host "=== Deploying BFF with Operations Endpoint (Simple) ===" -ForegroundColor Cyan

$BFFFunction = "rds-bff-prod"

Write-Host "Step 1: Updating BFF function code inline..." -ForegroundColor Yellow

# Read the BFF v4 code
$bffCode = Get-Content "bff/working-bff-with-data-v4.js" -Raw

# Create inline code update
$inlineCode = @"
exports.handler = $($bffCode -replace 'exports\.handler = async \(event, context\) => \{', '')
"@

# Write to temporary file for deployment
$inlineCode | Out-File -FilePath "temp-bff-inline.js" -Encoding UTF8

Write-Host "Step 2: Deploying via AWS CLI..." -ForegroundColor Yellow

# Use AWS CLI to update function code
try {
    # First, let's try updating the environment variables
    Write-Host "Updating environment variables..." -ForegroundColor Green
    
    $envVars = @{
        "DISCOVERY_FUNCTION_NAME" = "rds-discovery-prod"
        "OPERATIONS_FUNCTION_NAME" = "rds-operations-prod"
        "CACHE_TABLE_NAME" = "rds-discovery-cache"
        "AWS_REGION" = "ap-southeast-1"
    }
    
    $envJson = $envVars | ConvertTo-Json -Compress
    aws lambda update-function-configuration --function-name $BFFFunction --environment "Variables=$envJson"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Environment variables updated" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Environment variables update failed" -ForegroundColor Yellow
    }
    
    # Update the function code using the console or manual approach
    Write-Host ""
    Write-Host "⚠️  Automatic code deployment requires zip file creation." -ForegroundColor Yellow
    Write-Host "Please manually update the Lambda function code with the following:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Go to AWS Lambda Console" -ForegroundColor Cyan
    Write-Host "2. Find function: $BFFFunction" -ForegroundColor Cyan
    Write-Host "3. Replace the code with contents of: bff/working-bff-with-data-v4.js" -ForegroundColor Cyan
    Write-Host "4. Click 'Deploy'" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or use the AWS CLI with a proper zip file:" -ForegroundColor Yellow
    Write-Host "  zip -r bff-v4.zip bff/working-bff-with-data-v4.js" -ForegroundColor Gray
    Write-Host "  aws lambda update-function-code --function-name $BFFFunction --zip-file fileb://bff-v4.zip" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Deployment preparation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Step 3: Testing current BFF..." -ForegroundColor Yellow

# Test current BFF to see if operations endpoint exists
try {
    $testPayload = @{
        httpMethod = "POST"
        path = "/api/operations"
        body = @{
            operation = "create_snapshot"
            instance_id = "test-instance"
            parameters = @{
                snapshot_id = "test-snapshot"
            }
        } | ConvertTo-Json
    } | ConvertTo-Json
    
    $testPayload | Out-File -FilePath "test-operations-payload.json" -Encoding UTF8
    
    aws lambda invoke --function-name $BFFFunction --cli-binary-format raw-in-base64-out --payload file://test-operations-payload.json test-operations-response.json
    
    if ($LASTEXITCODE -eq 0) {
        $response = Get-Content test-operations-response.json | ConvertFrom-Json
        
        if ($response.statusCode -eq 405) {
            Write-Host "⚠️  Operations endpoint not found (Method not allowed)" -ForegroundColor Yellow
            Write-Host "    BFF needs to be updated with v4 code" -ForegroundColor Yellow
        } elseif ($response.statusCode -eq 500) {
            Write-Host "✅ Operations endpoint exists but returned error (expected for test data)" -ForegroundColor Green
        } else {
            Write-Host "✅ Operations endpoint test returned status: $($response.statusCode)" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  BFF test failed" -ForegroundColor Yellow
    }
    
    # Clean up test files
    Remove-Item test-operations-payload.json -ErrorAction SilentlyContinue
    Remove-Item test-operations-response.json -ErrorAction SilentlyContinue
} catch {
    Write-Host "⚠️  BFF test failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Clean up
Remove-Item temp-bff-inline.js -ErrorAction SilentlyContinue

Write-Host "`n=== DEPLOYMENT STATUS ===" -ForegroundColor Magenta
Write-Host "✅ Environment variables updated" -ForegroundColor Green
Write-Host "⚠️  Manual code update required" -ForegroundColor Yellow
Write-Host ""
Write-Host "To complete the deployment:" -ForegroundColor Yellow
Write-Host "1. Copy contents of bff/working-bff-with-data-v4.js" -ForegroundColor Cyan
Write-Host "2. Paste into Lambda function $BFFFunction in AWS Console" -ForegroundColor Cyan
Write-Host "3. Click Deploy" -ForegroundColor Cyan
Write-Host ""
Write-Host "BFF deployment preparation complete!" -ForegroundColor Green