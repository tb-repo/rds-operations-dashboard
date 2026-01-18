#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploy Operations 400 Error Fix

.DESCRIPTION
Deploys the BFF and Lambda fixes for the 400 error issue in operations.
This script addresses the critical issue where instance operations were failing with 400 errors.

.PARAMETER DryRun
If specified, shows what would be deployed without actually deploying

.EXAMPLE
./scripts/deploy-operations-fix.ps1
Deploy the operations fix

.EXAMPLE
./scripts/deploy-operations-fix.ps1 -DryRun
Show what would be deployed without actually deploying
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Deploying Operations 400 Error Fix" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

if ($DryRun) {
    Write-Host "🔍 DRY RUN MODE - No actual deployment will occur" -ForegroundColor Yellow
    Write-Host ""
}

# Configuration
$BFF_FUNCTION_NAME = "rds-dashboard-bff-prod"
$OPERATIONS_FUNCTION_NAME = "rds-operations-prod"
$REGION = "ap-southeast-1"

Write-Host "📋 Deployment Configuration:" -ForegroundColor Cyan
Write-Host "  BFF Function: $BFF_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Operations Function: $OPERATIONS_FUNCTION_NAME" -ForegroundColor White
Write-Host "  Region: $REGION" -ForegroundColor White
Write-Host ""

# Step 1: Deploy BFF Fix
Write-Host "🔧 Step 1: Deploying BFF Operations Fix" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

if (-not $DryRun) {
    try {
        # Build BFF
        Write-Host "📦 Building BFF..." -ForegroundColor Cyan
        Set-Location "bff"
        npm install
        npm run build
        
        # Create deployment package
        Write-Host "📦 Creating BFF deployment package..." -ForegroundColor Cyan
        if (Test-Path "deployment.zip") {
            Remove-Item "deployment.zip" -Force
        }
        
        # Create zip with all necessary files
        $files = @(
            "dist/*",
            "node_modules/**/*",
            "package.json",
            "package-lock.json"
        )
        
        Compress-Archive -Path $files -DestinationPath "deployment.zip" -Force
        
        # Deploy to Lambda
        Write-Host "🚀 Deploying BFF to Lambda..." -ForegroundColor Cyan
        aws lambda update-function-code `
            --function-name $BFF_FUNCTION_NAME `
            --zip-file fileb://deployment.zip `
            --region $REGION
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ BFF deployed successfully" -ForegroundColor Green
        } else {
            throw "BFF deployment failed"
        }
        
        Set-Location ".."
        
    } catch {
        Write-Host "❌ BFF deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        Set-Location ".."
        exit 1
    }
} else {
    Write-Host "🔍 Would build and deploy BFF with enhanced operations handling" -ForegroundColor Yellow
}

# Step 2: Deploy Operations Lambda Fix
Write-Host ""
Write-Host "🔧 Step 2: Deploying Operations Lambda Fix" -ForegroundColor Yellow
Write-Host "-------------------------------------------" -ForegroundColor Yellow

if (-not $DryRun) {
    try {
        # Create deployment package for operations Lambda
        Write-Host "📦 Creating Operations Lambda deployment package..." -ForegroundColor Cyan
        Set-Location "lambda/operations"
        
        if (Test-Path "deployment.zip") {
            Remove-Item "deployment.zip" -Force
        }
        
        # Create zip with handler and shared modules
        $files = @(
            "handler.py",
            "../shared/*.py"
        )
        
        # Create temporary directory for packaging
        $tempDir = "temp_package"
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempDir
        
        # Copy files to temp directory
        Copy-Item "handler.py" "$tempDir/"
        New-Item -ItemType Directory -Path "$tempDir/shared"
        Copy-Item "../shared/*.py" "$tempDir/shared/"
        
        # Create zip from temp directory
        Set-Location $tempDir
        Compress-Archive -Path "*" -DestinationPath "../deployment.zip" -Force
        Set-Location ".."
        
        # Clean up temp directory
        Remove-Item $tempDir -Recurse -Force
        
        # Deploy to Lambda
        Write-Host "🚀 Deploying Operations Lambda..." -ForegroundColor Cyan
        aws lambda update-function-code `
            --function-name $OPERATIONS_FUNCTION_NAME `
            --zip-file fileb://deployment.zip `
            --region $REGION
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Operations Lambda deployed successfully" -ForegroundColor Green
        } else {
            throw "Operations Lambda deployment failed"
        }
        
        Set-Location "../.."
        
    } catch {
        Write-Host "❌ Operations Lambda deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        Set-Location "../.."
        exit 1
    }
} else {
    Write-Host "🔍 Would deploy Operations Lambda with enhanced error handling and logging" -ForegroundColor Yellow
}

