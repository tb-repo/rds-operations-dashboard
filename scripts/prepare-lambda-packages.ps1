#!/usr/bin/env pwsh
# Prepare Lambda Packages - Copy shared module to each Lambda directory

Write-Host "=== Preparing Lambda Packages ===" -ForegroundColor Cyan

$lambdaDirs = @(
    "compliance-checker",
    "cost-analyzer",
    "discovery",
    "health-monitor",
    "operations",
    "query-handler",
    "cloudops-generator"
)

$sharedDir = "../lambda/shared"
$successCount = 0
$errorCount = 0

foreach ($dir in $lambdaDirs) {
    $targetDir = "../lambda/$dir/shared"
    
    try {
        Write-Host "Copying shared module to $dir..." -ForegroundColor Yellow
        
        # Remove existing shared directory if it exists
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }
        
        # Copy shared module
        Copy-Item -Path $sharedDir -Destination $targetDir -Recurse -Force
        
        Write-Host "Successfully copied shared module to $dir" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "Failed to copy shared module to $dir : $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Success: $successCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Green' })

if ($errorCount -eq 0) {
    Write-Host "`nAll Lambda packages prepared successfully!" -ForegroundColor Green
    Write-Host "You can now deploy the Compute stack: npx cdk deploy RDSDashboard-Compute-prod" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nSome Lambda packages failed to prepare" -ForegroundColor Red
    exit 1
}
