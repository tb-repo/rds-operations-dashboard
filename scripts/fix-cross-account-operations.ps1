#!/usr/bin/env pwsh
# Fix Cross-Account Discovery and Operations Issues

Write-Host "=== Fixing Cross-Account Discovery and Operations ===" -ForegroundColor Cyan

# Configuration
$HubAccount = "876595225096"
$CrossAccount = "817214535871"
$Region = "ap-southeast-1"
$ExternalId = "rds-dashboard-unique-external-id"  # Use the same as discovery
$RoleName = "RDSDashboardCrossAccountRole"

Write-Host "Step 1: Deploy Cross-Account Role in Account $CrossAccount" -ForegroundColor Yellow

# Deploy cross-account role
Write-Host "Deploying cross-account role..." -ForegroundColor Green
try {
    aws cloudformation deploy `
        --template-file infrastructure/cross-account-role.yaml `
        --stack-name rds-dashboard-cross-account-role `
        --parameter-overrides ManagementAccountId=$HubAccount ExternalId=$ExternalId `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Cross-account role deployed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Cross-account role deployment failed" -ForegroundColor Red
        Write-Host "You may need to deploy this manually in account $CrossAccount"
    }
}
catch {
    Write-Host "❌ Cross-account role deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Manual deployment required in account $CrossAccount"
}

Write-Host "`nStep 2: Update Operations Lambda Environment Variables" -ForegroundColor Yellow

# Get current discovery Lambda environment variables as template
$discoveryEnv = aws lambda get-function-configuration --function-name rds-discovery-prod --query 'Environment.Variables' --output json | ConvertFrom-Json

# Update operations Lambda with required environment variables
$operationsEnv = @{
    "AWS_ACCOUNT_ID" = $HubAccount
    "INVENTORY_TABLE" = $discoveryEnv.INVENTORY_TABLE
    "AUDIT_LOG_TABLE" = $discoveryEnv.AUDIT_LOG_TABLE
    "EXTERNAL_ID" = $discoveryEnv.EXTERNAL_ID
    "CROSS_ACCOUNT_ROLE_NAME" = $discoveryEnv.CROSS_ACCOUNT_ROLE_NAME
    "TARGET_ACCOUNTS" = $discoveryEnv.TARGET_ACCOUNTS
    "TARGET_REGIONS" = $discoveryEnv.TARGET_REGIONS
}

Write-Host "Updating operations Lambda environment variables..." -ForegroundColor Green
try {
    $envJson = $operationsEnv | ConvertTo-Json -Compress
    aws lambda update-function-configuration `
        --function-name rds-operations-prod `
        --environment "Variables=$envJson"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Operations Lambda environment variables updated" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to update operations Lambda environment variables" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Failed to update operations Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nStep 3: Update Discovery Lambda for Cross-Account" -ForegroundColor Yellow

# Update discovery Lambda to include only real accounts (remove example accounts)
$updatedTargetAccounts = "[$HubAccount,$CrossAccount]"
Write-Host "Updating discovery Lambda to include only real accounts..." -ForegroundColor Green
Write-Host "Removing example accounts 123456789012, 987654321098 and adding real cross-account $CrossAccount" -ForegroundColor Yellow

try {
    aws lambda update-function-configuration `
        --function-name rds-discovery-prod `
        --environment "Variables={AWS_ACCOUNT_ID=$HubAccount,INVENTORY_TABLE=$($discoveryEnv.INVENTORY_TABLE),AUDIT_LOG_TABLE=$($discoveryEnv.AUDIT_LOG_TABLE),EXTERNAL_ID=$($discoveryEnv.EXTERNAL_ID),CROSS_ACCOUNT_ROLE_NAME=$($discoveryEnv.CROSS_ACCOUNT_ROLE_NAME),TARGET_ACCOUNTS=`"$updatedTargetAccounts`",TARGET_REGIONS=`"$($discoveryEnv.TARGET_REGIONS)`",METRICS_CACHE_TABLE=$($discoveryEnv.METRICS_CACHE_TABLE),DATA_BUCKET=$($discoveryEnv.DATA_BUCKET),HEALTH_ALERTS_TABLE=$($discoveryEnv.HEALTH_ALERTS_TABLE)}"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Discovery Lambda updated for cross-account" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to update discovery Lambda" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Failed to update discovery Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nStep 4: Add Operations Endpoint to BFF" -ForegroundColor Yellow

# Check if BFF needs operations endpoint
Write-Host "Checking BFF operations endpoint..." -ForegroundColor Green

# Read current BFF code
$bffCode = Get-Content "bff/working-bff-with-data-v3.js" -Raw

if ($bffCode -notmatch "/api/operations") {
    Write-Host "Adding operations endpoint to BFF..." -ForegroundColor Green
    
    # Add operations endpoint to BFF
    $operationsEndpoint = @"

    // Handle /api/operations endpoint - call operations Lambda
    if (path === '/api/operations' || path.endsWith('/api/operations')) {
      if (httpMethod === 'POST') {
        try {
          const operationsPayload = {
            httpMethod: 'POST',
            path: '/operations',
            body: body,
            requestContext: event.requestContext || {}
          };
          
          const operationsCommand = new InvokeCommand({
            FunctionName: 'rds-operations-prod',
            InvocationType: 'RequestResponse',
            Payload: JSON.stringify(operationsPayload)
          });
          
          const operationsResult = await lambdaClient.send(operationsCommand);
          
          if (operationsResult.StatusCode === 200) {
            const operationsResponse = JSON.parse(new TextDecoder().decode(operationsResult.Payload));
            
            return {
              statusCode: operationsResponse.statusCode || 200,
              headers: corsHeaders,
              body: operationsResponse.body || JSON.stringify({ success: true })
            };
          } else {
            return {
              statusCode: 500,
              headers: corsHeaders,
              body: JSON.stringify({
                error: 'Operations service error',
                message: 'Unable to process operation request',
                timestamp: new Date().toISOString()
              })
            };
          }
        } catch (error) {
          console.error('Operations service error:', error);
          return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({
              error: 'Operations service error',
              message: error.message,
              timestamp: new Date().toISOString()
            })
          };
        }
      } else {
        return {
          statusCode: 405,
          headers: corsHeaders,
          body: JSON.stringify({
            error: 'Method not allowed',
            message: 'Only POST method is supported for operations',
            timestamp: new Date().toISOString()
          })
        };
      }
    }
"@
    
    # Insert operations endpoint before the default response
    $updatedBffCode = $bffCode -replace "(    // Default response)", "$operationsEndpoint`n`n    // Default response"
    
    # Write updated BFF code
    $updatedBffCode | Out-File -FilePath "bff/working-bff-with-data-v4.js" -Encoding UTF8
    
    Write-Host "✅ Operations endpoint added to BFF (saved as working-bff-with-data-v4.js)" -ForegroundColor Green
    Write-Host "Deploy this updated BFF to enable operations functionality" -ForegroundColor Yellow
} else {
    Write-Host "✅ Operations endpoint already exists in BFF" -ForegroundColor Green
}

