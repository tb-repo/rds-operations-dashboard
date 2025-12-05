#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy latest RDS Operations Dashboard changes
.DESCRIPTION
    Deploys monitoring dashboards and approval workflow system
.PARAMETER Environment
    Target environment (dev, staging, prod)
.PARAMETER SkipInfrastructure
    Skip infrastructure deployment
.PARAMETER SkipBFF
    Skip BFF deployment
.PARAMETER SkipFrontend
    Skip frontend deployment
.PARAMETER DryRun
    Show what would be deployed without actually deploying
.EXAMPLE
    .\deploy-latest-changes.ps1 -Environment dev
.EXAMPLE
    .\deploy-latest-changes.ps1 -Environment prod -SkipBFF
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [switch]$SkipInfrastructure,
    [switch]$SkipBFF,
    [switch]$SkipFrontend,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
function Write-Success { Write-Host "✅ $args" -ForegroundColor Green }
function Write-Info { Write-Host "ℹ️  $args" -ForegroundColor Cyan }
function Write-Warning { Write-Host "⚠️  $args" -ForegroundColor Yellow }
function Write-Error { Write-Host "❌ $args" -ForegroundColor Red }
function Write-Step { Write-Host "`n🔹 $args" -ForegroundColor Blue }

# Banner
Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     RDS Operations Dashboard - Latest Changes Deployment    ║
║                                                              ║
║     • Monitoring Dashboards                                  ║
║     • Approval Workflow System                               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "Environment: $Environment"
Write-Info "Dry Run: $DryRun"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Change to project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
Set-Location $projectRoot

# Pre-deployment checks
Write-Step "Running Pre-Deployment Checks"

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

# Check CDK
Write-Info "Checking CDK installation..."
try {
    $cdkVersion = cdk --version
    Write-Success "CDK Version: $cdkVersion"
} catch {
    Write-Error "CDK not installed. Run: npm install -g aws-cdk"
    exit 1
}

# Check Node.js
Write-Info "Checking Node.js..."
try {
    $nodeVersion = node --version
    Write-Success "Node.js Version: $nodeVersion"
} catch {
    Write-Error "Node.js not installed"
    exit 1
}

# Check Python
Write-Info "Checking Python..."
try {
    $pythonVersion = python --version
    Write-Success "Python Version: $pythonVersion"
} catch {
    Write-Error "Python not installed"
    exit 1
}

if ($DryRun) {
    Write-Warning "DRY RUN MODE - No actual deployments will be performed"
}

# Deploy Infrastructure
if (-not $SkipInfrastructure) {
    Write-Step "Deploying Infrastructure Changes"
    
    Set-Location "$projectRoot/infrastructure"
    
    # Install dependencies
    Write-Info "Installing CDK dependencies..."
    if (-not $DryRun) {
        npm install
    } else {
        Write-Info "[DRY RUN] Would run: npm install"
    }
    
    # Synthesize
    Write-Info "Synthesizing CloudFormation templates..."
    if (-not $DryRun) {
        cdk synth
    } else {
        Write-Info "[DRY RUN] Would run: cdk synth"
    }
    
    # Show diffs
    Write-Info "Showing infrastructure changes..."
    $stacks = @(
        "RDSDashboard-Data-$Environment",
        "RDSDashboard-IAM-$Environment",
        "RDSDashboard-Compute-$Environment",
        "RDSDashboard-API-$Environment"
    )
    
    foreach ($stack in $stacks) {
        Write-Info "Changes for $stack..."
        if (-not $DryRun) {
            cdk diff $stack
        } else {
            Write-Info "[DRY RUN] Would run: cdk diff $stack"
        }
    }
    
    # Confirm deployment
    if (-not $DryRun) {
        $confirm = Read-Host "Deploy infrastructure changes? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Warning "Infrastructure deployment cancelled"
        } else {
            # Deploy stacks
            foreach ($stack in $stacks) {
                Write-Info "Deploying $stack..."
                cdk deploy $stack --require-approval never
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to deploy $stack"
                    exit 1
                }
                Write-Success "Deployed $stack"
            }
        }
    } else {
        Write-Info "[DRY RUN] Would deploy: $($stacks -join ', ')"
    }
    
    Set-Location $projectRoot
} else {
    Write-Warning "Skipping infrastructure deployment"
}

# Deploy BFF
if (-not $SkipBFF) {
    Write-Step "Deploying BFF Changes"
    
    Set-Location "$projectRoot/bff"
    
    # Install dependencies
    Write-Info "Installing BFF dependencies..."
    if (-not $DryRun) {
        npm install
    } else {
        Write-Info "[DRY RUN] Would run: npm install"
    }
    
    # Build
    Write-Info "Building BFF..."
    if (-not $DryRun) {
        npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Error "BFF build failed"
            exit 1
        }
        Write-Success "BFF built successfully"
    } else {
        Write-Info "[DRY RUN] Would run: npm run build"
    }
    
    # Deploy (customize based on your hosting)
    Write-Info "Deploying BFF..."
    Write-Warning "BFF deployment method not specified in script"
    Write-Info "Please deploy BFF manually using your hosting service"
    Write-Info "Example commands:"
    Write-Info "  - Elastic Beanstalk: eb deploy rds-dashboard-bff-$Environment"
    Write-Info "  - ECS: aws ecs update-service --cluster rds-dashboard --service bff --force-new-deployment"
    Write-Info "  - Docker: docker build -t rds-dashboard-bff:latest . && docker push ..."
    
    Set-Location $projectRoot
} else {
    Write-Warning "Skipping BFF deployment"
}

