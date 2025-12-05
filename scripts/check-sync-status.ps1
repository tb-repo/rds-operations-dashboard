#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Check Git sync status and provide recommendations
.DESCRIPTION
    This script analyzes your Git repository status and provides
    clear recommendations for syncing to GitHub.
#>

$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking Git Sync Status..." -ForegroundColor Green
Write-Host ""

# Change to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    # Check if git repo
    $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
    if (-not $isGitRepo) {
        Write-Host "❌ Not a git repository" -ForegroundColor Red
        exit 1
    }

    # Get current branch
    $currentBranch = git branch --show-current
    Write-Host "📍 Current Branch: $currentBranch" -ForegroundColor Cyan
    
    # Get remote info
    $remoteUrl = git remote get-url origin 2>$null
    if ($remoteUrl) {
        Write-Host "🌐 Remote: $remoteUrl" -ForegroundColor Cyan
    } else {
        Write-Host "⚠️  No remote configured" -ForegroundColor Yellow
    }
    Write-Host ""

    # Count changes
    $staged = (git diff --cached --name-only | Measure-Object).Count
    $unstaged = (git diff --name-only | Measure-Object).Count
    $untracked = (git ls-files --others --exclude-standard | Measure-Object).Count
    $total = $staged + $unstaged + $untracked

    # Display summary
    Write-Host "📊 Change Summary:" -ForegroundColor Yellow
    Write-Host "   ✅ Staged:    $staged files" -ForegroundColor Green
    Write-Host "   📝 Unstaged:  $unstaged files" -ForegroundColor Yellow
    Write-Host "   🆕 Untracked: $untracked files" -ForegroundColor Cyan
    Write-Host "   📦 Total:     $total files" -ForegroundColor White
    Write-Host ""

    if ($total -eq 0) {
        Write-Host "✅ Repository is clean - nothing to sync!" -ForegroundColor Green
        
        # Check if ahead/behind remote
        git fetch origin $currentBranch 2>$null
        $ahead = (git rev-list --count origin/$currentBranch..$currentBranch 2>$null)
        $behind = (git rev-list --count $currentBranch..origin/$currentBranch 2>$null)
        
        if ($ahead -gt 0) {
            Write-Host "⬆️  You are $ahead commit(s) ahead of origin/$currentBranch" -ForegroundColor Yellow
            Write-Host "   Run: git push origin $currentBranch" -ForegroundColor Cyan
        } elseif ($behind -gt 0) {
            Write-Host "⬇️  You are $behind commit(s) behind origin/$currentBranch" -ForegroundColor Yellow
            Write-Host "   Run: git pull origin $currentBranch" -ForegroundColor Cyan
        } else {
            Write-Host "🎯 Your branch is up to date with origin/$currentBranch" -ForegroundColor Green
        }
        
        exit 0
    }

    # Show detailed status
    Write-Host "📋 Detailed Status:" -ForegroundColor Yellow
    Write-Host ""
    
    if ($staged -gt 0) {
        Write-Host "✅ Staged Changes:" -ForegroundColor Green
        git diff --cached --name-status | ForEach-Object {
            Write-Host "   $_" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    if ($unstaged -gt 0) {
        Write-Host "📝 Unstaged Changes:" -ForegroundColor Yellow
        git diff --name-status | ForEach-Object {
            Write-Host "   $_" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    if ($untracked -gt 0) {
        Write-Host "🆕 Untracked Files:" -ForegroundColor Cyan
        git ls-files --others --exclude-standard | ForEach-Object {
            Write-Host "   $_" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # Provide recommendations
    Write-Host "💡 Recommendations:" -ForegroundColor Yellow
    Write-Host ""
    
    if ($total -gt 0) {
        Write-Host "Option 1: Quick Sync (Recommended)" -ForegroundColor Green
        Write-Host "   ./scripts/sync-to-github.ps1 -Message 'Your commit message'" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Option 2: Manual Sync" -ForegroundColor Green
        Write-Host "   git add -A" -ForegroundColor Cyan
        Write-Host "   git commit -m 'Your commit message'" -ForegroundColor Cyan
        Write-Host "   git push origin $currentBranch" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Option 3: Review Changes First" -ForegroundColor Green
        Write-Host "   git diff                    # Review unstaged changes" -ForegroundColor Cyan
        Write-Host "   git diff --cached           # Review staged changes" -ForegroundColor Cyan
        Write-Host "   git status                  # Full status" -ForegroundColor Cyan
        Write-Host ""
    }

    # Check for large files
    Write-Host "🔍 Checking for large files..." -ForegroundColor Yellow
    $largeFiles = git ls-files | ForEach-Object {
        if (Test-Path $_) {
            $size = (Get-Item $_).Length
            if ($size -gt 10MB) {
                [PSCustomObject]@{
                    File = $_
                    Size = [math]::Round($size / 1MB, 2)
                }
            }
        }
    }
    
    if ($largeFiles) {
        Write-Host "⚠️  Large files detected (>10MB):" -ForegroundColor Yellow
        $largeFiles | ForEach-Object {
            Write-Host "   $($_.File) - $($_.Size) MB" -ForegroundColor Red
        }
        Write-Host "   Consider using Git LFS for large files" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "✅ No large files detected" -ForegroundColor Green
        Write-Host ""
    }

    # Final message
    Write-Host "📚 For more help, see:" -ForegroundColor Cyan
    Write-Host "   - docs/github-sync-guide.md" -ForegroundColor Gray
    Write-Host "   - SYNC-NOW.md" -ForegroundColor Gray
    Write-Host ""

} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
