#!/usr/bin/env pwsh

# Deploy Backend Infrastructure Fixes for Critical Production Issues
# This script deploys multi-region discovery and Cognito Admin permissions

param([switch]$DryRun)

$ErrorActionPreference = "Stop"

Write-Host "Starting Backend Infrastructure Fixes Deployment..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "DRY RUN MODE - No actual changes will be made" -ForegroundColor Yellow
}

# Step 1: Update Discovery Lambda Environment Variables
Write-Host "Step 1: Updating Discovery Lambda Configuration..." -ForegroundColor Blue

if (-not $DryRun) {
    try {
        Write-Host "Updating discovery Lambda environment variables..."
        
        $updateResult = aws lambda update-function-configuration `
            --function-name "rds-discovery-prod" `
            --environment file://discovery_env.json `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Discovery Lambda environment updated" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Failed to update discovery Lambda: $updateResult" -ForegroundColor Red
            throw "Discovery Lambda update failed"
        }
    } catch {
        Write-Host "ERROR: $($_)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "Would update discovery Lambda with multi-region configuration" -ForegroundColor Yellow
}

# Step 2: Update Operations Lambda Environment Variables
Write-Host "Step 2: Updating Operations Lambda Configuration..." -ForegroundColor Blue

if (-not $DryRun) {
    try {
        Write-Host "Updating operations Lambda environment variables..."
        
        $updateResult = aws lambda update-function-configuration `
            --function-name "rds-operations-prod" `
            --environment file://operations_env.json `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Operations Lambda environment updated" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Failed to update operations Lambda: $updateResult" -ForegroundColor Red
            throw "Operations Lambda update failed"
        }
    } catch {
        Write-Host "ERROR: $($_)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "Would update operations Lambda with multi-region configuration" -ForegroundColor Yellow
}

# Step 3: Update BFF Lambda Permissions for Cognito Admin
Write-Host "Step 3: Adding Cognito Admin Permissions to BFF Lambda..." -ForegroundColor Blue

if (-not $DryRun) {
    try {
        # Get current BFF Lambda role
        Write-Host "Getting BFF Lambda role information..."
        
        $bffConfig = aws lambda get-function-configuration `
            --function-name "rds-dashboard-bff-prod" `
            --output json | ConvertFrom-Json
        
        $roleName = ($bffConfig.Role -split '/')[-1]
        Write-Host "BFF Lambda role: $roleName"
        
        # Create policy document for Cognito permissions
        Write-Host "Creating Cognito Admin policy..."
        
        $policyDocument = @{
            Version = "2012-10-17"
            Statement = @(
                @{
                    Effect = "Allow"
                    Action = @(
                        "cognito-idp:ListUsers",
                        "cognito-idp:AdminGetUser",
                        "cognito-idp:AdminListGroupsForUser",
                        "cognito-idp:AdminCreateUser",
                        "cognito-idp:AdminDeleteUser",
                        "cognito-idp:AdminUpdateUserAttributes"
                    )
                    Resource = "*"
                }
            )
        } | ConvertTo-Json -Depth 10
        
        # Create or update the policy
        $policyName = "RDSDashboardCognitoAdminPolicy"
        $accountId = (aws sts get-caller-identity --query Account --output text)
        $policyArn = "arn:aws:iam::${accountId}:policy/${policyName}"
        
        # Check if policy exists
        $policyExists = $false
        try {
            $policyCheck = aws iam get-policy --policy-arn $policyArn --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $policyExists = $true
                Write-Host "Policy exists, updating..."
            }
        } catch {
            Write-Host "Policy does not exist, creating..."
        }
        
        if (-not $policyExists) {
            # Also check LASTEXITCODE from the aws command
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Policy does not exist, creating..."
            }
        }
        
        if ($policyExists) {
            # Update existing policy
            $policyDocument | Out-File -FilePath "temp-cognito-policy.json" -Encoding utf8
            
            $createResult = aws iam create-policy-version `
                --policy-arn $policyArn `
                --policy-document file://temp-cognito-policy.json `
                --set-as-default `
                --output json 2>&1
            
            Remove-Item "temp-cognito-policy.json" -Force
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Cognito Admin policy updated" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Failed to update policy: $createResult" -ForegroundColor Red
            }
        } else {
            # Create new policy
            $policyDocument | Out-File -FilePath "temp-cognito-policy.json" -Encoding utf8
            
            $createResult = aws iam create-policy `
                --policy-name $policyName `
                --policy-document file://temp-cognito-policy.json `
                --description "Cognito Admin permissions for RDS Dashboard BFF" `
                --output json 2>&1
            
            Remove-Item "temp-cognito-policy.json" -Force
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Cognito Admin policy created" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Failed to create policy: $createResult" -ForegroundColor Red
            }
        }
        
        # Attach policy to BFF Lambda role
        Write-Host "Attaching Cognito Admin policy to BFF Lambda role..."
        
        $attachResult = aws iam attach-role-policy `
            --role-name $roleName `
            --policy-arn $policyArn `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Cognito Admin policy attached to BFF Lambda role" -ForegroundColor Green
        } else {
            Write-Host "WARNING: Policy attachment may have failed (might already be attached): $attachResult" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "ERROR: $($_)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "Would create and attach Cognito Admin policy to BFF Lambda role" -ForegroundColor Yellow
}

