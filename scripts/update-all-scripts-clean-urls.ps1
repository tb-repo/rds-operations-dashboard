# Update All Scripts with Clean URLs
# This script systematically removes /prod suffixes from all PowerShell scripts

param(
    [switch]$WhatIf = $false,
    [switch]$Verbose = $false
)

Write-Host "=== API Gateway Clean URL Script Updater ===" -ForegroundColor Cyan
Write-Host "Updating all PowerShell scripts to use clean URLs without /prod suffix" -ForegroundColor Yellow
Write-Host ""

# URL mappings - old URLs with /prod to new clean URLs
$oldUrl1 = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
$newUrl1 = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"

$oldUrl2 = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
$newUrl2 = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"

$oldUrl3 = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
$newUrl3 = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"

# Get all PowerShell scripts in the project
$scriptFiles = Get-ChildItem -Path "." -Recurse -Filter "*.ps1" | Where-Object { 
    $_.FullName -notlike "*\.git\*" -and 
    $_.FullName -notlike "*node_modules*" -and
    $_.Name -ne "update-all-scripts-clean-urls.ps1"
}

Write-Host "Found $($scriptFiles.Count) PowerShell scripts to check" -ForegroundColor Green
Write-Host ""

$updatedFiles = @()
$totalReplacements = 0

foreach ($file in $scriptFiles) {
    $relativePath = $file.FullName.Replace((Get-Location).Path, "").TrimStart('\')
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
    } catch {
        continue
    }
    
    if (-not $content) {
        continue
    }
    
    $originalContent = $content
    $fileReplacements = 0
    
    # Replace URL 1
    if ($content.Contains($oldUrl1)) {
        $matches1 = ($content.Split($oldUrl1, [StringSplitOptions]::None)).Count - 1
        $content = $content.Replace($oldUrl1, $newUrl1)
        $fileReplacements += $matches1
        
        if ($Verbose) {
            Write-Host "  - Replacing $matches1 instances of: $oldUrl1" -ForegroundColor Yellow
        }
    }
    
    # Replace URL 2
    if ($content.Contains($oldUrl2)) {
        $matches2 = ($content.Split($oldUrl2, [StringSplitOptions]::None)).Count - 1
        $content = $content.Replace($oldUrl2, $newUrl2)
        $fileReplacements += $matches2
        
        if ($Verbose) {
            Write-Host "  - Replacing $matches2 instances of: $oldUrl2" -ForegroundColor Yellow
        }
    }
    
    # Replace URL 3
    if ($content.Contains($oldUrl3)) {
        $matches3 = ($content.Split($oldUrl3, [StringSplitOptions]::None)).Count - 1
        $content = $content.Replace($oldUrl3, $newUrl3)
        $fileReplacements += $matches3
        
        if ($Verbose) {
            Write-Host "  - Replacing $matches3 instances of: $oldUrl3" -ForegroundColor Yellow
        }
    }
    
    # Check if file was modified
    if ($content -ne $originalContent) {
        $updatedFiles += $relativePath
        $totalReplacements += $fileReplacements
        
        Write-Host "📝 $relativePath" -ForegroundColor Cyan
        Write-Host "   Replacements: $fileReplacements" -ForegroundColor White
        
        if (-not $WhatIf) {
            try {
                Set-Content -Path $file.FullName -Value $content -NoNewline -ErrorAction Stop
                Write-Host "   ✅ Updated" -ForegroundColor Green
            } catch {
                Write-Host "   ❌ Failed to update: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "   🔍 Would update (WhatIf mode)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

# Summary
Write-Host "=== Update Summary ===" -ForegroundColor Cyan
Write-Host "Files checked: $($scriptFiles.Count)" -ForegroundColor White
Write-Host "Files updated: $($updatedFiles.Count)" -ForegroundColor Green
Write-Host "Total replacements: $totalReplacements" -ForegroundColor Green

if ($WhatIf) {
    Write-Host ""
    Write-Host "⚠️  This was a dry run (WhatIf mode). No files were actually modified." -ForegroundColor Yellow
    Write-Host "Run without -WhatIf to apply changes." -ForegroundColor Yellow
}

if ($updatedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Updated files:" -ForegroundColor Cyan
    foreach ($file in $updatedFiles) {
        Write-Host "  - $file" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "✅ Script update complete!" -ForegroundColor Green

# Validation recommendation
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Deploy infrastructure changes: cd infrastructure && cdk deploy --all" -ForegroundColor White
Write-Host "2. Validate clean URLs: .\scripts\validate-clean-urls.ps1 -Verbose" -ForegroundColor White
Write-Host "3. Test critical endpoints to ensure functionality" -ForegroundColor White