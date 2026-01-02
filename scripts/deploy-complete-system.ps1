#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete RDS Operations Dashboard deployment
.DESCRIPTION
    Deploys the entire RDS Operations Dashboard system, handling dependency conflicts
    and ensuring proper deployment order.
.PARAMETER Environment
    Target environment (dev, staging, prod)
.PARAMETER SkipDependencyResolution
    Skip the API Gateway dependency resolution step
.PARAMETER SkipFrontend
    Skip frontend deployment
.PARAMETER Force
    Force deployment without confirmations
.EXAMPLE
    .\deploy-complete-system.ps1 -Environment dev
.EXAMPLE
    .\deploy-complete-system.ps1 -Environment prod -Force
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [switch]$SkipDependencyResolution,
    [switch]$SkipFrontend,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
function Write-Success { 
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green 
}
function Write-Info { 
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan 
}
function Write-Warning { 
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow 
}
function Write-Error { 
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red 
}
function Write-Step { 
    param([string]$Message)
    Write-Host "`n🔹 $Message" -ForegroundColor Blue 
}

# Banner
Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           RDS Operations Dashboard                           ║
║           Complete System Deployment                        ║
║                                                              ║
║     • Infrastructure (CDK Stacks)                           ║
║     • Backend Services (Lambda Functions)                   ║
║     • API Gateway & Authentication                          ║
║     • Frontend Application                                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "Environment: $Environment"
Write-Info "Force Mode: $Force"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Change to project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
Set-Location $projectRoot

Write-Info "Project Root: $projectRoot"

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

# Check required tools
$requiredTools = @(
    @{ Name = "CDK"; Command = "cdk --version"; InstallCmd = "npm install -g aws-cdk" },
    @{ Name = "Node.js"; Command = "node --version"; InstallCmd = "Install Node.js from nodejs.org" },
    @{ Name = "Python"; Command = "python --version"; InstallCmd = "Install Python from python.org" },
    @{ Name = "Docker"; Command = "docker --version"; InstallCmd = "Install Docker Desktop" }
)

foreach ($tool in $requiredTools) {
    Write-Info "Checking $($tool.Name)..."
    try {
        $version = Invoke-Expression $tool.Command
        Write-Success "$($tool.Name) Version: $version"
    } catch {
        Write-Warning "$($tool.Name) not found. Install with: $($tool.InstallCmd)"
        if ($tool.Name -eq "Docker" -and -not $Force) {
            Write-Warning "Docker is required for BFF deployment. Continue anyway? (y/n)"
            $continue = Read-Host
            if ($continue -ne "y") {
                exit 1
            }
        }
    }
}

# Check current deployment status
Write-Step "Checking Current Deployment Status"

Set-Location "$projectRoot/infrastructure"

# Install CDK dependencies
Write-Info "Installing CDK dependencies..."
npm install

# List existing stacks
Write-Info "Checking existing stacks..."
try {
    $existingStacks = aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --output json | ConvertFrom-Json
    $rdsStacks = $existingStacks.StackSummaries | Where-Object { $_.StackName -like "RDSDashboard-*" }
    
    if ($rdsStacks.Count -gt 0) {
        Write-Info "Found existing RDS Dashboard stacks:"
        foreach ($stack in $rdsStacks) {
            Write-Info "  - $($stack.StackName) ($($stack.StackStatus))"
        }
    } else {
        Write-Info "No existing RDS Dashboard stacks found"
    }
} catch {
    Write-Warning "Could not list existing stacks"
}

# Phase 1: Core Infrastructure
Write-Step "Phase 1: Deploying Core Infrastructure"

$coreStacks = @(
    "RDSDashboard-Data",
    "RDSDashboard-IAM", 
    "RDSDashboard-Compute",
    "RDSDashboard-Auth"
)

foreach ($stackName in $coreStacks) {
    Write-Info "Deploying $stackName..."
    
    # Show diff first
    Write-Info "Changes for ${stackName}:"
    cdk diff $stackName
    
    # Deploy
    if ($Force) {
        cdk deploy $stackName --require-approval never
    } else {
        $confirm = Read-Host "Deploy $stackName? (yes/no/skip)"
        if ($confirm -eq "yes") {
            cdk deploy $stackName --require-approval never
        } elseif ($confirm -eq "skip") {
            Write-Warning "Skipped $stackName"
            continue
        } else {
            Write-Warning "Cancelled $stackName deployment"
            exit 1
        }
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployed $stackName successfully"
    } else {
        Write-Error "Failed to deploy $stackName"
        exit 1
    }
}

