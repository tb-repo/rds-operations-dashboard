#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploy BFF to Lambda - Direct approach avoiding path length issues

.DESCRIPTION
Deploys the BFF using existing zip or creates one in a short path location
#>

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== BFF Lambda Deployment (Direct Method) ===" -ForegroundColor Cyan

# Option 1: Check if we have a recent bff.zip
$existingZip = "bff.zip"
if (Test-Path $existingZip) {
    $zipAge = (Get-Date) - (Get-Item $existingZip).LastWriteTime
    if ($zipAge.TotalHours -lt 24) {
        Write-Host "Found recent deployment package: $existingZip" -ForegroundColor Green
        Write-Host "Package age: $([math]::Round($zipAge.TotalHours, 1)) hours" -ForegroundColor Cyan
        
        $useExisting = Read-Host "Use existing package? (Y/n)"
        if ($useExisting -ne 'n' -and $useExisting -ne 'N') {
            Write-Host "Using existing package..." -ForegroundColor Yellow
            
            # Deploy to Lambda
            Write-Host "Deploying to Lambda function: $FunctionName..." -ForegroundColor Yellow
            try {
                $result = aws lambda update-function-code `
                    --function-name $FunctionName `
                    --zip-file "fileb://$existingZip" `
                    --region $Region `
                    --output json | ConvertFrom-Json
                
                Write-Host "Deployment successful!" -ForegroundColor Green
                Write-Host "Function: $($result.FunctionName)" -ForegroundColor Cyan
                Write-Host "Runtime: $($result.Runtime)" -ForegroundColor Cyan
                Write-Host "Last Modified: $($result.LastModified)" -ForegroundColor Cyan
                Write-Host "Code Size: $([math]::Round($result.CodeSize / 1MB, 2)) MB" -ForegroundColor Cyan
                
                Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
                exit 0
                
            } catch {
                Write-Error "Deployment failed: $($_.Exception.Message)"
                exit 1
            }
        }
    }
}

# Option 2: Create new package in temp directory with short path
Write-Host "Creating new deployment package..." -ForegroundColor Yellow

# Use Windows temp directory for shorter path
$tempBase = $env:TEMP
$deployDir = Join-Path $tempBase "bff-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
$zipPath = Join-Path $tempBase "bff-deployment.zip"

Write-Host "Using temp directory: $deployDir" -ForegroundColor Cyan

try {
    # Create temp directory
    New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
    
    # Copy dist folder
    Write-Host "Copying built files..." -ForegroundColor Yellow
    if (-not (Test-Path "dist")) {
        Write-Error "dist folder not found. Run 'npm run build' first."
        exit 1
    }
    Copy-Item "dist\*" $deployDir -Recurse -Force
    
    # Copy package files
    Write-Host "Copying package files..." -ForegroundColor Yellow
    Copy-Item "package.json" $deployDir -Force
    if (Test-Path "package-lock.json") {
        Copy-Item "package-lock.json" $deployDir -Force
    }
    
    # Install production dependencies
    Write-Host "Installing production dependencies..." -ForegroundColor Yellow
    Push-Location $deployDir
    npm install --production --no-audit --no-fund 2>&1 | Out-Null
    Pop-Location
    
    # Create zip file
    Write-Host "Creating deployment zip..." -ForegroundColor Yellow
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # Use PowerShell compression
    Compress-Archive -Path "$deployDir\*" -DestinationPath $zipPath -Force
    
    # Get zip file size
    $zipSize = (Get-Item $zipPath).Length / 1MB
    Write-Host "Deployment package size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan
    
    # Deploy to Lambda
    Write-Host "Deploying to Lambda function: $FunctionName..." -ForegroundColor Yellow
    $result = aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file "fileb://$zipPath" `
        --region $Region `
        --output json | ConvertFrom-Json
    
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host "Function: $($result.FunctionName)" -ForegroundColor Cyan
    Write-Host "Runtime: $($result.Runtime)" -ForegroundColor Cyan
    Write-Host "Last Modified: $($result.LastModified)" -ForegroundColor Cyan
    Write-Host "Code Size: $([math]::Round($result.CodeSize / 1MB, 2)) MB" -ForegroundColor Cyan
    
    # Copy zip to current directory for future use
    Write-Host "Saving deployment package..." -ForegroundColor Yellow
    Copy-Item $zipPath "bff-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip" -Force
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
} finally {
    # Cleanup
    Write-Host "Cleaning up..." -ForegroundColor Yellow
    if (Test-Path $deployDir) {
        Remove-Item $deployDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Test the API Gateway endpoints" -ForegroundColor White
Write-Host "2. Check CloudWatch logs: aws logs tail /aws/lambda/$FunctionName --follow" -ForegroundColor White
Write-Host "3. Run validation: ../scripts/validate-bff-deployment.ps1" -ForegroundColor White