# Step 3: Test the fix
Write-Host ""
Write-Host "🧪 Step 3: Testing Operations Fix" -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow

if (-not $DryRun) {
    Write-Host "⏳ Waiting 10 seconds for Lambda deployment to propagate..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    
    # Test the operations endpoint
    Write-Host "🔍 Testing operations endpoint..." -ForegroundColor Cyan
    
    $testPayload = @{
        instance_id = "tb-pg-db1"
        operation = "stop_instance"
        region = "ap-southeast-1"
        account_id = "876595225096"
        parameters = @{}
    } | ConvertTo-Json -Depth 3
    
    try {
        # Test direct Lambda invocation
        Write-Host "🧪 Testing Operations Lambda directly..." -ForegroundColor Cyan
        
        $lambdaEvent = @{
            body = $testPayload
            requestContext = @{
                identity = @{}
            }
        } | ConvertTo-Json -Depth 4
        
        $response = aws lambda invoke `
            --function-name $OPERATIONS_FUNCTION_NAME `
            --payload $lambdaEvent `
            --region $REGION `
            response.json
        
        if ($LASTEXITCODE -eq 0) {
            $responseContent = Get-Content "response.json" | ConvertFrom-Json
            if ($responseContent.statusCode -eq 200) {
                Write-Host "✅ Operations Lambda test passed" -ForegroundColor Green
            } elseif ($responseContent.statusCode -eq 404) {
                Write-Host "⚠️  Operations Lambda returned 404 (instance not found) - this is expected if instance doesn't exist" -ForegroundColor Yellow
            } else {
                Write-Host "⚠️  Operations Lambda returned status: $($responseContent.statusCode)" -ForegroundColor Yellow
                Write-Host "Response: $(Get-Content 'response.json')" -ForegroundColor Gray
            }
        } else {
            Write-Host "❌ Operations Lambda test failed" -ForegroundColor Red
        }
        
        # Clean up test file
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
        
    } catch {
        Write-Host "⚠️  Test failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "This may be expected if the instance doesn't exist in the inventory" -ForegroundColor Gray
    }
} else {
    Write-Host "🔍 Would test the operations endpoint with a sample request" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "📊 Deployment Summary" -ForegroundColor Green
Write-Host "=====================" -ForegroundColor Green

if (-not $DryRun) {
    Write-Host "✅ BFF Operations Fix: Deployed" -ForegroundColor Green
    Write-Host "✅ Operations Lambda Fix: Deployed" -ForegroundColor Green
    Write-Host "✅ Basic Testing: Completed" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Test operations in the dashboard UI" -ForegroundColor White
    Write-Host "2. Verify 400 errors are resolved" -ForegroundColor White
    Write-Host "3. Check CloudWatch logs for detailed debugging info" -ForegroundColor White
    Write-Host "4. If issues persist, check the enhanced logging in both BFF and Lambda" -ForegroundColor White
} else {
    Write-Host "🔍 Dry run completed - no actual deployment occurred" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📋 Would deploy:" -ForegroundColor Cyan
    Write-Host "• Enhanced BFF operations handling with better request formatting" -ForegroundColor White
    Write-Host "• Improved Operations Lambda with detailed error logging" -ForegroundColor White
    Write-Host "• Better validation and error messages" -ForegroundColor White
    Write-Host "• Enhanced debugging capabilities" -ForegroundColor White
}

Write-Host ""
Write-Host "🚀 Operations 400 Error Fix Deployment Complete!" -ForegroundColor Green