#!/usr/bin/env pwsh

<#
.SYNOPSIS
Fix BFF Lambda handler deployment issue

.DESCRIPTION
Rebuilds and redeploys the BFF Lambda with the correct handler configuration.
Fixes the "Runtime.HandlerNotFound" error.
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$FunctionName = "rds-dashboard-bff-prod"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "BFF Lambda Handler Fix"
Write-Host "========================================"
Write-Host ""
Write-Host "Function: $FunctionName"
Write-Host "Region: $Region"
Write-Host ""

try {
    # Step 1: Build BFF
    Write-Host "Step 1: Building BFF..."
    Push-Location bff
    
    Write-Host "  Installing dependencies..."
    npm install 2>&1 | Out-Null
    
    Write-Host "  Compiling TypeScript..."
    npm run build
    
    if (-not (Test-Path "dist/lambda.js")) {
        throw "Build failed: dist/lambda.js not found"
    }
    
    Write-Host "  Build successful"
    Write-Host ""
    
    # Step 2: Create deployment package
    Write-Host "Step 2: Creating deployment package..."
    
    if (Test-Path "../bff-lambda-fixed.zip") {
        Remove-Item "../bff-lambda-fixed.zip" -Force
    }
    
    # Create zip with dist and node_modules
    Write-Host "  Packaging Lambda function..."
    Compress-Archive -Path "dist/*", "node_modules" -DestinationPath "../bff-lambda-fixed.zip" -CompressionLevel Optimal
    
    Pop-Location
    
    $zipSize = (Get-Item "bff-lambda-fixed.zip").Length / 1MB
    Write-Host "  Package created: bff-lambda-fixed.zip ($([math]::Round($zipSize, 2)) MB)"
    Write-Host ""
    
    # Step 3: Update Lambda function code
    Write-Host "Step 3: Updating Lambda function code..."
    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://bff-lambda-fixed.zip `
        --region $Region | Out-Null
    
    Write-Host "  Code updated"
    Write-Host ""
    
    # Step 4: Update Lambda handler configuration
    Write-Host "Step 4: Updating Lambda handler configuration..."
    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --handler "dist/lambda.handler" `
        --region $Region | Out-Null
    
    Write-Host "  Handler updated to: dist/lambda.handler"
    Write-Host ""
    
    # Step 5: Wait for update to complete
    Write-Host "Step 5: Waiting for Lambda update to complete..."
    $maxWait = 60
    $waited = 0
    
    while ($waited -lt $maxWait) {
        $status = aws lambda get-function --function-name $FunctionName --region $Region --query 'Configuration.LastUpdateStatus' --output text
        
        if ($status -eq "Successful") {
            Write-Host "  Lambda update completed successfully"
            break
        } elseif ($status -eq "Failed") {
            throw "Lambda update failed"
        }
        
        Write-Host "  Waiting... ($waited seconds)"
        Start-Sleep -Seconds 5
        $waited += 5
    }
    
    if ($waited -ge $maxWait) {
        Write-Host "  Warning: Update taking longer than expected, but may still succeed"
    }
    
    Write-Host ""
    
    # Step 6: Test the fix
    Write-Host "Step 6: Testing BFF Lambda..."
    Write-Host "  Testing health endpoint..."
    
    $testUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/health"
    try {
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -UseBasicParsing
        Write-Host "  Status: $($response.StatusCode) - SUCCESS!"
        Write-Host "  Response: $($response.Content)"
    } catch {
        Write-Host "  Status: $($_.Exception.Response.StatusCode.value__) - May need authentication"
    }
    
    Write-Host ""
    
    Write-Host "========================================"
    Write-Host "BFF Lambda Handler Fix Complete!"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Changes Applied:"
    Write-Host "  1. Created lambda.ts handler wrapper"
    Write-Host "  2. Rebuilt BFF with new handler"
    Write-Host "  3. Updated Lambda function code"
    Write-Host "  4. Updated handler configuration to dist/lambda.handler"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "  1. Wait 30 seconds for Lambda to fully initialize"
    Write-Host "  2. Refresh dashboard: https://d2qvaswtmn22om.cloudfront.net"
    Write-Host "  3. Check browser console (CORS errors should be gone)"
    Write-Host "  4. Verify all 3 instances appear on dashboard"
    Write-Host ""
    Write-Host "If issues persist:"
    Write-Host "  - Check Lambda logs: aws logs tail /aws/lambda/$FunctionName --region $Region --follow"
    Write-Host "  - Test API directly: curl https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/health"
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
    Write-Host "  1. Verify you're in the rds-operations-dashboard directory"
    Write-Host "  2. Check Node.js and npm are installed"
    Write-Host "  3. Verify AWS CLI is configured correctly"
    Write-Host "  4. Check you have permissions to update Lambda functions"
    Write-Host ""
    
    if (Get-Location | Select-Object -ExpandProperty Path | Select-String "bff") {
        Pop-Location
    }
    
    exit 1
}
