# Targeted 400 Error Diagnostic Script
# Purpose: Deep dive into the specific 400 "Request failed with status code 400" error
# Approach: Trace the exact request path and identify the failure point

param(
    [switch]$Verbose,
    [string]$TestInstanceId = "tb-pg-db1",
    [string]$TestOperation = "stop"
)

Write-Host "🎯 TARGETED 400 ERROR DIAGNOSIS" -ForegroundColor Red
Write-Host "===============================" -ForegroundColor Red
Write-Host "Tracing the exact request path causing 400 errors" -ForegroundColor Yellow
Write-Host ""

$diagnosis = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    testParameters = @{
        instanceId = $TestInstanceId
        operation = $TestOperation
    }
    requestPath = @{}
    findings = @{}
}

# =============================================================================
# STEP 1: IDENTIFY THE FRONTEND API ENDPOINT
# =============================================================================

Write-Host "🔍 STEP 1: Analyzing frontend API configuration" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

try {
    # Check frontend API configuration
    $frontendApiPath = "frontend/src/lib/api.ts"
    if (Test-Path $frontendApiPath) {
        $apiContent = Get-Content $frontendApiPath -Raw
        
        # Extract API base URL
        $baseUrlPattern = "(?:baseURL|API_BASE_URL|apiUrl)\s*[:=]\s*[`'`"]([^`'`"]+)[`'`"]"
        $baseUrlMatch = [regex]::Match($apiContent, $baseUrlPattern)
        
        if ($baseUrlMatch.Success) {
            $apiBaseUrl = $baseUrlMatch.Groups[1].Value
            $diagnosis.requestPath.frontendApiBaseUrl = $apiBaseUrl
            Write-Host "   ✅ Frontend API Base URL: $apiBaseUrl" -ForegroundColor Green
        } else {
            $diagnosis.requestPath.frontendApiBaseUrl = "NOT_FOUND"
            Write-Host "   ⚠️  Could not extract API base URL from frontend" -ForegroundColor Yellow
        }
        
        # Extract operations function
        $operationsPattern = "(?s)(async\s+function\s+\w*[Oo]peration\w*.*?}|const\s+\w*[Oo]peration\w*\s*=\s*async.*?})"
        $operationsMatch = [regex]::Match($apiContent, $operationsPattern)
        
        if ($operationsMatch.Success) {
            $operationsFunction = $operationsMatch.Value
            $diagnosis.requestPath.frontendOperationsFunction = $operationsFunction.Substring(0, [Math]::Min(500, $operationsFunction.Length))
            Write-Host "   ✅ Found operations function in frontend" -ForegroundColor Green
            
            # Extract endpoint path
            $endpointPattern = "[`'`"]([^`'`"]*operation[^`'`"]*)[`'`"]"
            $endpointMatch = [regex]::Match($operationsFunction, $endpointPattern)
            
            if ($endpointMatch.Success) {
                $operationsEndpoint = $endpointMatch.Groups[1].Value
                $diagnosis.requestPath.frontendOperationsEndpoint = $operationsEndpoint
                Write-Host "   ✅ Operations endpoint: $operationsEndpoint" -ForegroundColor Green
            }
        } else {
            $diagnosis.requestPath.frontendOperationsFunction = "NOT_FOUND"
            Write-Host "   ❌ Could not find operations function in frontend" -ForegroundColor Red
        }
        
    } else {
        $diagnosis.requestPath.frontendApiFile = "NOT_FOUND"
        Write-Host "   ❌ Frontend API file not found at $frontendApiPath" -ForegroundColor Red
    }
} catch {
    $diagnosis.requestPath.frontendAnalysisError = $_.Exception.Message
    Write-Host "   ❌ Error analyzing frontend API: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# STEP 2: IDENTIFY THE BFF ENDPOINT
# =============================================================================

Write-Host ""
Write-Host "🔍 STEP 2: Identifying BFF endpoint and configuration" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

try {
    # Find BFF Lambda functions
    $bffFunctions = aws lambda list-functions --query "Functions[?contains(FunctionName, 'bff') || contains(FunctionName, 'BFF')].{Name:FunctionName,Runtime:Runtime,Environment:Environment}" --output json 2>$null
    
    if ($bffFunctions) {
        $bffList = $bffFunctions | ConvertFrom-Json
        
        $diagnosis.requestPath.bffFunctions = @()
        
        foreach ($bff in $bffList) {
            $bffInfo = @{
                name = $bff.Name
                runtime = $bff.Runtime
                environmentVars = @{}
            }
            
            Write-Host "   📡 BFF Function: $($bff.Name)" -ForegroundColor Cyan
            
            # Check for API Gateway URL in environment variables
            if ($bff.Environment -and $bff.Environment.Variables) {
                $envVars = $bff.Environment.Variables
                
                $relevantVars = @("API_GATEWAY_URL", "BACKEND_URL", "API_BASE_URL", "OPERATIONS_API_URL")
                foreach ($var in $relevantVars) {
                    if ($envVars.$var) {
                        $bffInfo.environmentVars[$var] = $envVars.$var
                        Write-Host "      ✅ $var = $($envVars.$var)" -ForegroundColor Green
                    }
                }
            }
            
            $diagnosis.requestPath.bffFunctions += $bffInfo
        }
        
        Write-Host "   📊 Found $($bffList.Count) BFF functions" -ForegroundColor Green
    } else {
        $diagnosis.requestPath.bffFunctions = @()
        Write-Host "   ❌ No BFF functions found" -ForegroundColor Red
    }
} catch {
    $diagnosis.requestPath.bffAnalysisError = $_.Exception.Message
    Write-Host "   ❌ Error analyzing BFF functions: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# STEP 3: IDENTIFY API GATEWAY CONFIGURATION
# =============================================================================

Write-Host ""
Write-Host "🔍 STEP 3: Analyzing API Gateway routing" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    # Get API Gateway APIs
    $apiList = aws apigateway get-rest-apis --query "items[?contains(name, 'rds') || contains(name, 'dashboard')].{id:id,name:name}" --output json 2>$null
    
    if ($apiList) {
        $apis = $apiList | ConvertFrom-Json
        
        $diagnosis.requestPath.apiGateways = @()
        
        foreach ($api in $apis) {
            Write-Host "   🌐 API Gateway: $($api.name) ($($api.id))" -ForegroundColor Cyan
            
            $apiInfo = @{
                id = $api.id
                name = $api.name
                url = "https://$($api.id).execute-api.ap-southeast-1.amazonaws.com/prod"
                operationsRoutes = @()
            }
            
            # Get resources for operations
            $resources = aws apigateway get-resources --rest-api-id $api.id --output json 2>$null
            
            if ($resources) {
                $resourceList = $resources | ConvertFrom-Json
                
                foreach ($resource in $resourceList.items) {
                    if ($resource.pathPart -match "operation" -or $resource.path -match "operation") {
                        $routeInfo = @{
                            path = $resource.path
                            pathPart = $resource.pathPart
                            methods = @()
                        }
                        
                        if ($resource.resourceMethods) {
                            $routeInfo.methods = $resource.resourceMethods | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
                        }
                        
                        $apiInfo.operationsRoutes += $routeInfo
                        Write-Host "      ✅ Operations route: $($resource.path) [$($routeInfo.methods -join ', ')]" -ForegroundColor Green
                    }
                }
            }
            
            $diagnosis.requestPath.apiGateways += $apiInfo
            Write-Host "      📡 API URL: $($apiInfo.url)" -ForegroundColor Gray
        }
    } else {
        $diagnosis.requestPath.apiGateways = @()
        Write-Host "   ❌ No API Gateway APIs found" -ForegroundColor Red
    }
} catch {
    $diagnosis.requestPath.apiGatewayAnalysisError = $_.Exception.Message
    Write-Host "   ❌ Error analyzing API Gateway: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# STEP 4: IDENTIFY OPERATIONS LAMBDA FUNCTION
# =============================================================================

Write-Host ""
Write-Host "🔍 STEP 4: Analyzing Operations Lambda function" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

try {
    # Find operations Lambda functions
    $operationsLambdas = aws lambda list-functions --query "Functions[?contains(FunctionName, 'operation')].{Name:FunctionName,Runtime:Runtime,Environment:Environment,LastModified:LastModified}" --output json 2>$null
    
    if ($operationsLambdas) {
        $opsList = $operationsLambdas | ConvertFrom-Json
        
        $diagnosis.requestPath.operationsLambdas = @()
        
        foreach ($ops in $opsList) {
            $opsInfo = @{
                name = $ops.Name
                runtime = $ops.Runtime
                lastModified = $ops.LastModified
                environmentVars = @{}
            }
            
            Write-Host "   ⚙️  Operations Lambda: $($ops.Name)" -ForegroundColor Cyan
            Write-Host "      Runtime: $($ops.Runtime)" -ForegroundColor Gray
            Write-Host "      Last Modified: $($ops.LastModified)" -ForegroundColor Gray
            
            # Check critical environment variables
            if ($ops.Environment -and $ops.Environment.Variables) {
                $envVars = $ops.Environment.Variables
                
                $criticalVars = @("AWS_ACCOUNT_ID", "INVENTORY_TABLE", "AUDIT_LOG_TABLE")
                foreach ($var in $criticalVars) {
                    if ($envVars.$var) {
                        $opsInfo.environmentVars[$var] = $envVars.$var
                        Write-Host "      ✅ $var = $($envVars.$var)" -ForegroundColor Green
                    } else {
                        $opsInfo.environmentVars[$var] = "MISSING"
                        Write-Host "      ❌ $var = MISSING" -ForegroundColor Red
                    }
                }
            }
            
            $diagnosis.requestPath.operationsLambdas += $opsInfo
        }
        
        Write-Host "   📊 Found $($opsList.Count) operations Lambda functions" -ForegroundColor Green
    } else {
        $diagnosis.requestPath.operationsLambdas = @()
        Write-Host "   ❌ No operations Lambda functions found" -ForegroundColor Red
    }
} catch {
    $diagnosis.requestPath.operationsLambdaAnalysisError = $_.Exception.Message
    Write-Host "   ❌ Error analyzing operations Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# STEP 5: TEST DIRECT API CALLS
# =============================================================================

Write-Host ""
Write-Host "🔍 STEP 5: Testing direct API calls to isolate 400 error source" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Generate test instructions based on discovered endpoints
$testInstructions = @()

if ($diagnosis.requestPath.apiGateways -and $diagnosis.requestPath.apiGateways.Count -gt 0) {
    foreach ($api in $diagnosis.requestPath.apiGateways) {
        if ($api.operationsRoutes -and $api.operationsRoutes.Count -gt 0) {
            foreach ($route in $api.operationsRoutes) {
                $testUrl = "$($api.url)$($route.path)"
                $testInstructions += @{
                    description = "Test operations endpoint via API Gateway"
                    method = "POST"
                    url = $testUrl
                    headers = @{
                        "Content-Type" = "application/json"
                        "Authorization" = "Bearer YOUR_JWT_TOKEN"
                    }
                    body = @{
                        instanceId = $TestInstanceId
                        operation = $TestOperation
                        region = "ap-southeast-1"
                    }
                    expectedResponse = "200 OK or specific error message"
                }
            }
        }
    }
}

if ($diagnosis.requestPath.operationsLambdas -and $diagnosis.requestPath.operationsLambdas.Count -gt 0) {
    foreach ($lambda in $diagnosis.requestPath.operationsLambdas) {
        $testInstructions += @{
            description = "Test operations Lambda directly"
            method = "AWS CLI"
            command = "aws lambda invoke --function-name $($lambda.name) --payload '{\"instanceId\":\"$TestInstanceId\",\"operation\":\"$TestOperation\",\"region\":\"ap-southeast-1\",\"userIdentity\":{\"sub\":\"test-user\"}}' response.json"
            expectedResponse = "200 status code or specific error in response.json"
        }
    }
}

$diagnosis.findings.testInstructions = $testInstructions

Write-Host "   📋 Generated $($testInstructions.Count) test scenarios:" -ForegroundColor Green

foreach ($i in 0..($testInstructions.Count - 1)) {
    $test = $testInstructions[$i]
    Write-Host "      $($i + 1). $($test.description)" -ForegroundColor Cyan
    
    if ($test.method -eq "POST") {
        Write-Host "         Method: $($test.method)" -ForegroundColor Gray
        Write-Host "         URL: $($test.url)" -ForegroundColor Gray
        Write-Host "         Body: $($test.body | ConvertTo-Json -Compress)" -ForegroundColor Gray
    } elseif ($test.method -eq "AWS CLI") {
        Write-Host "         Command: $($test.command)" -ForegroundColor Gray
    }
    
    Write-Host "         Expected: $($test.expectedResponse)" -ForegroundColor Gray
    Write-Host ""
}

# =============================================================================
# STEP 6: ANALYZE REQUEST FLOW AND IDENTIFY LIKELY FAILURE POINTS
# =============================================================================

Write-Host ""
Write-Host "🔍 STEP 6: Request flow analysis and failure point identification" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$flowAnalysis = @{
    expectedFlow = @(
        "1. Frontend (React) → API call with user JWT token",
        "2. API Gateway → Routes request to BFF Lambda",
        "3. BFF Lambda → Validates JWT, extracts user identity",
        "4. BFF Lambda → Calls Operations Lambda with user context",
        "5. Operations Lambda → Validates user identity, performs RDS operation",
        "6. Response flows back through the chain"
    )
    likelyFailurePoints = @()
    recommendations = @()
}

# Analyze potential failure points based on evidence
if (-not $diagnosis.requestPath.frontendApiBaseUrl -or $diagnosis.requestPath.frontendApiBaseUrl -eq "NOT_FOUND") {
    $flowAnalysis.likelyFailurePoints += "Frontend API configuration missing or incorrect"
    $flowAnalysis.recommendations += "Fix frontend API base URL configuration"
}

if (-not $diagnosis.requestPath.bffFunctions -or $diagnosis.requestPath.bffFunctions.Count -eq 0) {
    $flowAnalysis.likelyFailurePoints += "No BFF Lambda functions found - critical missing component"
    $flowAnalysis.recommendations += "CRITICAL: Deploy BFF Lambda function"
}

if (-not $diagnosis.requestPath.apiGateways -or $diagnosis.requestPath.apiGateways.Count -eq 0) {
    $flowAnalysis.likelyFailurePoints += "No API Gateway found - critical missing component"
    $flowAnalysis.recommendations += "CRITICAL: Set up API Gateway with proper routing"
}

if (-not $diagnosis.requestPath.operationsLambdas -or $diagnosis.requestPath.operationsLambdas.Count -eq 0) {
    $flowAnalysis.likelyFailurePoints += "No Operations Lambda functions found - critical missing component"
    $flowAnalysis.recommendations += "CRITICAL: Deploy Operations Lambda function"
}

# Check for configuration issues
$hasConfigIssues = $false
if ($diagnosis.requestPath.operationsLambdas) {
    foreach ($lambda in $diagnosis.requestPath.operationsLambdas) {
        foreach ($var in @("AWS_ACCOUNT_ID", "INVENTORY_TABLE", "AUDIT_LOG_TABLE")) {
            if ($lambda.environmentVars[$var] -eq "MISSING") {
                $flowAnalysis.likelyFailurePoints += "Operations Lambda missing environment variable: $var"
                $flowAnalysis.recommendations += "Configure environment variable $var in $($lambda.name)"
                $hasConfigIssues = $true
            }
        }
    }
}

if ($diagnosis.requestPath.apiGateways) {
    $hasOperationsRoutes = $false
    foreach ($api in $diagnosis.requestPath.apiGateways) {
        if ($api.operationsRoutes -and $api.operationsRoutes.Count -gt 0) {
            $hasOperationsRoutes = $true
            break
        }
    }
    
    if (-not $hasOperationsRoutes) {
        $flowAnalysis.likelyFailurePoints += "API Gateway has no operations routes configured"
        $flowAnalysis.recommendations += "Configure operations routes in API Gateway"
    }
}

$diagnosis.findings.flowAnalysis = $flowAnalysis

Write-Host "   🔄 Expected Request Flow:" -ForegroundColor Green
foreach ($step in $flowAnalysis.expectedFlow) {
    Write-Host "      $step" -ForegroundColor Gray
}

Write-Host ""
Write-Host "   ⚠️  Likely Failure Points:" -ForegroundColor Yellow
foreach ($failure in $flowAnalysis.likelyFailurePoints) {
    Write-Host "      ❌ $failure" -ForegroundColor Red
}

Write-Host ""
Write-Host "   🎯 Targeted Recommendations:" -ForegroundColor Green
foreach ($i in 0..($flowAnalysis.recommendations.Count - 1)) {
    Write-Host "      $($i + 1). $($flowAnalysis.recommendations[$i])" -ForegroundColor White
}

# =============================================================================
# SUMMARY AND NEXT STEPS
# =============================================================================

Write-Host ""
Write-Host "📊 400 ERROR DIAGNOSIS SUMMARY" -ForegroundColor Magenta
Write-Host "==============================" -ForegroundColor Magenta

$criticalIssues = $flowAnalysis.recommendations | Where-Object { $_ -match "CRITICAL" }
$configIssues = $flowAnalysis.recommendations | Where-Object { $_ -match "Configure" }
$otherIssues = $flowAnalysis.recommendations | Where-Object { $_ -notmatch "CRITICAL" -and $_ -notmatch "Configure" }

Write-Host "🚨 Critical Issues (Fix First): $($criticalIssues.Count)" -ForegroundColor Red
Write-Host "⚙️  Configuration Issues: $($configIssues.Count)" -ForegroundColor Yellow  
Write-Host "🔧 Other Issues: $($otherIssues.Count)" -ForegroundColor Cyan

Write-Host ""
Write-Host "🎯 IMMEDIATE NEXT STEPS:" -ForegroundColor Yellow

if ($criticalIssues.Count -gt 0) {
    Write-Host "   1. Address critical missing components first:" -ForegroundColor Red
    foreach ($issue in $criticalIssues) {
        Write-Host "      - $issue" -ForegroundColor White
    }
}

if ($testInstructions.Count -gt 0) {
    Write-Host "   2. Run manual API tests to confirm failure points:" -ForegroundColor Yellow
    Write-Host "      - Use the test scenarios generated above" -ForegroundColor White
    Write-Host "      - Capture exact error messages and HTTP status codes" -ForegroundColor White
    Write-Host "      - Test each layer independently" -ForegroundColor White
}

if ($configIssues.Count -gt 0) {
    Write-Host "   3. Fix configuration issues:" -ForegroundColor Cyan
    foreach ($issue in $configIssues) {
        Write-Host "      - $issue" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "💡 This targeted diagnosis provides specific, evidence-based next steps" -ForegroundColor Green
Write-Host "   instead of generic 'comprehensive fixes' that haven't worked before." -ForegroundColor Green
Write-Host ""

# Save diagnosis results
$diagnosisFile = "400-error-diagnosis-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$diagnosis | ConvertTo-Json -Depth 10 | Out-File -FilePath $diagnosisFile -Encoding UTF8
Write-Host "📁 Detailed diagnosis saved to: $diagnosisFile" -ForegroundColor Green