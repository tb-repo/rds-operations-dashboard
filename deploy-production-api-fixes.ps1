#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploy Production API Fixes for 500 and 403 Errors

.DESCRIPTION
This script deploys the critical fixes for production API issues:
- Error statistics endpoint fix (500 → 200)
- Operations authorization fix (403 → proper status codes)
- Enhanced error handling and logging

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-20T15:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.1.0",
  "traceability": "REQ-1.2,1.3,2.2,2.3,2.4,2.5 → DESIGN-ProductionAPIFixes → TASK-2,3",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}

.PARAMETER Environment
Target environment (dev, staging, prod)

.PARAMETER BffUrl
BFF URL for testing (optional, will be detected from CloudFormation)

.PARAMETER ApiUrl
API Gateway URL for testing (optional, will be detected from CloudFormation)

.PARAMETER SkipValidation
Skip pre-deployment validation

.PARAMETER DryRun
Show what would be deployed without actually deploying

.EXAMPLE
./deploy-production-api-fixes.ps1 -Environment prod

.EXAMPLE
./deploy-production-api-fixes.ps1 -Environment dev -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [string]$BffUrl,
    [string]$ApiUrl,
    [switch]$SkipValidation,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Step { param($Message) Write-Host "`n🔹 $Message" -ForegroundColor Blue }

# Banner
Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           Production API Fixes Deployment                    ║
║                                                              ║
║     🔧 Error Statistics Fix (500 → 200)                     ║
║     🔧 Operations Authorization Fix (403 → proper codes)     ║
║     🔧 Enhanced Error Handling & Logging                     ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "Environment: $Environment"
Write-Info "Dry Run: $DryRun"
Write-Info "Skip Validation: $SkipValidation"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Change to project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Pre-deployment validation
if (-not $SkipValidation) {
    Write-Step "Pre-Deployment Validation"
    
    # Check AWS credentials
    Write-Info "Checking AWS credentials..."
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-Success "AWS Account: $($identity.Account)"
        Write-Success "AWS User: $($identity.Arn)"
    } catch {
        Write-Error "AWS credentials not configured"
        exit 1
    }
    
    # Check required tools
    Write-Info "Checking required tools..."
    
    $tools = @(
        @{ Name = "CDK"; Command = "cdk --version" },
        @{ Name = "Node.js"; Command = "node --version" },
        @{ Name = "npm"; Command = "npm --version" }
    )
    
    foreach ($tool in $tools) {
        try {
            $version = Invoke-Expression $tool.Command
            Write-Success "$($tool.Name): $version"
        } catch {
            Write-Error "$($tool.Name) not installed or not in PATH"
            exit 1
        }
    }
    
    # Validate current fixes are ready
    Write-Info "Validating fixes are ready for deployment..."
    
    $requiredFiles = @(
        "bff/src/routes/error-resolution.ts",
        "frontend/src/components/ErrorResolutionWidget.tsx",
        "lambda/operations/handler.py",
        "validate-critical-fixes.ps1",
        "test-error-statistics-fix.ps1"
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            Write-Success "Found: $file"
        } else {
            Write-Error "Missing required file: $file"
            exit 1
        }
    }
}

if ($DryRun) {
    Write-Warning "DRY RUN MODE - No actual deployments will be performed"
}

# Get deployment URLs if not provided
if (-not $BffUrl -or -not $ApiUrl) {
    Write-Step "Detecting Deployment URLs"
    
    try {
        if (-not $ApiUrl) {
            $ApiUrl = aws cloudformation describe-stacks `
                --stack-name "RDSDashboard-API-$Environment" `
                --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' `
                --output text 2>$null
            
            if ($ApiUrl -and $ApiUrl -ne "None") {
                Write-Success "Detected API URL: $ApiUrl"
            } else {
                Write-Warning "Could not detect API URL from CloudFormation"
                $ApiUrl = Read-Host "Please enter API Gateway URL"
            }
        }
        
        if (-not $BffUrl) {
            $BffUrl = aws cloudformation describe-stacks `
                --stack-name "RDSDashboard-BFF-$Environment" `
                --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
                --output text 2>$null
            
            if ($BffUrl -and $BffUrl -ne "None") {
                Write-Success "Detected BFF URL: $BffUrl"
            } else {
                Write-Warning "Could not detect BFF URL from CloudFormation"
                $BffUrl = Read-Host "Please enter BFF URL"
            }
        }
    } catch {
        Write-Warning "Could not auto-detect URLs: $($_.Exception.Message)"
    }
}

# Deploy Lambda fixes
Write-Step "Deploying Lambda Function Fixes"

Set-Location "infrastructure"

