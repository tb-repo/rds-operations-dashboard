# Fix All Lambda Import Statements
# This script fixes import statements in all Lambda handlers to match the actual shared module structure

param([string]$Environment = "prod")

Write-Host "Fixing Lambda import statements..." -ForegroundColor Green

# Fix cost-analyzer handler
Write-Host "`nFixing cost-analyzer/handler.py..." -ForegroundColor Yellow
$costAnalyzerPath = Join-Path $PSScriptRoot "..\lambda\cost-analyzer\handler.py"
$content = Get-Content $costAnalyzerPath -Raw

$content = $content -replace 'from shared\.logger import get_logger', 'from shared import StructuredLogger'
$content = $content -replace 'from shared\.aws_clients import get_dynamodb_client, get_s3_client, get_cloudwatch_client', 'from shared import AWSClients'
$content = $content -replace 'from shared\.config import get_config', 'from shared import Config'
$content = $content -replace 'logger = get_logger\(__name__\)', 'logger = StructuredLogger("cost-analyzer")'
$content = $content -replace 'get_dynamodb_client\(\)', 'AWSClients.get_dynamodb_client()'
$content = $content -replace 'get_s3_client\(\)', 'AWSClients.get_s3_client()'
$content = $content -replace 'get_cloudwatch_client\(\)', 'AWSClients.get_cloudwatch_client()'
$content = $content -replace 'get_config\(\)', 'Config.load()'

[System.IO.File]::WriteAllText($costAnalyzerPath, $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "  Fixed cost-analyzer" -ForegroundColor Green

# Fix compliance-checker handler
Write-Host "`nFixing compliance-checker/handler.py..." -ForegroundColor Yellow
$compliancePath = Join-Path $PSScriptRoot "..\lambda\compliance-checker\handler.py"
$content = Get-Content $compliancePath -Raw

$content = $content -replace 'from shared\.logger import get_logger', 'from shared import StructuredLogger'
$content = $content -replace 'from shared\.aws_clients import get_dynamodb_client, get_s3_client, get_sns_client', 'from shared import AWSClients'
$content = $content -replace 'from shared\.config import get_config', 'from shared import Config'
$content = $content -replace 'logger = get_logger\(__name__\)', 'logger = StructuredLogger("compliance-checker")'
$content = $content -replace 'get_dynamodb_client\(\)', 'AWSClients.get_dynamodb_client()'
$content = $content -replace 'get_s3_client\(\)', 'AWSClients.get_s3_client()'
$content = $content -replace 'get_sns_client\(\)', 'AWSClients.get_sns_client()'
$content = $content -replace 'get_config\(\)', 'Config.load()'

[System.IO.File]::WriteAllText($compliancePath, $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "  Fixed compliance-checker" -ForegroundColor Green

# Fix operations handler
Write-Host "`nFixing operations/handler.py..." -ForegroundColor Yellow
$operationsPath = Join-Path $PSScriptRoot "..\lambda\operations\handler.py"
$content = Get-Content $operationsPath -Raw

$content = $content -replace 'from shared\.logger import get_logger', 'from shared import StructuredLogger'
$content = $content -replace 'from shared\.aws_clients import get_rds_client, get_dynamodb_client', 'from shared import AWSClients'
$content = $content -replace 'from shared\.config import get_config', 'from shared import Config'
$content = $content -replace 'logger = get_logger\(__name__\)', 'logger = StructuredLogger("operations")'
$content = $content -replace 'get_rds_client\(\)', 'AWSClients.get_rds_client()'
$content = $content -replace 'get_dynamodb_client\(\)', 'AWSClients.get_dynamodb_client()'
$content = $content -replace 'get_config\(\)', 'Config.load()'

[System.IO.File]::WriteAllText($operationsPath, $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "  Fixed operations" -ForegroundColor Green

Write-Host "`nAll Lambda handlers fixed!" -ForegroundColor Green
Write-Host "Now deploying updated Lambda functions..." -ForegroundColor Cyan

# Deploy all Lambda functions with shared module
$functions = @("discovery", "health-monitor", "cost-analyzer", "query-handler", "compliance-checker", "operations", "cloudops-generator")
$tempDir = Join-Path $env:TEMP "lambda-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

foreach ($func in $functions) {
    $functionName = "rds-$func-$Environment"
    Write-Host "`nDeploying $functionName..." -ForegroundColor Yellow
    
    $sourcePath = Join-Path $PSScriptRoot "..\lambda\$func"
    if (-not (Test-Path $sourcePath)) {
        Write-Host "  Skipping - not found" -ForegroundColor Gray
        continue
    }
    
    $deployDir = Join-Path $tempDir $functionName
    New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
    
    Copy-Item -Path "$sourcePath\*" -Destination $deployDir -Recurse -Force
    
    $sharedSource = Join-Path $PSScriptRoot "..\lambda\shared"
    $sharedDest = Join-Path $deployDir "shared"
    Copy-Item -Path $sharedSource -Destination $sharedDest -Recurse -Force
    
    $zipFile = Join-Path $tempDir "$functionName.zip"
    Compress-Archive -Path "$deployDir\*" -DestinationPath $zipFile -Force
    
    aws lambda update-function-code --function-name $functionName --zip-file "fileb://$zipFile" --output json | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Success!" -ForegroundColor Green
    } else {
        Write-Host "  Failed!" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nAll Lambda functions deployed!" -ForegroundColor Green
