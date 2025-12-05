# Fix Lambda Shared Module Issue
param([string]$Environment = "prod")

Write-Host "Fixing Lambda shared module issue for environment: $Environment" -ForegroundColor Green

$functions = @("discovery", "health-monitor", "cost-analyzer", "query-handler", "compliance-checker", "operations", "cloudops-generator")
$tempDir = Join-Path $env:TEMP "lambda-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

foreach ($func in $functions) {
    $functionName = "rds-$func-$Environment"
    Write-Host "`nProcessing $functionName..." -ForegroundColor Yellow
    
    $sourcePath = Join-Path $PSScriptRoot "..\lambda\$func"
    if (-not (Test-Path $sourcePath)) {
        Write-Host "  Skipping - not found" -ForegroundColor Gray
        continue
    }
    
    $deployDir = Join-Path $tempDir $functionName
    New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
    
    Write-Host "  Copying code..." -ForegroundColor Gray
    Copy-Item -Path "$sourcePath\*" -Destination $deployDir -Recurse -Force
    
    Write-Host "  Copying shared module..." -ForegroundColor Gray
    $sharedSource = Join-Path $PSScriptRoot "..\lambda\shared"
    $sharedDest = Join-Path $deployDir "shared"
    Copy-Item -Path $sharedSource -Destination $sharedDest -Recurse -Force
    
    $zipFile = Join-Path $tempDir "$functionName.zip"
    Write-Host "  Creating ZIP..." -ForegroundColor Gray
    Compress-Archive -Path "$deployDir\*" -DestinationPath $zipFile -Force
    
    Write-Host "  Updating Lambda..." -ForegroundColor Gray
    aws lambda update-function-code --function-name $functionName --zip-file "fileb://$zipFile" --output json | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Success!" -ForegroundColor Green
    } else {
        Write-Host "  Failed!" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nDone!" -ForegroundColor Green
