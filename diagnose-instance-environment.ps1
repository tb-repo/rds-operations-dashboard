#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Diagnose environment classification issues for RDS instances

.DESCRIPTION
    This script helps diagnose why an instance is being classified as production
    and provides steps to fix the classification.

.PARAMETER InstanceId
    The RDS instance ID to diagnose (default: database-1)

.EXAMPLE
    .\diagnose-instance-environment.ps1 -InstanceId database-1
#>

param(
    [string]$InstanceId = "database-1"
)

Write-Host "🔍 Diagnosing environment classification for instance: $InstanceId" -ForegroundColor Cyan
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
Write-Host "📋 Step 1: Checking RDS instance details..." -ForegroundColor Yellow

# Get instance details
try {
    $instanceDetails = aws rds describe-db-instances --db-instance-identifier $InstanceId --output json | ConvertFrom-Json
    $instance = $instanceDetails.DBInstances[0]
    
    Write-Host "✅ Instance found:" -ForegroundColor Green
    Write-Host "   - Instance ID: $($instance.DBInstanceIdentifier)"
    Write-Host "   - Engine: $($instance.Engine)"
    Write-Host "   - Status: $($instance.DBInstanceStatus)"
    Write-Host "   - Multi-AZ: $($instance.MultiAZ)"
    Write-Host "   - Deletion Protection: $($instance.DeletionProtection)"
    
} catch {
    Write-Host "❌ Instance '$InstanceId' not found or access denied." -ForegroundColor Red
    Write-Host "   Please check:"
    Write-Host "   1. Instance ID is correct"
    Write-Host "   2. Instance exists in current region"
    Write-Host "   3. You have RDS permissions"
    exit 1
}

Write-Host ""
Write-Host "🏷️  Step 2: Checking instance tags..." -ForegroundColor Yellow

