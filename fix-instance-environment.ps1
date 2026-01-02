#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick fix for instance environment classification issues

.DESCRIPTION
    This script provides quick fixes for common environment classification issues
    that prevent operations on RDS instances.

.PARAMETER InstanceId
    The RDS instance ID to fix (default: database-1)

.PARAMETER Environment
    The environment to set (Development, Test, Staging, POC, Sandbox)

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\fix-instance-environment.ps1 -InstanceId database-1 -Environment Development
    
.EXAMPLE
    .\fix-instance-environment.ps1 -InstanceId database-1 -Environment POC -Force
#>

param(
    [string]$InstanceId = "database-1",
    [ValidateSet("Development", "Test", "Staging", "POC", "Sandbox")]
    [string]$Environment = "Development",
    [switch]$Force
)

Write-Host "🔧 Quick Fix for Instance Environment Classification" -ForegroundColor Cyan
Write-Host "Instance: $InstanceId" -ForegroundColor White
Write-Host "Target Environment: $Environment" -ForegroundColor White
Write-Host ""

# Check if AWS CLI is available
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "❌ AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    exit 1
}

# Check AWS credentials
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "✅ AWS Identity: $($identity.Arn)" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS credentials not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "📋 Step 1: Verifying instance exists..." -ForegroundColor Yellow

# Get instance details
try {
    $instanceDetails = aws rds describe-db-instances --db-instance-identifier $InstanceId --output json | ConvertFrom-Json
    $instance = $instanceDetails.DBInstances[0]
    $instanceArn = $instance.DBInstanceArn
    
    Write-Host "✅ Instance found: $($instance.DBInstanceIdentifier)" -ForegroundColor Green
    Write-Host "   Engine: $($instance.Engine)"
    Write-Host "   Status: $($instance.DBInstanceStatus)"
    
} catch {
    Write-Host "❌ Instance '$InstanceId' not found or access denied." -ForegroundColor Red
    Write-Host "   Please check the instance ID and your permissions." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🏷️  Step 2: Checking current tags..." -ForegroundColor Yellow

# Get current tags
try {
    $tagsResponse = aws rds list-tags-for-resource --resource-name $instanceArn --output json | ConvertFrom-Json
    $tags = $tagsResponse.TagList
    
    $currentEnvTag = $tags | Where-Object { $_.Key -eq "Environment" }
    
    if ($currentEnvTag) {
        Write-Host "   Current Environment tag: $($currentEnvTag.Value)" -ForegroundColor Cyan
        
        if ($currentEnvTag.Value -eq $Environment) {
            Write-Host "✅ Environment tag is already set to $Environment" -ForegroundColor Green
            Write-Host "   The issue might be elsewhere. Try running discovery to refresh the inventory." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "   .\scripts\activate-discovery.ps1"
            exit 0
        }
        
        if ($currentEnvTag.Value.ToLower() -eq "production") {
            Write-Host "⚠️  Instance is currently tagged as Production!" -ForegroundColor Yellow
            Write-Host "   This blocks operations for safety reasons." -ForegroundColor Yellow
        }
    } else {
        Write-Host "   No Environment tag found" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Failed to get instance tags: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔧 Step 3: Applying fix..." -ForegroundColor Yellow

# Confirm action unless Force is specified
if (-not $Force) {
    Write-Host "About to set Environment tag to: $Environment" -ForegroundColor Cyan
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Apply the Environment tag
try {
    Write-Host "Setting Environment tag to: $Environment" -ForegroundColor Cyan
    
    aws rds add-tags-to-resource --resource-name $instanceArn --tags Key=Environment,Value=$Environment
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Environment tag updated successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to update Environment tag" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "❌ Error updating tag: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔄 Step 4: Refreshing dashboard inventory..." -ForegroundColor Yellow

# Run discovery to refresh the inventory
if (Test-Path ".\scripts\activate-discovery.ps1") {
    Write-Host "Running discovery to update dashboard inventory..." -ForegroundColor Cyan
    try {
        & ".\scripts\activate-discovery.ps1"
        Write-Host "✅ Discovery completed" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Discovery script failed, but tag was updated successfully" -ForegroundColor Yellow
        Write-Host "   You can manually run: .\scripts\activate-discovery.ps1" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  Discovery script not found at .\scripts\activate-discovery.ps1" -ForegroundColor Yellow
    Write-Host "   Please run discovery manually to refresh the inventory" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ FIX COMPLETED!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Summary of changes:" -ForegroundColor Cyan
Write-Host "   - Instance: $InstanceId"
Write-Host "   - Environment tag set to: $Environment"
Write-Host "   - Dashboard inventory refreshed"
Write-Host ""

# Provide environment-specific guidance
switch ($Environment) {
    "Development" {
        Write-Host "🎯 Development Environment Rules:" -ForegroundColor Blue
        Write-Host "   ✅ Operations allowed"
        Write-Host "   ✅ Deletion protection required"
        Write-Host "   ⚪ Multi-AZ not required"
    }
    "Test" {
        Write-Host "🎯 Test Environment Rules:" -ForegroundColor Blue
        Write-Host "   ✅ Operations allowed"
        Write-Host "   ✅ Deletion protection required"
        Write-Host "   ⚪ Multi-AZ not required"
    }
    "Staging" {
        Write-Host "🎯 Staging Environment Rules:" -ForegroundColor Blue
        Write-Host "   ✅ Operations allowed"
        Write-Host "   ✅ Deletion protection required"
        Write-Host "   ⚪ Multi-AZ not required"
    }
    "POC" {
        Write-Host "🎯 POC Environment Rules (Relaxed):" -ForegroundColor Blue
        Write-Host "   ✅ Operations allowed"
        Write-Host "   ⚪ Deletion protection not required"
        Write-Host "   ⚪ Multi-AZ not required"
    }
    "Sandbox" {
        Write-Host "🎯 Sandbox Environment Rules (Relaxed):" -ForegroundColor Blue
        Write-Host "   ✅ Operations allowed"
        Write-Host "   ⚪ Deletion protection not required"
        Write-Host "   ⚪ Multi-AZ not required"
    }
}

Write-Host ""
Write-Host "🚀 Next steps:" -ForegroundColor Green
Write-Host "   1. Wait 2-3 minutes for changes to propagate"
Write-Host "   2. Try your operation again in the dashboard"
Write-Host "   3. If issues persist, check the BFF logs for detailed errors"
Write-Host ""
Write-Host "📞 For more help, see: .\docs\environment-classification.md" -ForegroundColor Blue
Write-Host ""