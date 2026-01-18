#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploy BFF to Production Lambda

.DESCRIPTION
Builds and deploys the BFF to AWS Lambda with all dependencies and proper configuration.
This script handles the complete build and deployment process.

.PARAMETER FunctionName
The Lambda function name (default: rds-dashboard-bff-prod)

.PARAMETER Region
AWS region (default: ap-southeast-1)

.PARAMETER SkipBuild
Skip the build step if dist is already up to date

.EXAMPLE
./deploy-bff-production.ps1
./deploy-bff-production.ps1 -FunctionName my-bff -Region us-east-1
./deploy-bff-production.ps1 -SkipBuild
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "=== BFF Production Deployment ===" -ForegroundColor Cyan
Write-Host "Function: $FunctionName" -ForegroundColor White
Write-Host "Region: $Region" -ForegroundColor White
Write-Host ""

# Navigate to BFF directory
$bffPath = Join-Path (Join-Path $PSScriptRoot "..") "bff"
Push-Location $bffPath

try {
    # Step 1: Build TypeScript
    if (-not $SkipBuild) {
        Write-Host "[1/6] Building TypeScript..." -ForegroundColor Yellow
        npm run build
        if ($LASTEXITCODE -ne 0) {
            throw "TypeScript build failed"
        }
        Write-Host "Build successful" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[1/6] Skipping build (using existing dist)" -ForegroundColor Yellow
        Write-Host ""
    }

    # Step 2: Clean previous deployment artifacts
    Write-Host "[2/6] Cleaning previous deployment artifacts..." -ForegroundColor Yellow
    if (Test-Path "lambda-package") {
        Remove-Item "lambda-package" -Recurse -Force
    }
    if (Test-Path "deployment.zip") {
        Remove-Item "deployment.zip" -Force
    }
    Write-Host "Cleanup complete" -ForegroundColor Green
    Write-Host ""

    # Step 3: Create deployment package directory
    Write-Host "[3/6] Creating deployment package..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "lambda-package" -Force | Out-Null

    # Copy built files
    Copy-Item "dist/*" "lambda-package/" -Recurse -Force
    Write-Host "  Copied compiled code" -ForegroundColor Gray

    # Copy package files
    Copy-Item "package.json" "lambda-package/" -Force
    if (Test-Path "package-lock.json") {
        Copy-Item "package-lock.json" "lambda-package/" -Force
    }
    Write-Host "  Copied package files" -ForegroundColor Gray
    Write-Host ""

    # Step 4: Install production dependencies
    Write-Host "[4/6] Installing production dependencies..." -ForegroundColor Yellow
    Push-Location "lambda-package"
    try {
        npm install --production --no-audit --no-fund --loglevel=error
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed"
        }
        Write-Host "Dependencies installed" -ForegroundColor Green
    } finally {
        Pop-Location
    }
    Write-Host ""

    # Step 5: Create deployment zip
    Write-Host "[5/6] Creating deployment zip..." -ForegroundColor Yellow
    Compress-Archive -Path "lambda-package/*" -DestinationPath "deployment.zip" -Force

    $zipSize = (Get-Item "deployment.zip").Length / 1MB
    Write-Host "Deployment package created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    
    if ($zipSize -gt 50) {
        Write-Warning "Package size is large ($([math]::Round($zipSize, 2)) MB). Consider optimizing dependencies."
    }
    Write-Host ""

    # Step 6: Deploy to Lambda
    Write-Host "[6/6] Deploying to Lambda..." -ForegroundColor Yellow
    
    $deployResult = aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://deployment.zip `
        --region $Region `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Lambda deployment failed: $deployResult"
        throw "Deployment failed"
    }

    $result = $deployResult | ConvertFrom-Json
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Deployment Details:" -ForegroundColor Cyan
    Write-Host "  Function: $($result.FunctionName)" -ForegroundColor White
    Write-Host "  Runtime: $($result.Runtime)" -ForegroundColor White
    Write-Host "  Handler: $($result.Handler)" -ForegroundColor White
    Write-Host "  Code Size: $([math]::Round($result.CodeSize / 1MB, 2)) MB" -ForegroundColor White
    Write-Host "  Last Modified: $($result.LastModified)" -ForegroundColor White
    Write-Host ""

    # Wait for function to be ready
    Write-Host "Waiting for function to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5

    # Test health endpoint
    Write-Host "Testing health endpoint..." -ForegroundColor Yellow
    $testPayload = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{}
    } | ConvertTo-Json -Compress

    $testResult = aws lambda invoke `
        --function-name $FunctionName `
        --payload $testPayload `
        --region $Region `
        response.json 2>&1

    if (Test-Path "response.json") {
        $response = Get-Content "response.json" -Raw | ConvertFrom-Json
        if ($response.statusCode -eq 200) {
            Write-Host "Health check passed" -ForegroundColor Green
        } else {
            Write-Warning "Health check returned status: $($response.statusCode)"
        }
        Remove-Item "response.json" -Force
    }
    Write-Host ""

    # Cleanup deployment artifacts
    Write-Host "Cleaning up deployment artifacts..." -ForegroundColor Yellow
    Remove-Item "lambda-package" -Recurse -Force -ErrorAction SilentlyContinue
    # Keep deployment.zip for rollback if needed
    Write-Host "Cleanup complete (deployment.zip kept for rollback)" -ForegroundColor Green
    Write-Host ""

    Write-Host "=== Deployment Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Test API Gateway endpoints" -ForegroundColor White
    Write-Host "  2. Check CloudWatch logs: aws logs tail /aws/lambda/$FunctionName --follow" -ForegroundColor White
    Write-Host "  3. Run validation: ./scripts/validate-critical-fixes.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Rollback Command (if needed):" -ForegroundColor Yellow
    Write-Host "  aws lambda update-function-code --function-name $FunctionName --zip-file fileb://deployment.zip --region $Region" -ForegroundColor Gray
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "=== Deployment Failed ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check AWS credentials: aws sts get-caller-identity" -ForegroundColor White
    Write-Host "  2. Verify Lambda function exists: aws lambda get-function --function-name $FunctionName --region $Region" -ForegroundColor White
    Write-Host "  3. Check build output: npm run build" -ForegroundColor White
    Write-Host "  4. Review error message above for specific issues" -ForegroundColor White
    Write-Host ""
    
    Pop-Location
    exit 1
} finally {
    Pop-Location
}