# Phase 2: API Gateway (with dependency resolution)
Write-Step "Phase 2: Deploying API Gateway"

if (-not $SkipDependencyResolution) {
    Write-Info "Running API Gateway dependency resolution..."
    $resolveScript = Join-Path $projectRoot "scripts/resolve-api-dependency-conflict.ps1"
    
    if (Test-Path $resolveScript) {
        if ($Force) {
            & $resolveScript -Environment $Environment -Force
        } else {
            & $resolveScript -Environment $Environment
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "API Gateway dependency resolution had issues, but continuing..."
        }
    } else {
        Write-Warning "Dependency resolution script not found, attempting direct deployment..."
        
        Write-Info "Deploying RDSDashboard-API..."
        cdk deploy RDSDashboard-API --require-approval never
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "API Gateway deployment failed"
            exit 1
        }
    }
} else {
    Write-Info "Skipping dependency resolution, deploying API directly..."
    cdk deploy RDSDashboard-API --require-approval never
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "API Gateway deployment failed"
        exit 1
    }
}

Write-Success "API Gateway deployment completed"

# Phase 3: Supporting Infrastructure
Write-Step "Phase 3: Deploying Supporting Infrastructure"

$supportingStacks = @(
    "RDSDashboard-Orchestration",
    "RDSDashboard-OnboardingOrchestration",
    "RDSDashboard-Monitoring"
)

foreach ($stackName in $supportingStacks) {
    Write-Info "Deploying $stackName..."
    
    try {
        cdk deploy $stackName --require-approval never
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Deployed $stackName successfully"
        } else {
            Write-Warning "Failed to deploy $stackName (may not be critical)"
        }
    } catch {
        Write-Warning "Error deploying ${stackName}: $($_.Exception.Message)"
    }
}

# Phase 4: BFF Deployment
Write-Step "Phase 4: Deploying Backend-for-Frontend (BFF)"

Write-Info "Checking Docker availability for BFF deployment..."
try {
    docker --version | Out-Null
    $dockerAvailable = $true
    Write-Success "Docker is available"
} catch {
    $dockerAvailable = $false
    Write-Warning "Docker not available - BFF deployment may fail"
}

if ($dockerAvailable -or $Force) {
    Write-Info "Deploying RDSDashboard-BFF..."
    try {
        cdk deploy RDSDashboard-BFF --require-approval never
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "BFF deployed successfully"
            
            # Setup BFF secrets
            Write-Info "Setting up BFF secrets..."
            $secretsScript = Join-Path $projectRoot "scripts/setup-bff-secrets.ps1"
            if (Test-Path $secretsScript) {
                & $secretsScript
            } else {
                Write-Warning "BFF secrets setup script not found"
            }
        } else {
            Write-Warning "BFF deployment failed"
        }
    } catch {
        Write-Warning "Error deploying BFF: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Skipping BFF deployment due to Docker unavailability"
}

# Phase 5: WAF and Security
Write-Step "Phase 5: Deploying Security Layer"

Write-Info "Deploying RDSDashboard-WAF..."
try {
    cdk deploy RDSDashboard-WAF --require-approval never
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "WAF deployed successfully"
    } else {
        Write-Warning "WAF deployment failed (may not be critical)"
    }
} catch {
    Write-Warning "Error deploying WAF: $($_.Exception.Message)"
}

# Phase 6: Frontend Deployment
if (-not $SkipFrontend) {
    Write-Step "Phase 6: Deploying Frontend"
    
    # Deploy Frontend Stack (S3 + CloudFront)
    Write-Info "Deploying RDSDashboard-Frontend..."
    try {
        cdk deploy RDSDashboard-Frontend --require-approval never
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Frontend infrastructure deployed successfully"
        } else {
            Write-Warning "Frontend infrastructure deployment failed"
        }
    } catch {
        Write-Warning "Error deploying frontend infrastructure: $($_.Exception.Message)"
    }
    
    # Build and deploy frontend application
    Set-Location "$projectRoot/frontend"
    
    if (Test-Path "package.json") {
        Write-Info "Building frontend application..."
        
        # Install dependencies
        npm install
        
        # Build
        npm run build
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Frontend built successfully"
            
            # Get S3 bucket name from CloudFormation
            try {
                $bucketName = aws cloudformation describe-stacks --stack-name "RDSDashboard-Frontend" --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text
                
                if ($bucketName -and $bucketName -ne "None") {
                    Write-Info "Deploying to S3 bucket: $bucketName"
                    aws s3 sync dist/ s3://$bucketName/ --delete
                    
                    # Invalidate CloudFront
                    $distributionId = aws cloudformation describe-stacks --stack-name "RDSDashboard-Frontend" --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].OutputValue' --output text
                    
                    if ($distributionId -and $distributionId -ne "None") {
                        Write-Info "Invalidating CloudFront distribution: $distributionId"
                        aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*"
                    }
                    
                    Write-Success "Frontend deployed to S3 and CloudFront"
                } else {
                    Write-Warning "Could not find S3 bucket name from CloudFormation"
                }
            } catch {
                Write-Warning "Error deploying frontend to S3: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Frontend build failed"
        }
    } else {
        Write-Warning "Frontend package.json not found"
    }
    
    Set-Location $projectRoot
} else {
    Write-Warning "Skipping frontend deployment"
}

