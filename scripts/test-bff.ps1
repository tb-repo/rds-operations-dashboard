# Test BFF Deployment
# This script validates the BFF stack is working correctly

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod"
)

Write-Host "🧪 Testing BFF Deployment for environment: $Environment" -ForegroundColor Green
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Test-Component {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    Write-Host "Testing: $Name..." -ForegroundColor Yellow -NoNewline
    
    try {
        $result = & $Test
        if ($result) {
            Write-Host " ✅ PASS" -ForegroundColor Green
            $script:testsPassed++
            return $true
        } else {
            Write-Host " ❌ FAIL" -ForegroundColor Red
            $script:testsFailed++
            return $false
        }
    } catch {
        Write-Host " ❌ FAIL - $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
        return $false
    }
}

# Test 1: BFF Stack Exists
Test-Component "BFF Stack Exists" {
    $stack = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-BFF-$Environment" `
        --query 'Stacks[0].StackStatus' `
        --output text 2>$null
    
    return $stack -eq "CREATE_COMPLETE" -or $stack -eq "UPDATE_COMPLETE"
}

# Test 2: BFF API Gateway Exists
$bffUrl = $null
Test-Component "BFF API Gateway URL" {
    $script:bffUrl = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-BFF-$Environment" `
        --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
        --output text 2>$null
    
    return -not [string]::IsNullOrEmpty($script:bffUrl)
}

# Test 3: BFF Lambda Function Exists
Test-Component "BFF Lambda Function" {
    $function = aws lambda get-function `
        --function-name "rds-dashboard-bff-$Environment" `
        --query 'Configuration.FunctionName' `
        --output text 2>$null
    
    return -not [string]::IsNullOrEmpty($function)
}

# Test 4: Secrets Manager Secret Exists
Test-Component "Secrets Manager Secret" {
    $secret = aws secretsmanager describe-secret `
        --secret-id "rds-dashboard-api-key-$Environment" `
        --query 'Name' `
        --output text 2>$null
    
    return -not [string]::IsNullOrEmpty($secret)
}

# Test 5: Secret Contains API Key
Test-Component "Secret Contains API Key" {
    $secretValue = aws secretsmanager get-secret-value `
        --secret-id "rds-dashboard-api-key-$Environment" `
        --query 'SecretString' `
        --output text 2>$null
    
    if ([string]::IsNullOrEmpty($secretValue)) {
        return $false
    }
    
    $secret = $secretValue | ConvertFrom-Json
    return -not [string]::IsNullOrEmpty($secret.apiKey)
}

# Test 6: Lambda Has Secrets Manager Permission
Test-Component "Lambda IAM Permissions" {
    $role = aws lambda get-function `
        --function-name "rds-dashboard-bff-$Environment" `
        --query 'Configuration.Role' `
        --output text 2>$null
    
    if ([string]::IsNullOrEmpty($role)) {
        return $false
    }
    
    $roleName = $role.Split('/')[-1]
    $policies = aws iam list-attached-role-policies `
        --role-name $roleName `
        --query 'AttachedPolicies[*].PolicyName' `
        --output text 2>$null
    
    return $policies -match "SecretsManager"
}

# Test 7: BFF API Responds (OPTIONS for CORS)
if ($bffUrl) {
    Test-Component "BFF API CORS (OPTIONS)" {
        try {
            $response = Invoke-WebRequest `
                -Uri "$bffUrl/instances" `
                -Method OPTIONS `
                -Headers @{
                    "Origin" = "http://localhost:5173"
                    "Access-Control-Request-Method" = "GET"
                } `
                -UseBasicParsing `
                -ErrorAction Stop
            
            return $response.StatusCode -eq 200
        } catch {
            return $false
        }
    }
}

# Test 8: BFF API Responds (GET request)
if ($bffUrl) {
    Test-Component "BFF API GET Request" {
        try {
            $response = Invoke-WebRequest `
                -Uri "$bffUrl/instances" `
                -Method GET `
                -UseBasicParsing `
                -ErrorAction Stop
            
            return $response.StatusCode -eq 200
        } catch {
            # 403 or 401 is acceptable (means API is working, just needs auth)
            return $_.Exception.Response.StatusCode.value__ -in @(200, 401, 403)
        }
    }
}

# Test 9: Internal API Stack Exists
Test-Component "Internal API Stack" {
    $stack = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-API-$Environment" `
        --query 'Stacks[0].StackStatus' `
        --output text 2>$null
    
    return $stack -eq "CREATE_COMPLETE" -or $stack -eq "UPDATE_COMPLETE"
}

# Test 10: CloudWatch Logs Exist
Test-Component "CloudWatch Logs" {
    $logGroup = aws logs describe-log-groups `
        --log-group-name-prefix "/aws/lambda/rds-dashboard-bff-$Environment" `
        --query 'logGroups[0].logGroupName' `
        --output text 2>$null
    
    return -not [string]::IsNullOrEmpty($logGroup)
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "🎉 All tests passed! BFF is ready to use." -ForegroundColor Green
    Write-Host ""
    Write-Host "BFF API URL: $bffUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Update frontend/.env with: VITE_BFF_API_URL=$bffUrl" -ForegroundColor White
    Write-Host "2. Test locally: cd frontend && npm run dev" -ForegroundColor White
    Write-Host "3. Deploy: git push" -ForegroundColor White
    exit 0
} else {
    Write-Host "❌ Some tests failed. Please review the errors above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Check CloudWatch logs: aws logs tail /aws/lambda/rds-dashboard-bff-$Environment --follow" -ForegroundColor White
    Write-Host "2. Verify stack status: aws cloudformation describe-stacks --stack-name RDSDashboard-BFF-$Environment" -ForegroundColor White
    Write-Host "3. Re-run setup: ./scripts/setup-bff-secrets.ps1" -ForegroundColor White
    exit 1
}