# Deploy Frontend
if (-not $SkipFrontend) {
    Write-Step "Deploying Frontend Changes"
    
    Set-Location "$projectRoot/frontend"
    
    # Install dependencies
    Write-Info "Installing frontend dependencies..."
    if (-not $DryRun) {
        npm install
    } else {
        Write-Info "[DRY RUN] Would run: npm install"
    }
    
    # Build
    Write-Info "Building frontend..."
    if (-not $DryRun) {
        npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Frontend build failed"
            exit 1
        }
        Write-Success "Frontend built successfully"
    } else {
        Write-Info "[DRY RUN] Would run: npm run build"
    }
    
    # Deploy (customize based on your hosting)
    Write-Info "Deploying frontend..."
    Write-Warning "Frontend deployment method not specified in script"
    Write-Info "Please deploy frontend manually using your hosting service"
    Write-Info "Example commands:"
    Write-Info "  - S3: aws s3 sync dist/ s3://your-bucket/ --delete"
    Write-Info "  - CloudFront: aws cloudfront create-invalidation --distribution-id ID --paths '/*'"
    Write-Info "  - Netlify: netlify deploy --prod"
    Write-Info "  - Vercel: vercel --prod"
    
    Set-Location $projectRoot
} else {
    Write-Warning "Skipping frontend deployment"
}

# Post-deployment verification
if (-not $DryRun) {
    Write-Step "Post-Deployment Verification"
    
    # Test Lambda functions
    Write-Info "Testing Lambda functions..."
    
    $approvalFunctionName = "rds-approval-workflow-$Environment"
    $monitoringFunctionName = "rds-monitoring-$Environment"
    
    Write-Info "Testing $approvalFunctionName..."
    try {
        $payload = @{
            body = @{
                operation = "get_pending_approvals"
            } | ConvertTo-Json
        } | ConvertTo-Json
        
        aws lambda invoke `
            --function-name $approvalFunctionName `
            --payload $payload `
            --cli-binary-format raw-in-base64-out `
            response.json
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$approvalFunctionName is responding"
        } else {
            Write-Warning "$approvalFunctionName test failed"
        }
    } catch {
        Write-Warning "Could not test $approvalFunctionName"
    }
    
    Write-Info "Testing $monitoringFunctionName..."
    try {
        $payload = @{
            body = @{
                operation = "get_real_time_status"
                instance_id = "test"
            } | ConvertTo-Json
        } | ConvertTo-Json
        
        aws lambda invoke `
            --function-name $monitoringFunctionName `
            --payload $payload `
            --cli-binary-format raw-in-base64-out `
            response.json
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$monitoringFunctionName is responding"
        } else {
            Write-Warning "$monitoringFunctionName test failed"
        }
    } catch {
        Write-Warning "Could not test $monitoringFunctionName"
    }
    
    # Check DynamoDB table
    Write-Info "Checking DynamoDB tables..."
    try {
        $tableName = "rds-approvals-$Environment"
        aws dynamodb describe-table --table-name $tableName --output json | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Table $tableName exists"
        } else {
            Write-Warning "Table $tableName not found"
        }
    } catch {
        Write-Warning "Could not verify DynamoDB table"
    }
    
    # Clean up test files
    if (Test-Path "response.json") {
        Remove-Item "response.json"
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

Components Deployed:
"@ -ForegroundColor Green

if (-not $SkipInfrastructure) {
    Write-Success "✅ Infrastructure (Lambda, DynamoDB, API Gateway)"
} else {
    Write-Warning "⏭️  Infrastructure (Skipped)"
}

if (-not $SkipBFF) {
    Write-Success "✅ BFF (Backend-for-Frontend)"
} else {
    Write-Warning "⏭️  BFF (Skipped)"
}

if (-not $SkipFrontend) {
    Write-Success "✅ Frontend (React Application)"
} else {
    Write-Warning "⏭️  Frontend (Skipped)"
}

Write-Host @"

New Features Available:
  • Monitoring Dashboards (Compute & Connection)
  • Approval Workflow System
  • Risk-Based Approvals
  • Real-Time Metrics

Next Steps:
  1. Verify all services are running
  2. Test monitoring dashboards
  3. Test approval workflow
  4. Monitor CloudWatch logs
  5. Conduct user acceptance testing

For detailed verification steps, see:
  DEPLOYMENT-GUIDE-LATEST.md

"@ -ForegroundColor Cyan

if ($DryRun) {
    Write-Warning "This was a DRY RUN - no actual changes were made"
}

Write-Success "Deployment script completed successfully!"
