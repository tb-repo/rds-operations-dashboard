# Pre-Deployment Verification Script
# Run this before deploying to verify everything is ready

param(
    [Parameter(Mandatory=$false)]
    [string]$AdminEmail
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pre-Deployment Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allChecks = $true

# Check 1: AWS CLI
Write-Host "Checking AWS CLI..." -ForegroundColor Yellow
try {
    $awsVersion = aws --version 2>&1
    Write-Host "✅ AWS CLI installed: $awsVersion" -ForegroundColor Green
    
    # Check credentials
    $identity = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ AWS credentials configured" -ForegroundColor Green
    } else {
        Write-Host "❌ AWS credentials not configured" -ForegroundColor Red
        $allChecks = $false
    }
} catch {
    Write-Host "❌ AWS CLI not installed" -ForegroundColor Red
    $allChecks = $false
}
Write-Host ""

# Check 2: Node.js
Write-Host "Checking Node.js..." -ForegroundColor Yellow
try {
    $nodeVersion = node --version
    Write-Host "✅ Node.js installed: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js not installed" -ForegroundColor Red
    $allChecks = $false
}
Write-Host ""

# Check 3: npm
Write-Host "Checking npm..." -ForegroundColor Yellow
try {
    $npmVersion = npm --version
    Write-Host "✅ npm installed: $npmVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ npm not installed" -ForegroundColor Red
    $allChecks = $false
}
Write-Host ""

# Check 4: CDK
Write-Host "Checking AWS CDK..." -ForegroundColor Yellow
try {
    $cdkVersion = npx aws-cdk --version 2>&1
    Write-Host "✅ AWS CDK available: $cdkVersion" -ForegroundColor Green
} catch {
    Write-Host "⚠️  AWS CDK not found (will be installed via npx)" -ForegroundColor Yellow
}
Write-Host ""

# Check 5: Docker
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "✅ Docker installed: $dockerVersion" -ForegroundColor Green
    
    # Check if Docker is running
    docker ps 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Docker is running" -ForegroundColor Green
    } else {
        Write-Host "❌ Docker is not running" -ForegroundColor Red
        $allChecks = $false
    }
} catch {
    Write-Host "❌ Docker not installed" -ForegroundColor Red
    $allChecks = $false
}
Write-Host ""

# Check 6: Project structure
Write-Host "Checking project structure..." -ForegroundColor Yellow
$requiredDirs = @(
    "infrastructure",
    "bff",
    "frontend",
    "scripts"
)

foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        Write-Host "✅ Directory exists: $dir" -ForegroundColor Green
    } else {
        Write-Host "❌ Directory missing: $dir" -ForegroundColor Red
        $allChecks = $false
    }
}
Write-Host ""

# Check 7: Required files
Write-Host "Checking required files..." -ForegroundColor Yellow
$requiredFiles = @(
    "infrastructure/lib/auth-stack.ts",
    "infrastructure/lib/bff-stack.ts",
    "bff/Dockerfile",
    "bff/package.json",
    "frontend/package.json",
    "scripts/deploy-auth.ps1",
    "scripts/deploy-bff.ps1"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "✅ File exists: $file" -ForegroundColor Green
    } else {
        Write-Host "❌ File missing: $file" -ForegroundColor Red
        $allChecks = $false
    }
}
Write-Host ""

# Check 8: Dependencies installed
Write-Host "Checking dependencies..." -ForegroundColor Yellow

if (Test-Path "infrastructure/node_modules") {
    Write-Host "✅ Infrastructure dependencies installed" -ForegroundColor Green
} else {
    Write-Host "⚠️  Infrastructure dependencies not installed (run: cd infrastructure && npm install)" -ForegroundColor Yellow
}

if (Test-Path "bff/node_modules") {
    Write-Host "✅ BFF dependencies installed" -ForegroundColor Green
} else {
    Write-Host "⚠️  BFF dependencies not installed (run: cd bff && npm install)" -ForegroundColor Yellow
}

if (Test-Path "frontend/node_modules") {
    Write-Host "✅ Frontend dependencies installed" -ForegroundColor Green
} else {
    Write-Host "⚠️  Frontend dependencies not installed (run: cd frontend && npm install)" -ForegroundColor Yellow
}
Write-Host ""

# Check 9: Admin email provided
Write-Host "Checking admin email..." -ForegroundColor Yellow
if ($AdminEmail) {
    Write-Host "✅ Admin email provided: $AdminEmail" -ForegroundColor Green
} else {
    Write-Host "⚠️  Admin email not provided (will be prompted during deployment)" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($allChecks) {
    Write-Host "✅ All critical checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You are ready to deploy!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Install dependencies (if not already done):" -ForegroundColor White
    Write-Host "   cd infrastructure && npm install && cd .." -ForegroundColor Cyan
    Write-Host "   cd bff && npm install && cd .." -ForegroundColor Cyan
    Write-Host "   cd frontend && npm install && cd .." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Deploy authentication:" -ForegroundColor White
    if ($AdminEmail) {
        Write-Host "   .\scripts\deploy-auth.ps1 -AdminEmail `"$AdminEmail`" -Environment prod" -ForegroundColor Cyan
    } else {
        Write-Host "   .\scripts\deploy-auth.ps1 -AdminEmail `"your-email@company.com`" -Environment prod" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "3. Deploy BFF:" -ForegroundColor White
    Write-Host "   .\scripts\deploy-bff.ps1 -Environment prod" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. Test locally:" -ForegroundColor White
    Write-Host "   cd frontend && npm run dev" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "❌ Some critical checks failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before deploying." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "For detailed deployment instructions, see:" -ForegroundColor White
Write-Host "  - DEPLOYMENT-CHECKLIST.md" -ForegroundColor Cyan
Write-Host "  - QUICK-DEPLOY-COMMANDS.md" -ForegroundColor Cyan
Write-Host "  - AUTH-READY-TO-DEPLOY.md" -ForegroundColor Cyan
Write-Host ""
