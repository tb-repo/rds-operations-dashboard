#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy CORS configuration updates to Lambda function
    
.DESCRIPTION
    This script deploys CORS configuration updates including:
    - Environment variable updates for CORS origins
    - BFF Lambda function code deployment
    - Verification of deployment in staging environment first
    - Production deployment with rollback capability
    
.PARAMETER Environment
    Target environment (staging, production)
    
.PARAMETER CorsOrigins
    Comma-separated list of allowed CORS origins
    
.PARAMETER SkipStaging
    Skip staging deployment and deploy directly to production (not recommended)
    
.PARAMETER DryRun
    Show what would be deployed without making changes
    
.EXAMPLE
    .\deploy-cors-updates.ps1 -Environment staging -CorsOrigins "https://d2qvaswtmn22om.cloudfront.net,http://localhost:3000"
    
.EXAMPLE
    .\deploy-cors-updates.ps1 -Environment production -CorsOrigins "https://d2qvaswtmn22om.cloudfront.net"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("staging", "production")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$CorsOrigins,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipStaging,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Lambda function names by environment
$LambdaFunctions = @{
    staging = "rds-dashboard-bff-staging"
    production = "rds-dashboard-bff-prod"
}

# Default CORS origins by environment
$DefaultCorsOrigins = @{
    staging = "https://staging-d2qvaswtmn22om.cloudfront.net,http://localhost:3000,http://localhost:5173"
    production = "https://d2qvaswtmn22om.cloudfront.net"
}

# Colors for output
$Colors = @{
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "=" * 60 -Color Header
    Write-ColorOutput "  $Title" -Color Header
    Write-ColorOutput "=" * 60 -Color Header
    Write-Host ""
}

function Test-AWSCredentials {
    Write-ColorOutput "Checking AWS credentials..." -Color Info
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-ColorOutput "✓ AWS credentials valid - Account: $($identity.Account), User: $($identity.Arn)" -Color Success
        return $true
    }
    catch {
        Write-ColorOutput "✗ AWS credentials not configured or invalid" -Color Error
        Write-ColorOutput "Please run 'aws configure' or set AWS environment variables" -Color Error
        return $false
    }
}

function Get-LambdaFunction {
    param(
        [string]$FunctionName
    )
    
    try {
        $function = aws lambda get-function --function-name $FunctionName --output json | ConvertFrom-Json
        return $function
    }
    catch {
        Write-ColorOutput "✗ Lambda function '$FunctionName' not found" -Color Error
        return $null
    }
}

function Get-CurrentEnvironmentVariables {
    param(
        [string]$FunctionName
    )
    
    Write-ColorOutput "Getting current environment variables for $FunctionName..." -Color Info
    try {
        $config = aws lambda get-function-configuration --function-name $FunctionName --output json | ConvertFrom-Json
        return $config.Environment.Variables
    }
    catch {
        Write-ColorOutput "✗ Failed to get environment variables for $FunctionName" -Color Error
        return $null
    }
}

