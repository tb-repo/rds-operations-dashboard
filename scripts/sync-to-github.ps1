#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sync local changes to GitHub repository
.DESCRIPTION
    This script stages all changes, commits them, and pushes to GitHub.
    It handles both staged and unstaged changes.
.PARAMETER Message
    Commit message (optional, will prompt if not provided)
.PARAMETER Branch
    Branch to push to (default: main)
.PARAMETER Force
    Force push (use with caution)
.EXAMPLE
    ./sync-to-github.ps1 -Message "Add external code analysis integration"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$Message,
    [Parameter(Mandatory = $false)]
    [string]$Branch = "main",
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "🔄 Syncing code to GitHub..." -ForegroundColor Green

# Change to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    # Check if we're in a git repository
    $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
    if (-not $isGitRepo) {
        throw "Not a git repository. Please initialize git first."
    }

    # Get current branch
    $currentBranch = git branch --show-current
    Write-Host "📍 Current branch: $currentBranch" -ForegroundColor Cyan

    # Check for uncommitted changes
    $status = git status --porcelain
    if (-not $status) {
        Write-Host "✅ No changes to commit. Repository is up to date." -ForegroundColor Green
        exit 0
    }

    Write-Host "📋 Changes detected:" -ForegroundColor Yellow
    git status --short

    # Stage all changes
    Write-Host "`n📦 Staging all changes..." -ForegroundColor Yellow
    git add -A

    # Get commit message if not provided
    if (-not $Message) {
        Write-Host "`n💬 Enter commit message:" -ForegroundColor Yellow
        $Message = Read-Host
        if (-not $Message) {
            $Message = "Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Write-Host "Using default message: $Message" -ForegroundColor Gray
        }
    }

    # Commit changes
    Write-Host "`n💾 Committing changes..." -ForegroundColor Yellow
    git commit -m $Message

    # Check if remote exists
    $remotes = git remote
    if (-not $remotes) {
        Write-Host "⚠️  No remote repository configured." -ForegroundColor Yellow
        Write-Host "To add a remote, run:" -ForegroundColor Yellow
        Write-Host "  git remote add origin [your-github-repo-url]" -ForegroundColor Cyan
        exit 1
    }

    # Get remote URL
    $remoteUrl = git remote get-url origin
    Write-Host "🌐 Remote: $remoteUrl" -ForegroundColor Cyan

    # Push to GitHub
    Write-Host "`n🚀 Pushing to GitHub ($Branch)..." -ForegroundColor Yellow
    
    if ($Force) {
        Write-Host "⚠️  Force pushing..." -ForegroundColor Red
        git push origin $Branch --force
    } else {
        git push origin $Branch
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Successfully synced to GitHub!" -ForegroundColor Green
        Write-Host "🔗 View at: $remoteUrl" -ForegroundColor Cyan
        
        # Show summary
        Write-Host "`n📊 Summary:" -ForegroundColor Cyan
        Write-Host "   Branch: $Branch" -ForegroundColor Gray
        Write-Host "   Commit: $Message" -ForegroundColor Gray
        Write-Host "   Remote: $remoteUrl" -ForegroundColor Gray
    } else {
        throw "Push failed. You may need to pull changes first or resolve conflicts."
    }

} catch {
    Write-Host "`n❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "   1. Make sure you have push access to the repository" -ForegroundColor Gray
    Write-Host "   2. Try pulling changes first: git pull origin $Branch" -ForegroundColor Gray
    Write-Host "   3. Check if you need to authenticate with GitHub" -ForegroundColor Gray
    Write-Host "   4. Resolve any merge conflicts if they exist" -ForegroundColor Gray
    exit 1
} finally {
    Pop-Location
}