# Get instance tags
try {
    $instanceArn = $instance.DBInstanceArn
    $tagsResponse = aws rds list-tags-for-resource --resource-name $instanceArn --output json | ConvertFrom-Json
    $tags = $tagsResponse.TagList
    
    if ($tags.Count -eq 0) {
        Write-Host "⚠️  No tags found on instance!" -ForegroundColor Yellow
        Write-Host "   This means the instance will be classified using fallback rules."
    } else {
        Write-Host "✅ Tags found:" -ForegroundColor Green
        foreach ($tag in $tags) {
            $color = if ($tag.Key -eq "Environment") { "Cyan" } else { "White" }
            Write-Host "   - $($tag.Key): $($tag.Value)" -ForegroundColor $color
        }
    }
    
    # Check for Environment tag specifically
    $envTag = $tags | Where-Object { $_.Key -eq "Environment" }
    if ($envTag) {
        $envValue = $envTag.Value.ToLower()
        Write-Host ""
        Write-Host "🎯 Environment Classification: $($envTag.Value)" -ForegroundColor Cyan
        
        if ($envValue -eq "production") {
            Write-Host "❌ PROBLEM IDENTIFIED: Instance is tagged as Production!" -ForegroundColor Red
            Write-Host "   Operations are blocked on production instances for safety."
        } elseif ($envValue -in @("development", "dev", "test", "staging")) {
            Write-Host "✅ Instance is correctly tagged as non-production." -ForegroundColor Green
        } elseif ($envValue -in @("poc", "sandbox")) {
            Write-Host "✅ Instance is tagged as POC/Sandbox (relaxed rules)." -ForegroundColor Green
        } else {
            Write-Host "⚠️  Unknown environment value: $($envTag.Value)" -ForegroundColor Yellow
            Write-Host "   Will be treated as non-production."
        }
    } else {
        Write-Host ""
        Write-Host "⚠️  No Environment tag found!" -ForegroundColor Yellow
        Write-Host "   Instance will use fallback classification rules."
    }
    
} catch {
    Write-Host "❌ Failed to get instance tags: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "🔧 Step 3: Checking DynamoDB inventory..." -ForegroundColor Yellow

# Check if instance exists in DynamoDB inventory
try {
    $inventoryTable = "rds-inventory-prod"  # Adjust if different
    
    # Try to get item from DynamoDB
    $dynamoItem = aws dynamodb get-item --table-name $inventoryTable --key "{`"instance_id`": {`"S`": `"$InstanceId`"}}" --output json 2>$null | ConvertFrom-Json
    
    if ($dynamoItem.Item) {
        Write-Host "✅ Instance found in DynamoDB inventory" -ForegroundColor Green
        
        # Check tags in DynamoDB
        if ($dynamoItem.Item.tags -and $dynamoItem.Item.tags.M) {
            $dynamoTags = $dynamoItem.Item.tags.M
            Write-Host "   DynamoDB tags:"
            foreach ($tagKey in $dynamoTags.PSObject.Properties.Name) {
                $tagValue = $dynamoTags.$tagKey.S
                $color = if ($tagKey -eq "Environment") { "Cyan" } else { "White" }
                Write-Host "   - $tagKey`: $tagValue" -ForegroundColor $color
            }
            
            # Check Environment tag in DynamoDB
            if ($dynamoTags.Environment) {
                $dynamoEnv = $dynamoTags.Environment.S.ToLower()
                Write-Host ""
                Write-Host "🎯 DynamoDB Environment: $($dynamoTags.Environment.S)" -ForegroundColor Cyan
                
                if ($dynamoEnv -eq "production") {
                    Write-Host "❌ DynamoDB shows instance as Production!" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "   No tags found in DynamoDB record" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  Instance not found in DynamoDB inventory" -ForegroundColor Yellow
        Write-Host "   This could cause issues. Run discovery to update inventory."
    }
    
} catch {
    Write-Host "⚠️  Could not check DynamoDB inventory (table may not exist or no permissions)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "💡 SOLUTIONS:" -ForegroundColor Green
Write-Host ""

# Provide solutions based on findings
$envTag = $tags | Where-Object { $_.Key -eq "Environment" }
if ($envTag -and $envTag.Value.ToLower() -eq "production") {
    Write-Host "🔧 Solution 1: Change Environment tag to non-production" -ForegroundColor Yellow
    Write-Host "   If this is actually a development/test instance:"
    Write-Host ""
    Write-Host "   aws rds add-tags-to-resource \\"
    Write-Host "     --resource-name $instanceArn \\"
    Write-Host "     --tags Key=Environment,Value=Development"
    Write-Host ""
    Write-Host "🔧 Solution 2: Use CloudOps for production operations" -ForegroundColor Yellow
    Write-Host "   If this is truly a production instance, use the CloudOps feature"
    Write-Host "   to generate change requests instead of direct operations."
    
} elseif (-not $envTag) {
    Write-Host "🔧 Solution: Add Environment tag" -ForegroundColor Yellow
    Write-Host "   Add an Environment tag to properly classify the instance:"
    Write-Host ""
    Write-Host "   # For development/test instances:"
    Write-Host "   aws rds add-tags-to-resource \\"
    Write-Host "     --resource-name $instanceArn \\"
    Write-Host "     --tags Key=Environment,Value=Development"
    Write-Host ""
    Write-Host "   # For POC/sandbox instances (relaxed rules):"
    Write-Host "   aws rds add-tags-to-resource \\"
    Write-Host "     --resource-name $instanceArn \\"
    Write-Host "     --tags Key=Environment,Value=POC"
    
} else {
    Write-Host "✅ Environment tag looks correct. The issue might be elsewhere." -ForegroundColor Green
    Write-Host ""
    Write-Host "🔧 Additional troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "   1. Run discovery to refresh DynamoDB inventory:"
    Write-Host "      .\scripts\activate-discovery.ps1"
    Write-Host ""
    Write-Host "   2. Check BFF logs for detailed error messages"
    Write-Host ""
    Write-Host "   3. Verify API Gateway and Lambda permissions"
}

Write-Host ""
Write-Host "🔄 After making changes:" -ForegroundColor Cyan
Write-Host "   1. Wait 2-3 minutes for tag changes to propagate"
Write-Host "   2. Run discovery to update the dashboard inventory:"
Write-Host "      .\scripts\activate-discovery.ps1"
Write-Host "   3. Try the operation again"

Write-Host ""
Write-Host "📞 Need help? Check the environment classification guide:" -ForegroundColor Blue
Write-Host "   .\docs\environment-classification.md"
Write-Host ""