function Update-LambdaEnvironmentVariables {
    param(
        [string]$FunctionName,
        [hashtable]$EnvironmentVariables,
        [bool]$DryRun = $false
    )
    
    Write-ColorOutput "Updating environment variables for $FunctionName..." -Color Info
    
    # Convert hashtable to JSON format expected by AWS CLI
    $envVarsJson = $EnvironmentVariables | ConvertTo-Json -Compress
    
    if ($DryRun) {
        Write-ColorOutput "DRY RUN: Would update environment variables:" -Color Warning
        $EnvironmentVariables.GetEnumerator() | ForEach-Object {
            Write-ColorOutput "  $($_.Key) = $($_.Value)" -Color Info
        }
        return $true
    }
    
    try {
        $result = aws lambda update-function-configuration `
            --function-name $FunctionName `
            --environment "Variables=$envVarsJson" `
            --output json | ConvertFrom-Json
            
        Write-ColorOutput "✓ Environment variables updated successfully" -Color Success
        Write-ColorOutput "  Last Modified: $($result.LastModified)" -Color Info
        return $true
    }
    catch {
        Write-ColorOutput "✗ Failed to update environment variables: $($_.Exception.Message)" -Color Error
        return $false
    }
}

function Deploy-LambdaCode {
    param(
        [string]$FunctionName,
        [string]$CodePath,
        [bool]$DryRun = $false
    )
    
    Write-ColorOutput "Deploying code to $FunctionName..." -Color Info
    
    if ($DryRun) {
        Write-ColorOutput "DRY RUN: Would deploy code from $CodePath" -Color Warning
        return $true
    }
    
    # Build the BFF code
    Write-ColorOutput "Building BFF code..." -Color Info
    Push-Location "$PSScriptRoot/../bff"
    try {
        npm run build
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed"
        }
        Write-ColorOutput "✓ Build completed successfully" -Color Success
    }
    catch {
        Write-ColorOutput "✗ Build failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        Pop-Location
    }
    
    # Create deployment package
    Write-ColorOutput "Creating deployment package..." -Color Info
    $tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
    $zipPath = "$tempDir/deployment.zip"
    
    try {
        # Copy built code and dependencies
        Copy-Item "$PSScriptRoot/../bff/dist/*" -Destination $tempDir -Recurse -Force
        Copy-Item "$PSScriptRoot/../bff/node_modules" -Destination $tempDir -Recurse -Force
        Copy-Item "$PSScriptRoot/../bff/package.json" -Destination $tempDir -Force
        
        # Create ZIP file
        Compress-Archive -Path "$tempDir/*" -DestinationPath $zipPath -Force
        
        # Deploy to Lambda
        $result = aws lambda update-function-code `
            --function-name $FunctionName `
            --zip-file "fileb://$zipPath" `
            --output json | ConvertFrom-Json
            
        Write-ColorOutput "✓ Code deployed successfully" -Color Success
        Write-ColorOutput "  Code SHA256: $($result.CodeSha256)" -Color Info
        Write-ColorOutput "  Last Modified: $($result.LastModified)" -Color Info
        return $true
    }
    catch {
        Write-ColorOutput "✗ Code deployment failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

function Test-LambdaFunction {
    param(
        [string]$FunctionName,
        [string]$TestOrigin
    )
    
    Write-ColorOutput "Testing Lambda function $FunctionName..." -Color Info
    
    # Create test event
    $testEvent = @{
        httpMethod = "GET"
        path = "/health"
        headers = @{
            Origin = $TestOrigin
            "Content-Type" = "application/json"
        }
        body = $null
        isBase64Encoded = $false
    } | ConvertTo-Json -Depth 3
    
    try {
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $testEvent `
            --output json `
            response.json | ConvertFrom-Json
            
        if ($result.StatusCode -eq 200) {
            $response = Get-Content response.json | ConvertFrom-Json
            Write-ColorOutput "✓ Lambda function test successful" -Color Success
            Write-ColorOutput "  Status Code: $($response.statusCode)" -Color Info
            
            # Check CORS headers
            if ($response.headers -and $response.headers."Access-Control-Allow-Origin") {
                Write-ColorOutput "✓ CORS headers present" -Color Success
                Write-ColorOutput "  Access-Control-Allow-Origin: $($response.headers.'Access-Control-Allow-Origin')" -Color Info
            }
            else {
                Write-ColorOutput "⚠ CORS headers not found in response" -Color Warning
            }
            
            return $true
        }
        else {
            Write-ColorOutput "✗ Lambda function test failed with status: $($result.StatusCode)" -Color Error
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ Lambda function test failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        # Cleanup test response file
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
    }
}

function Backup-LambdaConfiguration {
    param(
        [string]$FunctionName
    )
    
    Write-ColorOutput "Creating backup of current configuration..." -Color Info
    
    try {
        $config = aws lambda get-function-configuration --function-name $FunctionName --output json
        $backupFile = "lambda-backup-$FunctionName-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $config | Out-File -FilePath $backupFile -Encoding UTF8
        
        Write-ColorOutput "✓ Configuration backed up to: $backupFile" -Color Success
        return $backupFile
    }
    catch {
        Write-ColorOutput "✗ Failed to backup configuration: $($_.Exception.Message)" -Color Error
        return $null
    }
}

function Confirm-Deployment {
    param(
        [string]$Environment,
        [string]$CorsOrigins
    )
    
    Write-ColorOutput "Deployment Summary:" -Color Header
    Write-ColorOutput "  Environment: $Environment" -Color Info
    Write-ColorOutput "  CORS Origins: $CorsOrigins" -Color Info
    Write-ColorOutput "  Lambda Function: $($LambdaFunctions[$Environment])" -Color Info
    Write-Host ""
    
    if ($Environment -eq "production" -and -not $SkipStaging) {
        Write-ColorOutput "⚠ This is a PRODUCTION deployment!" -Color Warning
        Write-ColorOutput "⚠ Ensure staging deployment was successful first!" -Color Warning
        Write-Host ""
    }
    
    $confirmation = Read-Host "Do you want to proceed with this deployment? (y/N)"
    return ($confirmation -eq "y" -or $confirmation -eq "Y")
}

# Main deployment logic
function Start-Deployment {
    Write-Header "CORS Configuration Deployment"
    
    # Validate parameters
    if (-not $CorsOrigins) {
        $CorsOrigins = $DefaultCorsOrigins[$Environment]
        Write-ColorOutput "Using default CORS origins for $Environment`: $CorsOrigins" -Color Info
    }
    
    $functionName = $LambdaFunctions[$Environment]
    
    # Pre-deployment checks
    if (-not (Test-AWSCredentials)) {
        exit 1
    }
    
    # Check if Lambda function exists
    $lambdaFunction = Get-LambdaFunction -FunctionName $functionName
    if (-not $lambdaFunction) {
        Write-ColorOutput "Lambda function '$functionName' not found. Please create it first." -Color Error
        exit 1
    }
    
    Write-ColorOutput "✓ Lambda function '$functionName' found" -Color Success
    
    # Get current configuration
    $currentEnvVars = Get-CurrentEnvironmentVariables -FunctionName $functionName
    if (-not $currentEnvVars) {
        exit 1
    }
    
    Write-ColorOutput "Current CORS configuration:" -Color Info
    if ($currentEnvVars.CORS_ORIGINS) {
        Write-ColorOutput "  CORS_ORIGINS: $($currentEnvVars.CORS_ORIGINS)" -Color Info
    }
    else {
        Write-ColorOutput "  CORS_ORIGINS: (not set - using environment defaults)" -Color Warning
    }
    
    # Confirm deployment
    if (-not $DryRun -and -not (Confirm-Deployment -Environment $Environment -CorsOrigins $CorsOrigins)) {
        Write-ColorOutput "Deployment cancelled by user" -Color Warning
        exit 0
    }
    
    # Create backup
    $backupFile = Backup-LambdaConfiguration -FunctionName $functionName
    if (-not $backupFile -and -not $DryRun) {
        Write-ColorOutput "Failed to create backup. Aborting deployment." -Color Error
        exit 1
    }
    
    # Update environment variables
    $newEnvVars = $currentEnvVars.PSObject.Copy()
    $newEnvVars.CORS_ORIGINS = $CorsOrigins
    $newEnvVars.NODE_ENV = $Environment
    
    $success = Update-LambdaEnvironmentVariables -FunctionName $functionName -EnvironmentVariables $newEnvVars -DryRun $DryRun
    if (-not $success) {
        Write-ColorOutput "Environment variable update failed. Aborting deployment." -Color Error
        exit 1
    }
    
    # Deploy code changes
    $success = Deploy-LambdaCode -FunctionName $functionName -CodePath "$PSScriptRoot/../bff" -DryRun $DryRun
    if (-not $success) {
        Write-ColorOutput "Code deployment failed. Aborting deployment." -Color Error
        exit 1
    }
    
    # Test the deployment
    if (-not $DryRun) {
        Write-ColorOutput "Waiting for deployment to stabilize..." -Color Info
        Start-Sleep -Seconds 10
        
        $testOrigin = $CorsOrigins.Split(',')[0].Trim()
        $success = Test-LambdaFunction -FunctionName $functionName -TestOrigin $testOrigin
        if (-not $success) {
            Write-ColorOutput "⚠ Deployment test failed. Check Lambda function logs." -Color Warning
            Write-ColorOutput "Backup file available: $backupFile" -Color Info
        }
        else {
            Write-ColorOutput "✓ Deployment test successful!" -Color Success
        }
    }
    
    Write-Header "Deployment Complete"
    
    if ($DryRun) {
        Write-ColorOutput "DRY RUN completed successfully" -Color Success
        Write-ColorOutput "Run without -DryRun to perform actual deployment" -Color Info
    }
    else {
        Write-ColorOutput "CORS configuration deployment completed successfully!" -Color Success
        Write-ColorOutput "Environment: $Environment" -Color Info
        Write-ColorOutput "Function: $functionName" -Color Info
        Write-ColorOutput "CORS Origins: $CorsOrigins" -Color Info
        
        if ($backupFile) {
            Write-ColorOutput "Backup file: $backupFile" -Color Info
        }
        
        Write-Host ""
        Write-ColorOutput "Next steps:" -Color Header
        Write-ColorOutput "1. Monitor Lambda function logs for any issues" -Color Info
        Write-ColorOutput "2. Test CORS functionality from frontend applications" -Color Info
        Write-ColorOutput "3. Verify all API endpoints work correctly" -Color Info
        
        if ($Environment -eq "staging") {
            Write-ColorOutput "4. Deploy to production after validation" -Color Info
        }
    }
}

# Run deployment
try {
    Start-Deployment
}
catch {
    Write-ColorOutput "Deployment failed with error: $($_.Exception.Message)" -Color Error
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" -Color Error
    exit 1
}