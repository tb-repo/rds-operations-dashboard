#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run local code analysis before committing
.DESCRIPTION
    This script runs multiple code analysis tools locally to catch issues
    before they are pushed to the repository and analyzed by CI/CD.
.PARAMETER SkipPython
    Skip Python analysis
.PARAMETER SkipTypeScript
    Skip TypeScript analysis
.PARAMETER SkipSecurity
    Skip security scans
.PARAMETER Fix
    Automatically fix issues where possible
.EXAMPLE
    ./run-local-analysis-simple.ps1
.EXAMPLE
    ./run-local-analysis-simple.ps1 -SkipSecurity -Fix
#>
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipPython,
    [Parameter(Mandatory = $false)]
    [switch]$SkipTypeScript,
    [Parameter(Mandatory = $false)]
    [switch]$SkipSecurity,
    [Parameter(Mandatory = $false)]
    [switch]$Fix
)

$ErrorActionPreference = "Continue"
$startTime = Get-Date

Write-Host "[*] Running Local Code Analysis" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""

$issues = @{
    Critical = 0
    High = 0
    Medium = 0
    Low = 0
}

# Change to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Push-Location $projectRoot

try {
    # Python Analysis
    if (-not $SkipPython) {
        Write-Host "[Python Analysis]" -ForegroundColor Cyan
        Write-Host "==================" -ForegroundColor Cyan
        
        # Check if Ruff is installed
        if (Get-Command ruff -ErrorAction SilentlyContinue) {
            Write-Host "  Running Ruff..." -ForegroundColor Gray
            if ($Fix) {
                ruff check lambda --fix 2>&1 | Out-Null
                Write-Host "  [OK] Ruff: Auto-fixed issues" -ForegroundColor Green
            } else {
                $ruffResult = ruff check lambda 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] Ruff: No issues found" -ForegroundColor Green
                } else {
                    $issues.Low++
                    Write-Host "  [WARN] Ruff found issues (run with -Fix to auto-fix)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "  [SKIP] Ruff not installed (pip install ruff)" -ForegroundColor Yellow
        }
        
        # Check if Bandit is installed
        if (Get-Command bandit -ErrorAction SilentlyContinue) {
            Write-Host "  Running Bandit (security)..." -ForegroundColor Gray
            $banditOutput = bandit -r lambda -f json 2>&1
            try {
                $banditResult = $banditOutput | ConvertFrom-Json
                if ($banditResult.results) {
                    $criticalCount = ($banditResult.results | Where-Object { $_.issue_severity -eq "HIGH" }).Count
                    $highCount = ($banditResult.results | Where-Object { $_.issue_severity -eq "MEDIUM" }).Count
                    $issues.Critical += $criticalCount
                    $issues.High += $highCount
                    
                    if ($criticalCount -gt 0) {
                        Write-Host "  [ERROR] Bandit found $criticalCount critical security issues" -ForegroundColor Red
                    } elseif ($highCount -gt 0) {
                        Write-Host "  [WARN] Bandit found $highCount high security issues" -ForegroundColor Yellow
                    } else {
                        Write-Host "  [OK] Bandit: No security issues found" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  [OK] Bandit: No security issues found" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [SKIP] Bandit: Could not parse results" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [SKIP] Bandit not installed (pip install bandit)" -ForegroundColor Yellow
        }
        
        Write-Host ""
    }
    
    # TypeScript Analysis
    if (-not $SkipTypeScript) {
        Write-Host "[TypeScript Analysis]" -ForegroundColor Cyan
        Write-Host "======================" -ForegroundColor Cyan
        
        # Check frontend
        if (Test-Path "frontend/package.json") {
            Push-Location "frontend"
            
            # Check if node_modules exists
            if (-not (Test-Path "node_modules")) {
                Write-Host "  Installing dependencies..." -ForegroundColor Gray
                npm ci 2>&1 | Out-Null
            }
            
            # Run ESLint
            if (Test-Path "node_modules/.bin/eslint") {
                Write-Host "  Running ESLint..." -ForegroundColor Gray
                if ($Fix) {
                    npx eslint . --ext .ts,.tsx --fix 2>&1 | Out-Null
                    Write-Host "  [OK] ESLint: Auto-fixed issues" -ForegroundColor Green
                } else {
                    $eslintOutput = npx eslint . --ext .ts,.tsx --format json 2>&1
                    try {
                        $eslintResult = $eslintOutput | ConvertFrom-Json
                        if ($eslintResult) {
                            $errorCount = ($eslintResult | ForEach-Object { $_.errorCount } | Measure-Object -Sum).Sum
                            $warningCount = ($eslintResult | ForEach-Object { $_.warningCount } | Measure-Object -Sum).Sum
                            
                            if ($errorCount -gt 0) {
                                $issues.High += $errorCount
                                Write-Host "  [ERROR] ESLint found $errorCount errors" -ForegroundColor Red
                            }
                            if ($warningCount -gt 0) {
                                $issues.Low += $warningCount
                                Write-Host "  [WARN] ESLint found $warningCount warnings" -ForegroundColor Yellow
                            }
                            if ($errorCount -eq 0 -and $warningCount -eq 0) {
                                Write-Host "  [OK] ESLint: No issues found" -ForegroundColor Green
                            }
                        }
                    } catch {
                        Write-Host "  [SKIP] ESLint: Could not parse results" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "  [SKIP] ESLint not found" -ForegroundColor Yellow
            }
            
            # Run TypeScript compiler
            if (Test-Path "node_modules/.bin/tsc") {
                Write-Host "  Running TypeScript compiler..." -ForegroundColor Gray
                $tscResult = npx tsc --noEmit 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] TypeScript: No type errors" -ForegroundColor Green
                } else {
                    $issues.High++
                    Write-Host "  [ERROR] TypeScript compiler found type errors" -ForegroundColor Red
                }
            } else {
                Write-Host "  [SKIP] TypeScript compiler not found" -ForegroundColor Yellow
            }
            
            Pop-Location
        } else {
            Write-Host "  [SKIP] Frontend directory not found" -ForegroundColor Yellow
        }
        
        Write-Host ""
    }
    
    # Security Scans
    if (-not $SkipSecurity) {
        Write-Host "[Security Scans]" -ForegroundColor Cyan
        Write-Host "=================" -ForegroundColor Cyan
        
        # Check for hardcoded secrets (simple pattern matching)
        Write-Host "  Checking for potential secrets..." -ForegroundColor Gray
        $secretPatterns = @(
            "password\s*=\s*['\`"][^'\`"]+['\`"]",
            "api[_-]?key\s*=\s*['\`"][^'\`"]+['\`"]",
            "secret\s*=\s*['\`"][^'\`"]+['\`"]",
            "token\s*=\s*['\`"][^'\`"]+['\`"]"
        )
        
        $secretsFound = 0
        foreach ($pattern in $secretPatterns) {
            $matches = Select-String -Path "lambda/**/*.py","frontend/**/*.ts","frontend/**/*.tsx","bff/**/*.ts" -Pattern $pattern -ErrorAction SilentlyContinue
            if ($matches) {
                $secretsFound += $matches.Count
            }
        }
        
        if ($secretsFound -gt 0) {
            $issues.Critical += $secretsFound
            Write-Host "  [ERROR] Found $secretsFound potential hardcoded secrets" -ForegroundColor Red
        } else {
            Write-Host "  [OK] No obvious hardcoded secrets found" -ForegroundColor Green
        }
        
        Write-Host ""
    }
    
    # Summary
    Write-Host "[Analysis Summary]" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host ""
    
    $totalIssues = $issues.Critical + $issues.High + $issues.Medium + $issues.Low
    
    if ($issues.Critical -gt 0) {
        Write-Host "  [CRITICAL] $($issues.Critical)" -ForegroundColor Red
    }
    if ($issues.High -gt 0) {
        Write-Host "  [HIGH] $($issues.High)" -ForegroundColor Yellow
    }
    if ($issues.Medium -gt 0) {
        Write-Host "  [MEDIUM] $($issues.Medium)" -ForegroundColor Yellow
    }
    if ($issues.Low -gt 0) {
        Write-Host "  [LOW] $($issues.Low)" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    if ($totalIssues -eq 0) {
        Write-Host "[OK] No issues found! Code is ready to commit." -ForegroundColor Green
        $exitCode = 0
    } elseif ($issues.Critical -gt 0) {
        Write-Host "[ERROR] Critical issues found! Fix before committing." -ForegroundColor Red
        $exitCode = 1
    } elseif ($issues.High -gt 0) {
        Write-Host "[WARN] High priority issues found. Consider fixing before committing." -ForegroundColor Yellow
        $exitCode = 0
    } else {
        Write-Host "[OK] Only minor issues found. Safe to commit." -ForegroundColor Green
        $exitCode = 0
    }
    
    $duration = (Get-Date) - $startTime
    $durationSeconds = [math]::Round($duration.TotalSeconds, 1)
    Write-Host ""
    Write-Host "[*] Analysis completed in $durationSeconds seconds" -ForegroundColor Cyan
    
    exit $exitCode
    
} catch {
    Write-Host "[ERROR] Analysis failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
