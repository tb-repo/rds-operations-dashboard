#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Rollback CORS configuration deployment
    
.DESCRIPTION
    This script rolls back CORS configuration changes by:
    - Restoring previous environment variables from backup
    - Optionally restoring previous code version
    - Verifying rollback was successful
    
.PARAMETER Environment
    Target environment to rollback (staging, production)
    
.PARAMETER BackupFile
    Path to the backup file created during deployment
    
.PARAMETER RestoreCode
    Also restore the previous code version (requires code backup)
    
.PARAMETER Force
    Skip confirmation prompts
    
.EXAMPLE
    .\rollback-cors-deployment.ps1 -Environment staging -BackupFile "lambda-backup-rds-dashboard-bff-staging-20241231-143022.json"
    
.EXAMPLE
    .\rollback-cors-deployment.ps1 -Environment production -BackupFile "backup.json" -RestoreCode -Force
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("staging", "production")]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$RestoreCode,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Lambda function names by environment
$LambdaFunctions = @{
    staging = "rds-dashboard-bff-staging"
    production = "rds-dashboard-bff-prod"
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

function Test-BackupFile {
    param([string]$BackupFile)
    
    if (-not (Test-Path $BackupFile)) {
        Write-ColorOutput "✗ Backup file not found: $BackupFile" -Color Error
        return $false
    }
    
    try {
        $backup = Get-Content $BackupFile | ConvertFrom-Json
        if (-not $backup.Environment -or -not $backup.Environment.Variables) {
            Write-ColorOutput "✗ Invalid backup file format" -Color Error
            return $false
        }
        
        Write-ColorOutput "✓ Backup file is valid" -Color Success
        Write-ColorOutput "  Function: $($backup.FunctionName)" -Color Info
        Write-ColorOutput "  Last Modified: $($backup.LastModified)" -Color Info
        Write-ColorOutput "  Runtime: $($backup.Runtime)" -Color Info
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ Failed to parse backup file: $($_.Exception.Message)" -Color Error
        return $false
    }
}

function Get-CurrentConfiguration {
    param([string]$FunctionName)
    
    Write-ColorOutput "Getting current configuration for comparison..." -Color Info
    
    try {
        $config = aws lambda get-function-configuration --function-name $FunctionName --output json | ConvertFrom-Json
        return $config
    }
    catch {
        Write-ColorOutput "✗ Failed to get current configuration: $($_.Exception.Message)" -Color Error
        return $null
    }
}

function Restore-EnvironmentVariables {
    param(
        [string]$FunctionName,
        [string]$BackupFile
    )
    
    Write-ColorOutput "Restoring environment variables from backup..." -Color Info
    
    try {
        $backup = Get-Content $BackupFile | ConvertFrom-Json
        $envVars = $backup.Environment.Variables
        
        # Convert to hashtable for AWS CLI
        $envVarsJson = $envVars | ConvertTo-Json -Compress
        
        $result = aws lambda update-function-configuration `
            --function-name $FunctionName `
            --environment "Variables=$envVarsJson" `
            --output json | ConvertFrom-Json
            
        Write-ColorOutput "✓ Environment variables restored successfully" -Color Success
        Write-ColorOutput "  Last Modified: $($result.LastModified)" -Color Info
        
        # Show restored CORS configuration
        if ($envVars.CORS_ORIGINS) {
            Write-ColorOutput "  Restored CORS_ORIGINS: $($envVars.CORS_ORIGINS)" -Color Info
        }
        else {
            Write-ColorOutput "  CORS_ORIGINS: (not set - using environment defaults)" -Color Info
        }
        
        if ($envVars.NODE_ENV) {
            Write-ColorOutput "  Restored NODE_ENV: $($envVars.NODE_ENV)" -Color Info
        }
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ Failed to restore environment variables: $($_.Exception.Message)" -Color Error
        return $false
    }
}

function Get-PreviousCodeVersion {
    param([string]$FunctionName)
    
    Write-ColorOutput "Getting previous code versions..." -Color Info
    
    try {
        $versions = aws lambda list-versions-by-function --function-name $FunctionName --output json | ConvertFrom-Json
        
        # Get the last two versions (current and previous)
        $sortedVersions = $versions.Versions | Where-Object { $_.Version -ne '$LATEST' } | Sort-Object { [int]$_.Version } -Descending
        
        if ($sortedVersions.Count -ge 2) {
            $previousVersion = $sortedVersions[1]
            Write-ColorOutput "✓ Previous version found: $($previousVersion.Version)" -Color Success
            Write-ColorOutput "  Last Modified: $($previousVersion.LastModified)" -Color Info
            Write-ColorOutput "  Code SHA256: $($previousVersion.CodeSha256)" -Color Info
            return $previousVersion
        }
        else {
            Write-ColorOutput "⚠ No previous version available for code rollback" -Color Warning
            return $null
        }
    }
    catch {
        Write-ColorOutput "✗ Failed to get previous versions: $($_.Exception.Message)" -Color Error
        return $null
    }
}

function Restore-CodeVersion {
    param(
        [string]$FunctionName,
        [object]$PreviousVersion
    )
    
    if (-not $PreviousVersion) {
        Write-ColorOutput "⚠ No previous version to restore" -Color Warning
        return $false
    }
    
    Write-ColorOutput "Restoring code to version $($PreviousVersion.Version)..." -Color Info
    
    try {
        # Update function code to use previous version
        $result = aws lambda update-function-code `
            --function-name $FunctionName `
            --s3-bucket $PreviousVersion.Code.Location `
            --output json | ConvertFrom-Json
            
        Write-ColorOutput "✓ Code restored to previous version" -Color Success
        Write-ColorOutput "  Code SHA256: $($result.CodeSha256)" -Color Info
        Write-ColorOutput "  Last Modified: $($result.LastModified)" -Color Info
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ Failed to restore code version: $($_.Exception.Message)" -Color Error
        Write-ColorOutput "⚠ Manual code restoration may be required" -Color Warning
        return $false
    }
}

function Test-RollbackSuccess {
    param(
        [string]$FunctionName,
        [string]$BackupFile
    )
    
    Write-ColorOutput "Verifying rollback success..." -Color Info
    
    try {
        $backup = Get-Content $BackupFile | ConvertFrom-Json
        $current = aws lambda get-function-configuration --function-name $FunctionName --output json | ConvertFrom-Json
        
        # Compare environment variables
        $backupEnvVars = $backup.Environment.Variables
        $currentEnvVars = $current.Environment.Variables
        
        $envVarsMatch = $true
        
        # Check key environment variables
        $keyVars = @("CORS_ORIGINS", "NODE_ENV", "FRONTEND_URL")
        foreach ($var in $keyVars) {
            $backupValue = if ($backupEnvVars.$var) { $backupEnvVars.$var } else { "(not set)" }
            $currentValue = if ($currentEnvVars.$var) { $currentEnvVars.$var } else { "(not set)" }
            
            if ($backupValue -eq $currentValue) {
                Write-ColorOutput "✓ $var matches backup: $currentValue" -Color Success
            }
            else {
                Write-ColorOutput "✗ $var mismatch - Backup: $backupValue, Current: $currentValue" -Color Error
                $envVarsMatch = $false
            }
        }
        
        if ($envVarsMatch) {
            Write-ColorOutput "✓ Environment variables successfully restored" -Color Success
        }
        else {
            Write-ColorOutput "✗ Some environment variables don't match backup" -Color Error
        }
        
        # Test basic functionality
        Write-ColorOutput "Testing basic Lambda function..." -Color Info
        $testEvent = @{
            httpMethod = "GET"
            path = "/health"
            headers = @{}
            body = $null
            isBase64Encoded = $false
        } | ConvertTo-Json -Depth 3
        
        $result = aws lambda invoke `
            --function-name $FunctionName `
            --payload $testEvent `
            --output json `
            response.json | ConvertFrom-Json
            
        if ($result.StatusCode -eq 200) {
            Write-ColorOutput "✓ Lambda function is responding" -Color Success
        }
        else {
            Write-ColorOutput "✗ Lambda function test failed" -Color Error
            $envVarsMatch = $false
        }
        
        return $envVarsMatch
    }
    catch {
        Write-ColorOutput "✗ Rollback verification failed: $($_.Exception.Message)" -Color Error
        return $false
    }
    finally {
        if (Test-Path "response.json") {
            Remove-Item "response.json" -Force
        }
    }
}

function Confirm-Rollback {
    param(
        [string]$Environment,
        [string]$BackupFile,
        [bool]$RestoreCode
    )
    
    Write-ColorOutput "Rollback Summary:" -Color Header
    Write-ColorOutput "  Environment: $Environment" -Color Info
    Write-ColorOutput "  Lambda Function: $($LambdaFunctions[$Environment])" -Color Info
    Write-ColorOutput "  Backup File: $BackupFile" -Color Info
    Write-ColorOutput "  Restore Code: $RestoreCode" -Color Info
    Write-Host ""
    
    if ($Environment -eq "production") {
        Write-ColorOutput "⚠ This is a PRODUCTION rollback!" -Color Warning
        Write-ColorOutput "⚠ This will revert CORS configuration changes!" -Color Warning
        Write-Host ""
    }
    
    $confirmation = Read-Host "Do you want to proceed with this rollback? (y/N)"
    return ($confirmation -eq "y" -or $confirmation -eq "Y")
}

# Main rollback logic
function Start-Rollback {
    Write-Header "CORS Configuration Rollback"
    
    $functionName = $LambdaFunctions[$Environment]
    
    # Validate backup file
    if (-not (Test-BackupFile -BackupFile $BackupFile)) {
        exit 1
    }
    
    # Check AWS credentials
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-ColorOutput "✓ AWS credentials valid - Account: $($identity.Account)" -Color Success
    }
    catch {
        Write-ColorOutput "✗ AWS credentials not configured or invalid" -Color Error
        exit 1
    }
    
    # Get current configuration for comparison
    $currentConfig = Get-CurrentConfiguration -FunctionName $functionName
    if (-not $currentConfig) {
        exit 1
    }
    
    Write-ColorOutput "Current CORS configuration:" -Color Info
    if ($currentConfig.Environment.Variables.CORS_ORIGINS) {
        Write-ColorOutput "  CORS_ORIGINS: $($currentConfig.Environment.Variables.CORS_ORIGINS)" -Color Info
    }
    else {
        Write-ColorOutput "  CORS_ORIGINS: (not set)" -Color Info
    }
    
    # Get previous code version if needed
    $previousVersion = $null
    if ($RestoreCode) {
        $previousVersion = Get-PreviousCodeVersion -FunctionName $functionName
        if (-not $previousVersion) {
            Write-ColorOutput "⚠ Code rollback requested but no previous version available" -Color Warning
            $RestoreCode = $false
        }
    }
    
    # Confirm rollback
    if (-not $Force -and -not (Confirm-Rollback -Environment $Environment -BackupFile $BackupFile -RestoreCode $RestoreCode)) {
        Write-ColorOutput "Rollback cancelled by user" -Color Warning
        exit 0
    }
    
    # Create backup of current state before rollback
    Write-ColorOutput "Creating backup of current state before rollback..." -Color Info
    $preRollbackBackup = "pre-rollback-backup-$functionName-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    try {
        $currentConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $preRollbackBackup -Encoding UTF8
        Write-ColorOutput "✓ Pre-rollback backup created: $preRollbackBackup" -Color Success
    }
    catch {
        Write-ColorOutput "⚠ Failed to create pre-rollback backup: $($_.Exception.Message)" -Color Warning
    }
    
    # Restore environment variables
    $success = Restore-EnvironmentVariables -FunctionName $functionName -BackupFile $BackupFile
    if (-not $success) {
        Write-ColorOutput "Environment variable rollback failed. Aborting." -Color Error
        exit 1
    }
    
    # Restore code if requested
    if ($RestoreCode -and $previousVersion) {
        $success = Restore-CodeVersion -FunctionName $functionName -PreviousVersion $previousVersion
        if (-not $success) {
            Write-ColorOutput "⚠ Code rollback failed, but environment variables were restored" -Color Warning
        }
    }
    
    # Wait for changes to take effect
    Write-ColorOutput "Waiting for rollback to take effect..." -Color Info
    Start-Sleep -Seconds 10
    
    # Verify rollback
    $success = Test-RollbackSuccess -FunctionName $functionName -BackupFile $BackupFile
    
    Write-Header "Rollback Complete"
    
    if ($success) {
        Write-ColorOutput "✓ CORS configuration rollback completed successfully!" -Color Success
        Write-ColorOutput "Environment: $Environment" -Color Info
        Write-ColorOutput "Function: $functionName" -Color Info
        Write-ColorOutput "Backup used: $BackupFile" -Color Info
        
        if ($preRollbackBackup) {
            Write-ColorOutput "Pre-rollback backup: $preRollbackBackup" -Color Info
        }
    }
    else {
        Write-ColorOutput "⚠ Rollback completed but verification failed" -Color Warning
        Write-ColorOutput "Please check Lambda function manually" -Color Warning
    }
    
    Write-Host ""
    Write-ColorOutput "Next steps:" -Color Header
    Write-ColorOutput "1. Test CORS functionality from frontend applications" -Color Info
    Write-ColorOutput "2. Monitor Lambda function logs for any issues" -Color Info
    Write-ColorOutput "3. Verify all API endpoints work correctly" -Color Info
    Write-ColorOutput "4. Consider investigating the original deployment issue" -Color Info
}

# Run rollback
try {
    Start-Rollback
}
catch {
    Write-ColorOutput "Rollback failed with error: $($_.Exception.Message)" -Color Error
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" -Color Error
    exit 1
}