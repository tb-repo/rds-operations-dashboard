#!/usr/bin/env pwsh
# Fix AWS Client Imports - Replace incorrect imports with correct class-based imports

Write-Host "=== Fixing AWS Client Imports ===" -ForegroundColor Cyan

$files = @(
    "../lambda/cloudops-generator/handler.py",
    "../lambda/compliance-checker/checks.py",
    "../lambda/compliance-checker/reporting.py",
    "../lambda/cost-analyzer/reporting.py",
    "../lambda/cost-analyzer/utilization.py"
)

$successCount = 0
$errorCount = 0

foreach ($file in $files) {
    try {
        Write-Host "Processing $file..." -ForegroundColor Yellow
        
        $content = Get-Content $file -Raw
        
        # Replace incorrect imports
        $content = $content -replace 'from shared\.aws_clients import get_rds_client', 'from shared.aws_clients import AWSClients'
        $content = $content -replace 'from shared\.aws_clients import get_cloudwatch_client', 'from shared.aws_clients import AWSClients'
        $content = $content -replace 'from shared\.aws_clients import get_s3_client', 'from shared.aws_clients import AWSClients'
        $content = $content -replace 'from shared\.aws_clients import get_dynamodb_client', 'from shared.aws_clients import AWSClients'
        
        # Replace function calls with class method calls
        $content = $content -replace '\bget_rds_client\(', 'AWSClients.get_rds_client('
        $content = $content -replace '\bget_cloudwatch_client\(', 'AWSClients.get_cloudwatch_client('
        $content = $content -replace '\bget_s3_client\(', 'AWSClients.get_s3_client('
        $content = $content -replace '\bget_dynamodb_client\(', 'AWSClients.get_dynamodb_client('
        
        # Write back
        Set-Content -Path $file -Value $content -NoNewline
        
        Write-Host "Fixed $file" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "Failed to fix $file : $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Success: $successCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Green' })

if ($errorCount -eq 0) {
    Write-Host "`nAll imports fixed successfully!" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run: ./prepare-lambda-packages.ps1" -ForegroundColor Cyan
    Write-Host "2. Deploy: npx cdk deploy RDSDashboard-Compute-prod" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nSome files failed to fix" -ForegroundColor Red
    exit 1
}