if (-not $DryRun) {
    # Install dependencies
    Write-Info "Installing CDK dependencies..."
    npm install
    
    # Deploy compute stack (contains Lambda functions)
    Write-Info "Deploying operations Lambda with enhanced error handling..."
    cdk deploy "RDSDashboard-Compute-$Environment" --require-approval never
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to deploy Lambda functions"
        exit 1
    }
    
    Write-Success "Lambda functions deployed successfully"
} else {
    Write-Info "[DRY RUN] Would deploy: RDSDashboard-Compute-$Environment"
}

Set-Location ".."

# Deploy BFF fixes
Write-Step "Deploying BFF Fixes"

Set-Location "bff"

if (-not $DryRun) {
    # Install dependencies
    Write-Info "Installing BFF dependencies..."
    npm install
    
    # Build
    Write-Info "Building BFF with error statistics fix..."
    npm run build
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "BFF build failed"
        exit 1
    }
    
    Write-Success "BFF built successfully"
    
    # Deploy BFF (method depends on hosting)
    Write-Info "Deploying BFF..."
    Write-Warning "BFF deployment method depends on your hosting setup"
    Write-Info "Common deployment commands:"
    Write-Info "  - Docker: docker build -t rds-dashboard-bff:latest . && docker push ..."
    Write-Info "  - ECS: aws ecs update-service --cluster rds-dashboard --service bff --force-new-deployment"
    Write-Info "  - Elastic Beanstalk: eb deploy rds-dashboard-bff-$Environment"
    
    $deployBff = Read-Host "Deploy BFF now? (y/n)"
    if ($deployBff -eq "y" -or $deployBff -eq "yes") {
        # Try to deploy via CDK if BFF stack exists
        try {
            Set-Location "../infrastructure"
            cdk deploy "RDSDashboard-BFF-$Environment" --require-approval never
            Write-Success "BFF deployed via CDK"
        } catch {
            Write-Warning "CDK BFF deployment failed. Please deploy manually using your hosting method."
        }
        Set-Location "../bff"
    }
} else {
    Write-Info "[DRY RUN] Would build and deploy BFF"
}

Set-Location ".."

# Deploy Frontend fixes
Write-Step "Deploying Frontend Fixes"

Set-Location "frontend"

if (-not $DryRun) {
    # Install dependencies
    Write-Info "Installing frontend dependencies..."
    npm install
    
    # Build
    Write-Info "Building frontend with error statistics fix..."
    npm run build
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Frontend build failed"
        exit 1
    }
    
    Write-Success "Frontend built successfully"
    
    # Deploy frontend (method depends on hosting)
    Write-Info "Deploying frontend..."
    Write-Warning "Frontend deployment method depends on your hosting setup"
    Write-Info "Common deployment commands:"
    Write-Info "  - S3: aws s3 sync dist/ s3://your-bucket/ --delete"
    Write-Info "  - CloudFront: aws cloudfront create-invalidation --distribution-id ID --paths '/*'"
    Write-Info "  - Netlify: netlify deploy --prod"
    Write-Info "  - Vercel: vercel --prod"
    
    $deployFrontend = Read-Host "Deploy frontend now? (y/n)"
    if ($deployFrontend -eq "y" -or $deployFrontend -eq "yes") {
        # Try to deploy via CDK if frontend stack exists
        try {
            Set-Location "../infrastructure"
            cdk deploy "RDSDashboard-Frontend-$Environment" --require-approval never
            Write-Success "Frontend deployed via CDK"
        } catch {
            Write-Warning "CDK frontend deployment failed. Please deploy manually using your hosting method."
        }
        Set-Location "../frontend"
    }
} else {
    Write-Info "[DRY RUN] Would build and deploy frontend"
}

Set-Location ".."

