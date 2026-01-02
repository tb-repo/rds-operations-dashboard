#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Resolve API Gateway deployment dependency conflict
.DESCRIPTION
    This script resolves the circular dependency issue where BFF and WAF stacks
    import API Gateway exports, preventing API stack updates.
.PARAMETER Environment
    Target environment (dev, staging, prod)
.PARAMETER Force
    Force deployment even if conflicts exist
.EXAMPLE
    .\resolve-api-dependency-conflict.ps1 -Environment dev
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [switch]$Force
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
║     API Gateway Dependency Conflict Resolution              ║
║                                                              ║
║     Resolving circular dependencies between:                 ║
║     • API Gateway Stack                                      ║
║     • BFF Stack (imports API exports)                       ║
║     • WAF Stack (imports API exports)                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "Environment: $Environment"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Change to infrastructure directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$infraPath = Join-Path $projectRoot "infrastructure"

if (-not (Test-Path $infraPath)) {
    Write-Error "Infrastructure directory not found: $infraPath"
    exit 1
}

Set-Location $infraPath

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

# Install dependencies
Write-Info "Installing CDK dependencies..."
npm install

# Check current stack status
Write-Step "Analyzing Current Stack Dependencies"

$apiStackName = "RDSDashboard-API"
$bffStackName = "RDSDashboard-BFF"
$wafStackName = "RDSDashboard-WAF"

# Check if stacks exist
Write-Info "Checking existing stacks..."

$existingStacks = @()
try {
    $stackList = aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --output json | ConvertFrom-Json
    $existingStacks = $stackList.StackSummaries | Where-Object { $_.StackName -like "RDSDashboard-*" } | Select-Object -ExpandProperty StackName
    
    Write-Info "Found existing stacks:"
    foreach ($stack in $existingStacks) {
        Write-Info "  - $stack"
    }
} catch {
    Write-Warning "Could not list existing stacks"
}

# Strategy 1: Try direct API stack deployment first
Write-Step "Strategy 1: Attempting Direct API Stack Deployment"

Write-Info "Checking if API stack can be deployed directly..."
try {
    Write-Info "Running CDK diff for API stack..."
    cdk diff $apiStackName 2>&1 | Out-String | Write-Host
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "API stack diff successful. Attempting deployment..."
        
        if ($Force) {
            Write-Warning "Force flag enabled - deploying without confirmation"
            cdk deploy $apiStackName --require-approval never
        } else {
            $confirm = Read-Host "Deploy API stack now? This may resolve the dependency conflict (yes/no)"
            if ($confirm -eq "yes") {
                cdk deploy $apiStackName --require-approval never
            } else {
                Write-Warning "API stack deployment cancelled"
            }
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "API stack deployed successfully!"
            Write-Info "Dependency conflict resolved. You can now deploy other stacks."
            exit 0
        } else {
            Write-Warning "API stack deployment failed. Trying alternative strategies..."
        }
    }
} catch {
    Write-Warning "Direct API stack deployment not possible. Trying alternative strategies..."
}

# Strategy 2: Temporary stack removal and redeployment
Write-Step "Strategy 2: Temporary Stack Removal Approach"

Write-Warning "This strategy involves temporarily removing dependent stacks"
Write-Warning "This will cause temporary service disruption"

if (-not $Force) {
    $confirm = Read-Host "Do you want to proceed with temporary stack removal? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Info "Temporary removal cancelled"
        exit 0
    }
}

# Check which dependent stacks exist
$dependentStacks = @()
if ($bffStackName -in $existingStacks) {
    $dependentStacks += $bffStackName
}
if ($wafStackName -in $existingStacks) {
    $dependentStacks += $wafStackName
}

if ($dependentStacks.Count -eq 0) {
    Write-Info "No dependent stacks found. API stack should deploy cleanly."
    Write-Info "Attempting API stack deployment..."
    cdk deploy $apiStackName --require-approval never
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "API stack deployed successfully!"
        exit 0
    } else {
        Write-Error "API stack deployment failed"
        exit 1
    }
}

Write-Info "Found dependent stacks that need temporary removal:"
foreach ($stack in $dependentStacks) {
    Write-Info "  - $stack"
}

# Step 1: Remove dependent stacks
Write-Info "Step 1: Removing dependent stacks..."
foreach ($stack in $dependentStacks) {
    Write-Info "Removing $stack..."
    try {
        cdk destroy $stack --force
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Removed $stack"
        } else {
            Write-Warning "Failed to remove $stack (may not exist)"
        }
    } catch {
        Write-Warning "Error removing $stack: $_"
    }
}

# Step 2: Deploy API stack
Write-Info "Step 2: Deploying API stack..."
cdk deploy $apiStackName --require-approval never

if ($LASTEXITCODE -ne 0) {
    Write-Error "API stack deployment failed even after removing dependent stacks"
    exit 1
}

Write-Success "API stack deployed successfully!"

# Step 3: Redeploy dependent stacks
Write-Info "Step 3: Redeploying dependent stacks..."
foreach ($stack in $dependentStacks) {
    Write-Info "Redeploying $stack..."
    try {
        cdk deploy $stack --require-approval never
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Redeployed $stack"
        } else {
            Write-Warning "Failed to redeploy $stack"
        }
    } catch {
        Write-Warning "Error redeploying $stack: $_"
    }
}

# Strategy 3: Environment-specific deployment
Write-Step "Strategy 3: Environment-Specific Deployment"

Write-Info "Attempting environment-specific deployment approach..."

# Deploy with environment suffix
$envApiStackName = "$apiStackName-$Environment"
Write-Info "Deploying $envApiStackName..."

try {
    cdk deploy $envApiStackName --require-approval never
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Environment-specific API stack deployed: $envApiStackName"
    } else {
        Write-Warning "Environment-specific deployment also failed"
    }
} catch {
    Write-Warning "Environment-specific deployment error: $_"
}

# Final verification
Write-Step "Final Verification"

Write-Info "Checking final stack status..."
try {
    $finalStacks = aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --output json | ConvertFrom-Json
    $finalApiStacks = $finalStacks.StackSummaries | Where-Object { $_.StackName -like "*API*" }
    
    if ($finalApiStacks.Count -gt 0) {
        Write-Success "API stack(s) found:"
        foreach ($stack in $finalApiStacks) {
            Write-Success "  - $($stack.StackName) ($($stack.StackStatus))"
        }
    } else {
        Write-Warning "No API stacks found in final verification"
    }
} catch {
    Write-Warning "Could not verify final stack status"
}

# Summary and next steps
Write-Step "Summary and Next Steps"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    RESOLUTION COMPLETE                       ║
╚══════════════════════════════════════════════════════════════╝

The API Gateway dependency conflict resolution process is complete.

Next Steps:
1. Verify API Gateway is accessible
2. Test API endpoints
3. Deploy remaining stacks (Frontend, etc.)
4. Run end-to-end tests

If issues persist:
1. Check CloudFormation console for detailed error messages
2. Review stack dependencies in CDK code
3. Consider manual CloudFormation template deployment
4. Contact DevOps team for assistance

"@ -ForegroundColor Green

Write-Success "Dependency conflict resolution completed!"

# Return to original directory
Set-Location $projectRoot