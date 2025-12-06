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
    ./run-local-analysis.ps1
.EXAMPLE
    ./run-local-analysis.ps1 -SkipSecurity -Fix
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

Write-Host "🔍 Running Local Code Analysis" -ForegroundColor Green
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
        Write-Host "🐍 Python Analysis" -ForegroundColor Cyan
        Write-Host "==================" -ForegroundColor Cyan
        
        # Check if Python tools are installed
        $pythonTools = @("pylint", "bandit", "ruff", "safety")
        $missingTools = @()
        
        foreach ($tool in $pythonTools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                $missingTools += $tool
            }
        }
        
        if ($missingTools.Count -gt 0) {
            Write-Host "⚠️  Missing Python tools: $($missingTools -join ', ')" -ForegroundColor Yellow
            Write-Host "   Install with: pip install $($missingTools -join ' ')" -ForegroundColor Yellow
        } else {
            # Run Pylint
            Write-Host "  Running Pylint..." -ForegroundColor Gray
            $pylintFiles = Get-ChildItem -Path "lambda" -Filter "*.py" -Recurse | Where-Object { $_.FullName -notmatch "tests|__pycache__|\.venv" }
            if ($pylintFiles.Count -gt 0) {
                $pylintResult = pylint $pylintFiles.FullName --exit-zero 2>&1
                $pylintScoreMatch = $pylintResult | Select-String "Your code has been rated at ([\d\.]+)/10"
                if ($pylintScoreMatch) {
                    $pylintScore = $pylintScoreMatch.Matches[0].Groups[1].Value
                    Write-Host "  ✅ Pylint score: $pylintScore/10" -ForegroundColor Green
                    if ([double]$pylintScore -lt 8.0) {
                        $issues.Medium++
                    }
                }
            }
            
            # Run Bandit (Security)
            Write-Host "  Running Bandit (security)..." -ForegroundColor Gray
            $banditResult = bandit -r lambda -f json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($banditResult) {
                $criticalCount = ($banditResult.results | Where-Object { $_.issue_severity -eq "HIGH" }).Count
                $highCount = ($banditResult.results | Where-Object { $_.issue_severity -eq "MEDIUM" }).Count
                $issues.Critical += $criticalCount
                $issues.High += $highCount
                
                if ($criticalCount -gt 0) {
                    Write-Host "  ❌ Bandit found $criticalCount critical security issues" -ForegroundColor Red
                } elseif ($highCount -gt 0) {
                    Write-Host "  ⚠️  Bandit found $highCount high security issues" -ForegroundColor Yellow
                } else {
                    Write-Host "  ✅ Bandit: No security issues found" -ForegroundColor Green
                }
            }
            
            # Run Ruff
            Write-Host "  Running Ruff..." -ForegroundColor Gray
            if ($Fix) {
                ruff check lambda --fix 2>&1 | Out-Null
                Write-Host "  ✅ Ruff: Auto-fixed issues" -ForegroundColor Green
            } else {
                $ruffResult = ruff check lambda 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  ✅ Ruff: No issues found" -ForegroundColor Green
                } else {
                    $issues.Low++
                    Write-Host "  ⚠️  Ruff found issues (run with -Fix to auto-fix)" -ForegroundColor Yellow
                }
            }
            
            # Run Safety (dependency check)
            Write-Host "  Running Safety (dependency check)..." -ForegroundColor Gray
            if (Test-Path "lambda/requirements.txt") {
                $safetyResult = safety check -r lambda/requirements.txt --json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($safetyResult) {
                    $vulnCount = $safetyResult.Count
                    if ($vulnCount -gt 0) {
                        $issues.High += $vulnCount
                        Write-Host "  ❌ Safety found $vulnCount vulnerable dependencies" -ForegroundColor Red
                    } else {
                        Write-Host "  ✅ Safety: No vulnerable dependencies" -ForegroundColor Green
                    }
                }
            }
        }
        Write-Host ""
    }
    
    # TypeScript Analysis
    if (-not $SkipTypeScript) {
        Write-Host "📘 TypeScript Analysis" -ForegroundColor Cyan
        Write-Host "======================" -ForegroundColor Cyan
        
        # Check if in frontend directory
        if (Test-Path "frontend/package.json") {
            Push-Location "frontend"
            
            # Check if node_modules exists
            if (-not (Test-Path "node_modules")) {
                Write-Host "  Installing dependencies..." -ForegroundColor Gray
                npm ci 2>&1 | Out-Null
            }
            
            # Run ESLint
            Write-Host "  Running ESLint..." -ForegroundColor Gray
            if ($Fix) {
                npx eslint . --ext .ts,.tsx --fix 2>&1 | Out-Null
                Write-Host "  ✅ ESLint: Auto-fixed issues" -ForegroundColor Green
            } else {
                $eslintResult = npx eslint . --ext .ts,.tsx --format json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($eslintResult) {
                    $errorCount = ($eslintResult | ForEach-Object { $_.errorCount } | Measure-Object -Sum).Sum
                    $warningCount = ($eslintResult | ForEach-Object { $_.warningCount } | Measure-Object -Sum).Sum
                    
                    if ($errorCount -gt 0) {
                        $issues.High += $errorCount
                        Write-Host "  ❌ ESLint found $errorCount errors" -ForegroundColor Red
                    }
                    if ($warningCount -gt 0) {
                        $issues.Low += $warningCount
                        Write-Host "  ⚠️  ESLint found $warningCount warnings" -ForegroundColor Yellow
                    }
                    if ($errorCount -eq 0 -and $warningCount -eq 0) {
                        Write-Host "  ✅ ESLint: No issues found" -ForegroundColor Green
                    }
                }
            }
            
            # Run TypeScript compiler
            Write-Host "  Running TypeScript compiler..." -ForegroundColor Gray
            $tscResult = npx tsc --noEmit 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ TypeScript: No type errors" -ForegroundColor Green
            } else {
                $issues.High++
                Write-Host "  ❌ TypeScript compiler found type errors" -ForegroundColor Red
            }
            
            Pop-Location
        }
        
        # Check BFF
        if (Test-Path "bff/package.json") {
            Push-Location "bff"
            
            if (-not (Test-Path "node_modules")) {
                Write-Host "  Installing BFF dependencies..." -ForegroundColor Gray
                npm ci 2>&1 | Out-Null
            }
            
            Write-Host "  Running BFF TypeScript check..." -ForegroundColor Gray
            $tscResult = npx tsc --noEmit 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ BFF TypeScript: No type errors" -ForegroundColor Green
            } else {
                $issues.High++
                Write-Host "  ❌ BFF TypeScript compiler found type errors" -ForegroundColor Red
            }
            
            Pop-Location
        }
        Write-Host ""
    }
    
    # Security Scans
    if (-not $SkipSecurity) {
        Write-Host "🔒 Security Scans" -ForegroundColor Cyan
        Write-Host "=================" -ForegroundColor Cyan
        
        # GitGuardian
        if (Get-Command ggshield -ErrorAction SilentlyContinue) {
            Write-Host "  Running GitGuardian (secrets detection)..." -ForegroundColor Gray
            $ggResult = ggshield secret scan repo . --exit-zero 2>&1
            if ($ggResult -match "No secrets have been found") {
                Write-Host "  ✅ GitGuardian: No secrets found" -ForegroundColor Green
            } else {
                $issues.Critical++
                Write-Host "  ❌ GitGuardian found potential secrets!" -ForegroundColor Red
            }
        } else {
            Write-Host "  ⚠️  GitGuardian not installed (pip install ggshield)" -ForegroundColor Yellow
        }
        
        # Semgrep
        if (Get-Command semgrep -ErrorAction SilentlyContinue) {
            Write-Host "  Running Semgrep (security patterns)..." -ForegroundColor Gray
            $semgrepResult = semgrep --config=auto --json . 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($semgrepResult) {
                $criticalCount = ($semgrepResult.results | Where-Object { $_.extra.severity -eq "ERROR" }).Count
                $warningCount = ($semgrepResult.results | Where-Object { $_.extra.severity -eq "WARNING" }).Count
                
                if ($criticalCount -gt 0) {
                    $issues.Critical += $criticalCount
                    Write-Host "  ❌ Semgrep found $criticalCount critical issues" -ForegroundColor Red
                } elseif ($warningCount -gt 0) {
                    $issues.Medium += $warningCount
                    Write-Host "  ⚠️  Semgrep found $warningCount warnings" -ForegroundColor Yellow
                } else {
                    Write-Host "  ✅ Semgrep: No security issues found" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "  ⚠️  Semgrep not installed (pip install semgrep)" -ForegroundColor Yellow
        }
        
        Write-Host ""
    }
    
    # Summary
    Write-Host "📊 Analysis Summary" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host ""
    
    $totalIssues = $issues.Critical + $issues.High + $issues.Medium + $issues.Low
    
    if ($issues.Critical -gt 0) {
        Write-Host "  🔴 Critical: $($issues.Critical)" -ForegroundColor Red
    }
    if ($issues.High -gt 0) {
        Write-Host "  🟠 High: $($issues.High)" -ForegroundColor Yellow
    }
    if ($issues.Medium -gt 0) {
        Write-Host "  🟡 Medium: $($issues.Medium)" -ForegroundColor Yellow
    }
    if ($issues.Low -gt 0) {
        Write-Host "  🟢 Low: $($issues.Low)" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    if ($totalIssues -eq 0) {
        Write-Host "✅ No issues found! Code is ready to commit." -ForegroundColor Green
    } elseif ($issues.Critical -gt 0) {
        Write-Host "❌ Critical issues found! Fix before committing." -ForegroundColor Red
        exit 1
    } elseif ($issues.High -gt 0) {
        Write-Host "⚠️  High priority issues found. Consider fixing before committing." -ForegroundColor Yellow
    } else {
        Write-Host "✅ Only minor issues found. Safe to commit." -ForegroundColor Green
    }
    
    $duration = (Get-Date) - $startTime
    $durationSeconds = $duration.TotalSeconds.ToString("F1")
    Write-Host ""
    Write-Host "⏱️  Analysis completed in $durationSeconds seconds" -ForegroundColor Cyan
    
} catch {
    Write-Host "❌ Analysis failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