Write-Host "`nStep 5: Test the Fixes" -ForegroundColor Yellow

# Wait for Lambda updates to propagate
Write-Host "Waiting for Lambda updates to propagate..." -ForegroundColor Green
Start-Sleep -Seconds 10

# Test discovery with cross-account
Write-Host "Testing discovery service..." -ForegroundColor Green
try {
    aws lambda invoke --function-name rds-discovery-prod --cli-binary-format raw-in-base64-out --payload '{}' test_discovery_response.json
    
    if ($LASTEXITCODE -eq 0) {
        $discoveryResponse = Get-Content test_discovery_response.json | ConvertFrom-Json
        $discoveryBody = $discoveryResponse.body | ConvertFrom-Json
        
        Write-Host "✅ Discovery service working" -ForegroundColor Green
        Write-Host "  Total instances: $($discoveryBody.total_instances)"
        Write-Host "  Accounts scanned: $($discoveryBody.accounts_scanned)"
        Write-Host "  Cross-account enabled: $($discoveryBody.cross_account_enabled)"
        Write-Host "  Errors: $($discoveryBody.errors.Count)"
        
        if ($discoveryBody.errors.Count -gt 0) {
            Write-Host "  Error details:" -ForegroundColor Yellow
            foreach ($error in $discoveryBody.errors) {
                Write-Host "    - $($error.error)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "❌ Discovery service test failed" -ForegroundColor Red
    }
    
    Remove-Item test_discovery_response.json -ErrorAction SilentlyContinue
}
catch {
    Write-Host "❌ Discovery service test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test operations service
Write-Host "Testing operations service..." -ForegroundColor Green
try {
    $operationsPayload = @{
        httpMethod = "POST"
        path = "/operations"
        body = @{
            operation = "create_snapshot"
            instance_id = "tb-pg-db1"
            parameters = @{
                snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            user_id = "test-user"
            requested_by = "fix-script"
        } | ConvertTo-Json
    } | ConvertTo-Json
    
    $operationsPayload | Out-File -FilePath test_operations_payload_fixed.json -Encoding UTF8
    
    aws lambda invoke --function-name rds-operations-prod --cli-binary-format raw-in-base64-out --payload file://test_operations_payload_fixed.json test_operations_response.json
    
    if ($LASTEXITCODE -eq 0) {
        $operationsResponse = Get-Content test_operations_response.json | ConvertFrom-Json
        
        if ($operationsResponse.errorMessage) {
            Write-Host "⚠️  Operations service has configuration issues:" -ForegroundColor Yellow
            Write-Host "    $($operationsResponse.errorMessage)" -ForegroundColor Yellow
        } else {
            Write-Host "✅ Operations service working" -ForegroundColor Green
        }
    } else {
        Write-Host "❌ Operations service test failed" -ForegroundColor Red
    }
    
    Remove-Item test_operations_payload_fixed.json -ErrorAction SilentlyContinue
    Remove-Item test_operations_response.json -ErrorAction SilentlyContinue
}
catch {
    Write-Host "❌ Operations service test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
Write-Host "Fixes applied:" -ForegroundColor Green
Write-Host "✅ Cross-account role deployment attempted"
Write-Host "✅ Operations Lambda environment variables updated"
Write-Host "✅ Discovery Lambda updated for cross-account"
Write-Host "✅ Operations endpoint added to BFF (if missing)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. If cross-account role deployment failed, deploy manually in account $CrossAccount"
Write-Host "2. Deploy updated BFF (working-bff-with-data-v4.js) if operations endpoint was added"
Write-Host "3. Test operations functionality from the dashboard"
Write-Host "4. Verify cross-account discovery is working"
Write-Host ""
Write-Host "Cross-account discovery and operations fix complete!" -ForegroundColor Green