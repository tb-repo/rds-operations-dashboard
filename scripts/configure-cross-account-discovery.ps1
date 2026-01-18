# Configure Cross-Account RDS Discovery
# This script configures the discovery service to scan all organization accounts

param(
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-southeast-1",
    
    [Parameter(Mandatory=$false)]
    [string[]]$TargetAccounts = @("876595225096"),  # Add additional account IDs here
    
    [Parameter(Mandatory=$false)]
    [string]$ExternalId = "rds-dashboard-unique-external-id",
    
    [Parameter(Mandatory=$false)]
    [string]$CrossAccountRoleName = "RDSDashboardCrossAccountRole"
)

Write-Host "=== Configuring Cross-Account RDS Discovery ===" -ForegroundColor Cyan
Write-Host ""

# Get current AWS account
try {
    $currentAccount = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get current account"
    }
    Write-Host "Current AWS Account: $currentAccount" -ForegroundColor Green
} catch {
    Write-Host "❌ Error getting current AWS account: $_" -ForegroundColor Red
    exit 1
}

# Ensure current account is included in target accounts
if ($TargetAccounts -notcontains $currentAccount) {
    $TargetAccounts = @($currentAccount) + $TargetAccounts
    Write-Host "✓ Added current account to target accounts" -ForegroundColor Yellow
}

# Convert target accounts to JSON
$targetAccountsJson = $TargetAccounts | ConvertTo-Json -Compress
Write-Host "Target Accounts: $targetAccountsJson" -ForegroundColor Green

# Configure discovery service environment variables
Write-Host ""
Write-Host "Configuring discovery service..." -NoNewline

try {
    $envVars = @{
        "TARGET_ACCOUNTS" = $targetAccountsJson
        "TARGET_REGIONS" = '["ap-southeast-1"]'
        "EXTERNAL_ID" = $ExternalId
        "CROSS_ACCOUNT_ROLE_NAME" = $CrossAccountRoleName
        "INVENTORY_TABLE" = "rds-inventory-prod"
        "AUDIT_LOG_TABLE" = "audit-log-prod"
        "METRICS_CACHE_TABLE" = "metrics-cache-prod"
        "HEALTH_ALERTS_TABLE" = "health-alerts-prod"
        "DATA_BUCKET" = "rds-dashboard-data-$currentAccount-prod"
    }
    
    $envVarsJson = $envVars | ConvertTo-Json -Compress
    
    # Update discovery service function
    aws lambda update-function-configuration `
        --function-name "rds-discovery-service" `
        --environment "Variables=$envVarsJson" `
        --region $Region | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update discovery service configuration"
    }
    
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAILED]" -ForegroundColor Red
    Write-Host "❌ Error configuring discovery service: $_" -ForegroundColor Red
    exit 1
}

# Validate cross-account roles (if multiple accounts)
if ($TargetAccounts.Count -gt 1) {
    Write-Host ""
    Write-Host "Validating cross-account roles..." -ForegroundColor Yellow
    
    foreach ($accountId in $TargetAccounts) {
        if ($accountId -eq $currentAccount) {
            Write-Host "  ✓ $accountId (current account)" -ForegroundColor Green
            continue
        }
        
        Write-Host "  Checking account $accountId..." -NoNewline
        
        try {
            # Try to assume the role
            $roleArn = "arn:aws:iam::${accountId}:role/${CrossAccountRoleName}"
            
            $assumeResult = aws sts assume-role `
                --role-arn $roleArn `
                --role-session-name "rds-dashboard-validation" `
                --external-id $ExternalId `
                --duration-seconds 900 `
                --region $Region 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host " [OK]" -ForegroundColor Green
            } else {
                Write-Host " [FAILED]" -ForegroundColor Red
                Write-Host "    ❌ Cannot assume role in account $accountId" -ForegroundColor Red
                Write-Host "    Role ARN: $roleArn" -ForegroundColor Yellow
                Write-Host "    External ID: $ExternalId" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    To fix this issue:" -ForegroundColor Yellow
                Write-Host "    1. Create IAM role '$CrossAccountRoleName' in account $accountId" -ForegroundColor Yellow
                Write-Host "    2. Add trust policy allowing account $currentAccount to assume it" -ForegroundColor Yellow
                Write-Host "    3. Include ExternalId '$ExternalId' in trust policy" -ForegroundColor Yellow
                Write-Host "    4. Attach policy with rds:Describe* permissions" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " [ERROR]" -ForegroundColor Red
            Write-Host "    ❌ Error validating account $accountId`: $_" -ForegroundColor Red
        }
    }
}

# Test discovery service
Write-Host ""
Write-Host "Testing discovery service..." -NoNewline

try {
    $testResult = aws lambda invoke `
        --function-name "rds-discovery-service" `
        --payload '{}' `
        --region $Region `
        --cli-binary-format raw-in-base64-out `
        response.json 2>&1
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path "response.json")) {
        $response = Get-Content "response.json" | ConvertFrom-Json
        
        if ($response.statusCode -eq 200) {
            $body = $response.body | ConvertFrom-Json
            Write-Host " [OK]" -ForegroundColor Green
            Write-Host "  ✓ Total instances discovered: $($body.total_instances)" -ForegroundColor Green
            Write-Host "  ✓ Accounts scanned: $($body.accounts_scanned)/$($body.accounts_attempted)" -ForegroundColor Green
            Write-Host "  ✓ Regions scanned: $($body.regions_scanned)" -ForegroundColor Green
            
            if ($body.errors -and $body.errors.Count -gt 0) {
                Write-Host "  ⚠️  Errors encountered: $($body.errors.Count)" -ForegroundColor Yellow
                foreach ($error in $body.errors) {
                    Write-Host "    - $($error.error)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Host "    Discovery service returned status: $($response.statusCode)" -ForegroundColor Red
        }
        
        Remove-Item "response.json" -ErrorAction SilentlyContinue
    } else {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Host "    Failed to invoke discovery service" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "    Error testing discovery service: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Configuration Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Ensure cross-account roles are properly configured" -ForegroundColor Yellow
Write-Host "2. Deploy the updated BFF with discovery integration" -ForegroundColor Yellow
Write-Host "3. Test the /api/instances endpoint for real-time data" -ForegroundColor Yellow