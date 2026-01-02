#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Simple Missing API Endpoints Diagnostic
    
.DESCRIPTION
    Diagnoses missing API endpoints with simplified approach
    
.PARAMETER Region
    AWS region to check (default: ap-southeast-1)
#>

param(
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Missing API Endpoints Diagnostic ===" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host ""

# Initialize results
$results = @{
    Issues = @()
    Recommendations = @()
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
    $results.Issues += $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

# 1. Check BFF Lambda Function
Write-Host "--- Checking BFF Lambda Function ---" -ForegroundColor Yellow

try {
    $bffFunctions = aws lambda list-functions --region $Region --output json 2>$null | ConvertFrom-Json
    $bffFunction = $bffFunctions.Functions | Where-Object { $_.FunctionName -like "*bff*" -or $_.FunctionName -like "*BFF*" }
    
    if ($bffFunction) {
        Write-Success "Found BFF function: $($bffFunction.FunctionName)"
        
        # Check environment variables
        $config = aws lambda get-function-configuration --function-name $bffFunction.FunctionName --region $Region --output json 2>$null | ConvertFrom-Json
        if ($config.Environment.Variables.INTERNAL_API_URL) {
            Write-Success "BFF has INTERNAL_API_URL: $($config.Environment.Variables.INTERNAL_API_URL)"
            $internalApiUrl = $config.Environment.Variables.INTERNAL_API_URL
        } else {
            Write-Error "BFF missing INTERNAL_API_URL environment variable"
        }
    } else {
        Write-Error "No BFF Lambda function found"
    }
} catch {
    Write-Error "Failed to check BFF: $($_.Exception.Message)"
}

# 2. Check API Gateway
Write-Host "`n--- Checking API Gateway ---" -ForegroundColor Yellow

try {
    $apis = aws apigateway get-rest-apis --region $Region --output json 2>$null | ConvertFrom-Json
    $rdsApi = $apis.items | Where-Object { $_.name -like "*rds*" -or $_.name -like "*dashboard*" }
    
    if ($rdsApi) {
        Write-Success "Found API Gateway: $($rdsApi.name) (ID: $($rdsApi.id))"
        
        # Check routes
        $resources = aws apigateway get-resources --rest-api-id $rdsApi.id --region $Region --output json 2>$null | ConvertFrom-Json
        $criticalPaths = @("instances", "compliance", "costs")
        
        foreach ($path in $criticalPaths) {
            $route = $resources.items | Where-Object { $_.pathPart -eq $path }
            if ($route) {
                Write-Success "Found route: /$path"
            } else {
                Write-Error "Missing route: /$path"
            }
        }
    } else {
        Write-Error "No API Gateway found for RDS Dashboard"
    }
} catch {
    Write-Error "Failed to check API Gateway: $($_.Exception.Message)"
}

# 3. Check Backend Lambda Functions
Write-Host "`n--- Checking Backend Lambda Functions ---" -ForegroundColor Yellow

$expectedLambdas = @("query-handler", "compliance-checker", "cost-analyzer")

try {
    $allLambdas = aws lambda list-functions --region $Region --output json 2>$null | ConvertFrom-Json
    
    foreach ($expectedLambda in $expectedLambdas) {
        $foundLambda = $allLambdas.Functions | Where-Object { $_.FunctionName -like "*$expectedLambda*" }
        
        if ($foundLambda) {
            Write-Success "Found Lambda: $($foundLambda.FunctionName)"
            
            # Test basic invocation
            try {
                $testPayload = '{"httpMethod":"GET","path":"/health"}'
                $testResult = aws lambda invoke --function-name $foundLambda.FunctionName --payload $testPayload --region $Region test-response.json 2>$null
                
                if (Test-Path "test-response.json") {
                    $response = Get-Content "test-response.json" -Raw | ConvertFrom-Json
                    if ($response.statusCode) {
                        Write-Success "Lambda $expectedLambda responds (Status: $($response.statusCode))"
                    } else {
                        Write-Warning "Lambda $expectedLambda response unclear"
                    }
                    Remove-Item "test-response.json" -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Warning "Could not test Lambda $expectedLambda"
            }
        } else {
            Write-Error "Missing Lambda function: $expectedLambda"
            $results.Recommendations += "Deploy missing Lambda function: $expectedLambda"
        }
    }
} catch {
    Write-Error "Failed to check Lambda functions: $($_.Exception.Message)"
}

# 4. Check DynamoDB Tables
Write-Host "`n--- Checking DynamoDB Tables ---" -ForegroundColor Yellow

$expectedTables = @("rds-inventory-prod", "cost-snapshots-prod", "rds_compliance")

foreach ($tableName in $expectedTables) {
    try {
        $tableInfo = aws dynamodb describe-table --table-name $tableName --region $Region --output json 2>$null | ConvertFrom-Json
        if ($tableInfo) {
            Write-Success "Found table: $tableName (Status: $($tableInfo.Table.TableStatus))"
        } else {
            Write-Error "Missing table: $tableName"
            $results.Recommendations += "Create missing DynamoDB table: $tableName"
        }
    } catch {
        Write-Error "Table $tableName not accessible or missing"
        $results.Recommendations += "Create or fix access to DynamoDB table: $tableName"
    }
}

# 5. Test API Endpoints (if we have the URL)
if ($internalApiUrl) {
    Write-Host "`n--- Testing API Endpoints ---" -ForegroundColor Yellow
    
    $testEndpoints = @("instances", "compliance", "costs")
    
    foreach ($endpoint in $testEndpoints) {
        try {
            $response = Invoke-WebRequest -Uri "$internalApiUrl/$endpoint" -Method GET -TimeoutSec 10 -ErrorAction Stop
            Write-Success "Endpoint /$endpoint returned: $($response.StatusCode)"
        } catch {
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode } else { "Error" }
            Write-Error "Endpoint /$endpoint failed: $statusCode"
        }
    }
}

# Summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan

if ($results.Issues.Count -eq 0) {
    Write-Host "✅ No critical issues found!" -ForegroundColor Green
} else {
    Write-Host "❌ Issues Found:" -ForegroundColor Red
    foreach ($issue in $results.Issues) {
        Write-Host "  • $issue" -ForegroundColor Red
    }
}

if ($results.Recommendations.Count -gt 0) {
    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    foreach ($rec in $results.Recommendations) {
        Write-Host "  • $rec" -ForegroundColor Yellow
    }
}

Write-Host "`n=== NEXT STEPS ===" -ForegroundColor White
Write-Host "1. Deploy missing Lambda functions" -ForegroundColor Gray
Write-Host "2. Create missing DynamoDB tables" -ForegroundColor Gray
Write-Host "3. Configure API Gateway routes" -ForegroundColor Gray
Write-Host "4. Test endpoints after deployment" -ForegroundColor Gray

# Save results
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "diagnostic-results-$timestamp.json"
$results | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host "`nResults saved to: $outputFile" -ForegroundColor Cyan