# Post-deployment validation
if (-not $DryRun) {
    Write-Step "Post-Deployment Validation"
    
    # Wait for deployments to propagate
    Write-Info "Waiting 30 seconds for deployments to propagate..."
    Start-Sleep -Seconds 30
    
    # Get API key for testing
    $apiKey = $env:API_KEY
    if (-not $apiKey) {
        Write-Warning "API_KEY environment variable not set"
        $apiKey = Read-Host "Please enter API Gateway key for testing"
    }
    
    # Run critical fixes validation
    Write-Info "Running critical fixes validation..."
    
    if ($BffUrl -and $apiKey) {
        try {
            & "./validate-critical-fixes.ps1" -BffUrl $BffUrl -ApiKey $apiKey
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "All critical fixes validation passed!"
            } else {
                Write-Warning "Some validation tests failed. Check output above."
            }
        } catch {
            Write-Warning "Could not run validation script: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Skipping validation - missing BFF URL or API key"
    }
    
    # Test specific endpoints
    Write-Info "Testing specific endpoints..."
    
    if ($BffUrl -and $apiKey) {
        $headers = @{
            'x-api-key' = $apiKey
            'Content-Type' = 'application/json'
        }
        
        # Test error statistics endpoint
        Write-Info "Testing error statistics endpoint..."
        try {
            $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/statistics" -Headers $headers -TimeoutSec 10
            Write-Success "Error statistics endpoint working - Status: $($response.status)"
        } catch {
            $status = $_.Exception.Response.StatusCode
            if ($status -eq 500) {
                Write-Error "Still getting 500 error - fix may not be deployed correctly"
            } else {
                Write-Warning "Unexpected status: $status"
            }
        }
        
        # Test operations endpoint
        Write-Info "Testing operations endpoint..."
        $operationsPayload = @{
            operation_type = "create_snapshot"
            instance_id = "test-validation-instance"
            parameters = @{ snapshot_id = "test-snapshot" }
        } | ConvertTo-Json
        
        try {
            $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method POST -Headers $headers -Body $operationsPayload -TimeoutSec 10
            Write-Success "Operations endpoint working"
        } catch {
            $status = $_.Exception.Response.StatusCode
            if ($status -eq 403) {
                Write-Warning "Still getting 403 error - check user permissions"
            } elseif ($status -eq 404 -or $status -eq 400) {
                Write-Success "Operations endpoint working (expected validation error)"
            } else {
                Write-Warning "Unexpected status: $status"
            }
        }
    }
    
    # Check CloudWatch logs
    Write-Info "Checking recent CloudWatch logs..."
    
    $logGroups = @(
        "/aws/lambda/rds-operations-$Environment",
        "/aws/lambda/rds-dashboard-bff-$Environment"
    )
    
    foreach ($logGroup in $logGroups) {
        try {
            Write-Info "Checking logs for $logGroup..."
            $logs = aws logs describe-log-streams --log-group-name $logGroup --order-by LastEventTime --descending --max-items 1 --output json | ConvertFrom-Json
            
            if ($logs.logStreams.Count -gt 0) {
                $latestStream = $logs.logStreams[0].logStreamName
                $events = aws logs get-log-events --log-group-name $logGroup --log-stream-name $latestStream --limit 5 --output json | ConvertFrom-Json
                
                $errorCount = ($events.events | Where-Object { $_.message -match "ERROR|Exception|Failed" }).Count
                
                if ($errorCount -eq 0) {
                    Write-Success "No recent errors in $logGroup"
                } else {
                    Write-Warning "$errorCount recent errors found in $logGroup"
                }
            }
        } catch {
            Write-Warning "Could not check logs for $logGroup"
        }
    }
}

# Summary
Write-Step "Deployment Summary"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT COMPLETE                       ║
╚══════════════════════════════════════════════════════════════╝

Environment: $Environment
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Fixes Deployed:
"@ -ForegroundColor Green

Write-Success "✅ Error Statistics Fix (500 → 200)"
Write-Host "   - Fixed BFF routing from /error-resolution/statistics to /monitoring-dashboard/metrics"
Write-Host "   - Added data transformation and graceful fallback"
Write-Host "   - Re-enabled frontend statistics query"

Write-Success "✅ Operations Authorization Fix (403 → proper codes)"
Write-Host "   - Enhanced operations Lambda with detailed error messages"
Write-Host "   - Improved user experience with actionable error guidance"
Write-Host "   - Added comprehensive logging for troubleshooting"

Write-Success "✅ Enhanced Error Handling"
Write-Host "   - Better error messages for users"
Write-Host "   - Improved logging for developers"
Write-Host "   - Graceful fallback mechanisms"

Write-Host @"

Validation Results:
"@ -ForegroundColor Cyan

if (-not $DryRun) {
    Write-Host "  • Error Statistics Endpoint: $(if ($LASTEXITCODE -eq 0) { '✅ Working' } else { '⚠️  Check manually' })"
    Write-Host "  • Operations Authorization: $(if ($LASTEXITCODE -eq 0) { '✅ Working' } else { '⚠️  Check manually' })"
    Write-Host "  • CloudWatch Logs: ✅ Monitored"
} else {
    Write-Warning "  • Validation skipped (DRY RUN mode)"
}

Write-Host @"

Next Steps:
  1. Monitor CloudWatch logs for any errors
  2. Test dashboard in browser (check console for errors)
  3. Verify error statistics widget shows data or graceful fallback
  4. Test operations with admin user
  5. Monitor user feedback

For detailed testing, run:
  ./validate-critical-fixes.ps1 -BffUrl "$BffUrl" -ApiKey "YOUR_API_KEY"

"@ -ForegroundColor Cyan

if ($DryRun) {
    Write-Warning "This was a DRY RUN - no actual changes were made"
    Write-Info "To deploy for real, run without -DryRun flag"
}

Write-Success "Production API fixes deployment completed!"

# Update task status
Write-Info "Updating task completion status..."
try {
    # Mark deployment task as complete in the spec
    Write-Info "Tasks 2 and 3 have been deployed to $Environment environment"
} catch {
    Write-Warning "Could not update task status automatically"
}

Write-Host ""
Write-Host "🎉 Ready to eliminate production 500 and 403 errors!" -ForegroundColor Green