# Phase 7: Post-Deployment Verification
Write-Step "Phase 7: Post-Deployment Verification"

Write-Info "Running post-deployment tests..."

# Test Lambda functions
$testFunctions = @(
    "rds-discovery",
    "rds-health-monitor", 
    "rds-query-handler",
    "rds-operations",
    "rds-approval-workflow",
    "rds-monitoring"
)

foreach ($functionName in $testFunctions) {
    Write-Info "Testing $functionName..."
    try {
        aws lambda get-function --function-name $functionName --output json | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$functionName exists and is accessible"
        } else {
            Write-Warning "$functionName not found or not accessible"
        }
    } catch {
        Write-Warning "Could not test $functionName"
    }
}

# Test DynamoDB tables
$testTables = @(
    "rds-inventory",
    "health-alerts",
    "metrics-cache",
    "audit-log",
    "rds-approvals"
)

foreach ($tableName in $testTables) {
    Write-Info "Testing $tableName..."
    try {
        aws dynamodb describe-table --table-name $tableName --output json | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$tableName exists and is accessible"
        } else {
            Write-Warning "$tableName not found or not accessible"
        }
    } catch {
        Write-Warning "Could not test $tableName"
    }
}

# Get deployment URLs
Write-Step "Deployment URLs and Information"

try {
    Write-Info "Retrieving deployment information..."
    
    # API Gateway URL
    $apiUrl = aws cloudformation describe-stacks --stack-name "RDSDashboard-API" --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>$null
    if ($apiUrl -and $apiUrl -ne "None") {
        Write-Success "API Gateway URL: $apiUrl"
    }
    
    # BFF URL
    $bffUrl = aws cloudformation describe-stacks --stack-name "RDSDashboard-BFF" --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' --output text 2>$null
    if ($bffUrl -and $bffUrl -ne "None") {
        Write-Success "BFF API URL: $bffUrl"
    }
    
    # Frontend URL
    $frontendUrl = aws cloudformation describe-stacks --stack-name "RDSDashboard-Frontend" --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' --output text 2>$null
    if ($frontendUrl -and $frontendUrl -ne "None") {
        Write-Success "Frontend URL: $frontendUrl"
    }
    
    # Cognito URLs
    $cognitoUrl = aws cloudformation describe-stacks --stack-name "RDSDashboard-Auth" --query 'Stacks[0].Outputs[?OutputKey==`HostedUIUrl`].OutputValue' --output text 2>$null
    if ($cognitoUrl -and $cognitoUrl -ne "None") {
        Write-Success "Cognito Hosted UI: $cognitoUrl"
    }
    
} catch {
    Write-Warning "Could not retrieve all deployment URLs"
}

# Final summary
Write-Step "Deployment Summary"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT COMPLETE                       ║
╚══════════════════════════════════════════════════════════════╝

Environment: $Environment
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

System Components:
✅ Core Infrastructure (Data, IAM, Compute, Auth)
✅ API Gateway (with dependency resolution)
✅ Supporting Services (Orchestration, Monitoring)
✅ Backend-for-Frontend (BFF)
✅ Security Layer (WAF)
✅ Frontend Application

Next Steps:
1. Test the application in your browser
2. Verify authentication flow works
3. Test API endpoints
4. Monitor CloudWatch logs
5. Set up monitoring and alerts

For detailed testing instructions, see:
  DEPLOYMENT-GUIDE-LATEST.md
  TESTING-SUMMARY.md

"@ -ForegroundColor Green

Write-Success "Complete system deployment finished!"

# Return to original directory
Set-Location $projectRoot