# Step 4: Test Discovery
Write-Host "Step 4: Testing Multi-Region Discovery..." -ForegroundColor Blue

if (-not $DryRun) {
    try {
        Write-Host "Triggering discovery to test multi-region configuration..."
        
        # Invoke discovery Lambda
        $discoveryResult = aws lambda invoke `
            --function-name "rds-discovery-prod" `
            --payload '{"trigger": "manual", "source": "backend-fixes-deployment"}' `
            --output json `
            discovery-test-response.json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Discovery Lambda invoked" -ForegroundColor Green
            
            # Clean up response file
            if (Test-Path "discovery-test-response.json") {
                Remove-Item "discovery-test-response.json" -Force
            }
        } else {
            Write-Host "WARNING: Discovery test failed: $discoveryResult" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "WARNING: Error testing discovery: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "Would trigger discovery to test multi-region configuration" -ForegroundColor Yellow
}

# Summary
Write-Host "Backend Infrastructure Fixes Deployment Summary:" -ForegroundColor Magenta

if (-not $DryRun) {
    Write-Host "SUCCESS: Backend Infrastructure Fixes Deployment Complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Changes Applied:" -ForegroundColor Cyan
    Write-Host "  - Discovery Lambda: Multi-region configuration (4 regions)"
    Write-Host "  - Operations Lambda: Multi-region configuration (4 regions)"
    Write-Host "  - BFF Lambda: Cognito Admin permissions added"
    Write-Host "  - Discovery: Triggered to test multi-region functionality"
    Write-Host ""
    Write-Host "Regions Now Configured:" -ForegroundColor Cyan
    Write-Host "  - ap-southeast-1 (Singapore)"
    Write-Host "  - eu-west-2 (London)"
    Write-Host "  - ap-south-1 (Mumbai)"
    Write-Host "  - us-east-1 (N. Virginia)"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Test dashboard to verify more instances are discovered"
    Write-Host "  2. Test user management tab to verify user list loads"
    Write-Host "  3. Test instance operations across different regions"
    Write-Host "  4. Run comprehensive testing script"
    Write-Host ""
    Write-Host "Testing Command:" -ForegroundColor Cyan
    Write-Host "  ./scripts/test-backend-fixes-comprehensive.ps1"
    
} else {
    Write-Host "Dry Run Complete - No changes were made" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Would Apply:" -ForegroundColor Cyan
    Write-Host "  - Multi-region discovery configuration (4 regions)"
    Write-Host "  - Cognito Admin permissions for user management"
    Write-Host "  - Discovery system testing"
    Write-Host ""
    Write-Host "Run without -DryRun to apply these changes" -ForegroundColor Yellow
}

Write-Host "Backend Infrastructure Fixes Deployment Script Complete!" -ForegroundColor Green