# Forensic Analysis Script - Evidence-Based Root Cause Investigation
# Purpose: Systematically diagnose the actual state of all 3 critical issues
# Approach: Test each component independently, capture evidence, identify root causes

param(
    [switch]$Verbose,
    [switch]$SaveEvidence,
    [string]$OutputDir = "forensic-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

Write-Host "🔍 FORENSIC ANALYSIS - CRITICAL PRODUCTION ISSUES" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Approach: Evidence-based diagnosis, not assumption-based fixes" -ForegroundColor Yellow
Write-Host ""

# Create evidence directory
if ($SaveEvidence) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "📁 Evidence will be saved to: $OutputDir" -ForegroundColor Green
}

$evidence = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    issues = @{}
    infrastructure = @{}
    recommendations = @{}
}

# =============================================================================
# ISSUE 1: INSTANCE OPERATIONS 400 ERRORS - FORENSIC ANALYSIS
# =============================================================================

Write-Host "🚨 ISSUE 1: Instance Operations 400 Errors" -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red

$issue1 = @{
    description = "Instance operations failing with 400 'Request failed with status code 400'"
    tests = @{}
    rootCause = $null
    evidence = @{}
}

# Test 1.1: Frontend API Call Structure
Write-Host "🔍 Test 1.1: Analyzing frontend API call structure..." -ForegroundColor Yellow

try {
    # Check if frontend API file exists and analyze operations calls
    $frontendApiPath = "frontend/src/lib/api.ts"
    if (Test-Path $frontendApiPath) {
        $apiContent = Get-Content $frontendApiPath -Raw
        
        # Look for operations-related functions
        $operationsPattern = "(?s)(async\s+\w*[Oo]peration\w*.*?})"
        $operationsMatches = [regex]::Matches($apiContent, $operationsPattern)
        
        $issue1.evidence.frontendApiStructure = @{
            fileExists = $true
            operationsFunctions = $operationsMatches.Count
            functions = @()
        }
        
        foreach ($match in $operationsMatches) {
            $issue1.evidence.frontendApiStructure.functions += $match.Value.Substring(0, [Math]::Min(200, $match.Value.Length))
        }
        
        Write-Host "   ✅ Frontend API file found with $($operationsMatches.Count) operation functions" -ForegroundColor Green
    } else {
        $issue1.evidence.frontendApiStructure = @{
            fileExists = $false
            error = "Frontend API file not found at $frontendApiPath"
        }
        Write-Host "   ❌ Frontend API file not found" -ForegroundColor Red
    }
} catch {
    $issue1.evidence.frontendApiStructure = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error analyzing frontend API: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 1.2: BFF Function Analysis
Write-Host "🔍 Test 1.2: Analyzing BFF function deployment and configuration..." -ForegroundColor Yellow

try {
    # Check for BFF functions
    $bffFunctions = @()
    
    # Look for BFF-related Lambda functions
    $lambdaList = aws lambda list-functions --query "Functions[?contains(FunctionName, 'bff') || contains(FunctionName, 'BFF')].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}" --output json 2>$null
    
    if ($lambdaList) {
        $bffFunctions = $lambdaList | ConvertFrom-Json
        
        $issue1.evidence.bffFunctions = @{
            count = $bffFunctions.Count
            functions = $bffFunctions
        }
        
        Write-Host "   ✅ Found $($bffFunctions.Count) BFF functions:" -ForegroundColor Green
        foreach ($func in $bffFunctions) {
            Write-Host "      - $($func.Name) ($($func.Runtime)) - Modified: $($func.LastModified)" -ForegroundColor Cyan
        }
    } else {
        $issue1.evidence.bffFunctions = @{
            count = 0
            error = "No BFF functions found or AWS CLI error"
        }
        Write-Host "   ❌ No BFF functions found" -ForegroundColor Red
    }
} catch {
    $issue1.evidence.bffFunctions = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking BFF functions: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 1.3: API Gateway Configuration
Write-Host "🔍 Test 1.3: Analyzing API Gateway routing for operations..." -ForegroundColor Yellow

try {
    # Get API Gateway APIs
    $apiList = aws apigateway get-rest-apis --query "items[?contains(name, 'rds') || contains(name, 'dashboard')].{id:id,name:name}" --output json 2>$null
    
    if ($apiList) {
        $apis = $apiList | ConvertFrom-Json
        
        $issue1.evidence.apiGateway = @{
            apis = $apis
            operationsRoutes = @()
        }
        
        foreach ($api in $apis) {
            Write-Host "   📡 Checking API: $($api.name) ($($api.id))" -ForegroundColor Cyan
            
            # Get resources for this API
            $resources = aws apigateway get-resources --rest-api-id $api.id --query "items[?contains(pathPart, 'operation') || contains(path, 'operation')].{path:path,methods:resourceMethods}" --output json 2>$null
            
            if ($resources) {
                $operationsRoutes = $resources | ConvertFrom-Json
                $issue1.evidence.apiGateway.operationsRoutes += @{
                    apiId = $api.id
                    apiName = $api.name
                    routes = $operationsRoutes
                }
                
                if ($operationsRoutes.Count -gt 0) {
                    Write-Host "      ✅ Found $($operationsRoutes.Count) operations routes" -ForegroundColor Green
                } else {
                    Write-Host "      ⚠️  No operations routes found" -ForegroundColor Yellow
                }
            }
        }
    } else {
        $issue1.evidence.apiGateway = @{
            error = "No APIs found or AWS CLI error"
        }
        Write-Host "   ❌ No API Gateway APIs found" -ForegroundColor Red
    }
} catch {
    $issue1.evidence.apiGateway = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking API Gateway: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 1.4: Operations Lambda Function Analysis
Write-Host "🔍 Test 1.4: Analyzing Operations Lambda function..." -ForegroundColor Yellow

try {
    # Look for operations Lambda functions
    $operationsLambdas = aws lambda list-functions --query "Functions[?contains(FunctionName, 'operation')].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified,Environment:Environment}" --output json 2>$null
    
    if ($operationsLambdas) {
        $opsLambdas = $operationsLambdas | ConvertFrom-Json
        
        $issue1.evidence.operationsLambdas = @{
            count = $opsLambdas.Count
            functions = $opsLambdas
        }
        
        Write-Host "   ✅ Found $($opsLambdas.Count) operations Lambda functions:" -ForegroundColor Green
        foreach ($func in $opsLambdas) {
            Write-Host "      - $($func.Name) ($($func.Runtime)) - Modified: $($func.LastModified)" -ForegroundColor Cyan
            
            # Check environment variables
            if ($func.Environment -and $func.Environment.Variables) {
                $envVars = $func.Environment.Variables | Get-Member -MemberType NoteProperty | Measure-Object
                Write-Host "        Environment variables: $($envVars.Count)" -ForegroundColor Gray
            }
        }
    } else {
        $issue1.evidence.operationsLambdas = @{
            count = 0
            error = "No operations Lambda functions found"
        }
        Write-Host "   ❌ No operations Lambda functions found" -ForegroundColor Red
    }
} catch {
    $issue1.evidence.operationsLambdas = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking operations Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 1.5: Direct API Test (if possible)
Write-Host "🔍 Test 1.5: Testing direct API calls to identify 400 error source..." -ForegroundColor Yellow

# This would require knowing the exact API endpoint and authentication
# For now, we'll document what needs to be tested
$issue1.evidence.directApiTest = @{
    status = "requires_manual_testing"
    instructions = @(
        "1. Identify the exact API endpoint for operations (from API Gateway or frontend)",
        "2. Capture the exact request payload being sent by frontend",
        "3. Test the API endpoint directly with curl/Postman",
        "4. Compare request format with what Lambda expects",
        "5. Check authentication headers and user identity passing"
    )
}

Write-Host "   ⚠️  Direct API testing requires manual intervention with specific endpoints" -ForegroundColor Yellow

$issue1.tests = @{
    frontendApiStructure = if ($issue1.evidence.frontendApiStructure.fileExists) { "PASS" } else { "FAIL" }
    bffFunctions = if ($issue1.evidence.bffFunctions.count -gt 0) { "PASS" } else { "FAIL" }
    apiGateway = if ($issue1.evidence.apiGateway.apis) { "PASS" } else { "FAIL" }
    operationsLambdas = if ($issue1.evidence.operationsLambdas.count -gt 0) { "PASS" } else { "FAIL" }
    directApiTest = "MANUAL_REQUIRED"
}

$evidence.issues.issue1_operations_400_errors = $issue1

# =============================================================================
# ISSUE 2: CROSS-ACCOUNT DISCOVERY - FORENSIC ANALYSIS
# =============================================================================

Write-Host ""
Write-Host "🚨 ISSUE 2: Cross-Account Discovery" -ForegroundColor Red
Write-Host "===================================" -ForegroundColor Red

$issue2 = @{
    description = "Cross-account instances not visible on dashboard (account 817214535871)"
    tests = @{}
    rootCause = $null
    evidence = @{}
}

# Test 2.1: Cross-Account Role Existence
Write-Host "🔍 Test 2.1: Checking cross-account role existence..." -ForegroundColor Yellow

try {
    # Check if cross-account role exists in secondary account
    # Note: This requires switching to the secondary account or having cross-account permissions
    
    $issue2.evidence.crossAccountRole = @{
        status = "requires_manual_verification"
        targetAccount = "817214535871"
        expectedRole = "RDSDashboardCrossAccountRole"
        instructions = @(
            "1. Switch to AWS account 817214535871",
            "2. Check if role 'RDSDashboardCrossAccountRole' exists",
            "3. Verify role trust policy allows assumption from primary account",
            "4. Verify role has RDS read permissions"
        )
    }
    
    Write-Host "   ⚠️  Cross-account role verification requires manual check in account 817214535871" -ForegroundColor Yellow
} catch {
    $issue2.evidence.crossAccountRole = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking cross-account role: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2.2: Discovery Lambda Configuration
Write-Host "🔍 Test 2.2: Analyzing Discovery Lambda configuration..." -ForegroundColor Yellow

try {
    # Look for discovery Lambda functions
    $discoveryLambdas = aws lambda list-functions --query "Functions[?contains(FunctionName, 'discovery')].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified,Environment:Environment}" --output json 2>$null
    
    if ($discoveryLambdas) {
        $discLambdas = $discoveryLambdas | ConvertFrom-Json
        
        $issue2.evidence.discoveryLambdas = @{
            count = $discLambdas.Count
            functions = @()
        }
        
        Write-Host "   ✅ Found $($discLambdas.Count) discovery Lambda functions:" -ForegroundColor Green
        
        foreach ($func in $discLambdas) {
            $funcDetails = @{
                name = $func.Name
                runtime = $func.Runtime
                lastModified = $func.LastModified
                environmentVariables = @{}
            }
            
            Write-Host "      - $($func.Name) ($($func.Runtime)) - Modified: $($func.LastModified)" -ForegroundColor Cyan
            
            # Check critical environment variables
            if ($func.Environment -and $func.Environment.Variables) {
                $envVars = $func.Environment.Variables
                
                $criticalVars = @("TARGET_ACCOUNTS", "TARGET_REGIONS", "CROSS_ACCOUNT_ROLE_NAME", "EXTERNAL_ID")
                foreach ($var in $criticalVars) {
                    if ($envVars.$var) {
                        $funcDetails.environmentVariables[$var] = $envVars.$var
                        Write-Host "        ✅ $var = $($envVars.$var)" -ForegroundColor Green
                    } else {
                        $funcDetails.environmentVariables[$var] = "MISSING"
                        Write-Host "        ❌ $var = MISSING" -ForegroundColor Red
                    }
                }
            }
            
            $issue2.evidence.discoveryLambdas.functions += $funcDetails
        }
    } else {
        $issue2.evidence.discoveryLambdas = @{
            count = 0
            error = "No discovery Lambda functions found"
        }
        Write-Host "   ❌ No discovery Lambda functions found" -ForegroundColor Red
    }
} catch {
    $issue2.evidence.discoveryLambdas = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking discovery Lambda: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2.3: RDS Instances in Secondary Account
Write-Host "🔍 Test 2.3: Checking RDS instances in secondary account..." -ForegroundColor Yellow

$issue2.evidence.secondaryAccountRDS = @{
    status = "requires_cross_account_access"
    instructions = @(
        "1. Assume cross-account role in account 817214535871",
        "2. Run: aws rds describe-db-instances --region ap-southeast-1",
        "3. Run: aws rds describe-db-instances --region eu-west-2", 
        "4. Document which instances exist and their states",
        "5. Verify instances are in expected regions"
    )
}

Write-Host "   ⚠️  Secondary account RDS check requires cross-account role assumption" -ForegroundColor Yellow

# Test 2.4: Discovery Inventory Table
Write-Host "🔍 Test 2.4: Checking discovery inventory table..." -ForegroundColor Yellow

try {
    # Check if inventory table exists and has data
    $inventoryTables = aws dynamodb list-tables --query "TableNames[?contains(@, 'inventory')]" --output json 2>$null
    
    if ($inventoryTables) {
        $tables = $inventoryTables | ConvertFrom-Json
        
        $issue2.evidence.inventoryTable = @{
            tables = $tables
            data = @{}
        }
        
        Write-Host "   ✅ Found $($tables.Count) inventory tables:" -ForegroundColor Green
        
        foreach ($table in $tables) {
            Write-Host "      - $table" -ForegroundColor Cyan
            
            # Get item count (scan with limit to avoid large costs)
            try {
                $itemCount = aws dynamodb scan --table-name $table --select "COUNT" --max-items 100 --query "Count" --output text 2>$null
                if ($itemCount) {
                    $issue2.evidence.inventoryTable.data[$table] = @{
                        itemCount = $itemCount
                        status = "accessible"
                    }
                    Write-Host "        Items: $itemCount (limited scan)" -ForegroundColor Gray
                } else {
                    $issue2.evidence.inventoryTable.data[$table] = @{
                        status = "inaccessible_or_empty"
                    }
                    Write-Host "        Items: Unable to scan or empty" -ForegroundColor Yellow
                }
            } catch {
                $issue2.evidence.inventoryTable.data[$table] = @{
                    error = $_.Exception.Message
                }
                Write-Host "        Error scanning table: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        $issue2.evidence.inventoryTable = @{
            error = "No inventory tables found"
        }
        Write-Host "   ❌ No inventory tables found" -ForegroundColor Red
    }
} catch {
    $issue2.evidence.inventoryTable = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking inventory table: $($_.Exception.Message)" -ForegroundColor Red
}

$issue2.tests = @{
    crossAccountRole = "MANUAL_REQUIRED"
    discoveryLambdas = if ($issue2.evidence.discoveryLambdas.count -gt 0) { "PASS" } else { "FAIL" }
    secondaryAccountRDS = "MANUAL_REQUIRED"
    inventoryTable = if ($issue2.evidence.inventoryTable.tables) { "PASS" } else { "FAIL" }
}

$evidence.issues.issue2_cross_account_discovery = $issue2

# =============================================================================
# ISSUE 3: MISSING THIRD INSTANCE - FORENSIC ANALYSIS
# =============================================================================

Write-Host ""
Write-Host "🚨 ISSUE 3: Missing Third Instance" -ForegroundColor Red
Write-Host "==================================" -ForegroundColor Red

$issue3 = @{
    description = "Third RDS instance not visible despite discovery attempts"
    tests = @{}
    rootCause = $null
    evidence = @{}
}

# Test 3.1: RDS Instances in Primary Account
Write-Host "🔍 Test 3.1: Checking RDS instances in primary account..." -ForegroundColor Yellow

try {
    # Check RDS instances in primary account across regions
    $regions = @("ap-southeast-1", "eu-west-2", "ap-south-1", "us-east-1")
    
    $issue3.evidence.primaryAccountRDS = @{
        regions = @{}
        totalInstances = 0
    }
    
    foreach ($region in $regions) {
        Write-Host "   🌍 Checking region: $region" -ForegroundColor Cyan
        
        try {
            $instances = aws rds describe-db-instances --region $region --query "DBInstances[].{DBInstanceIdentifier:DBInstanceIdentifier,DBInstanceStatus:DBInstanceStatus,Engine:Engine,AvailabilityZone:AvailabilityZone}" --output json 2>$null
            
            if ($instances) {
                $regionInstances = $instances | ConvertFrom-Json
                
                $issue3.evidence.primaryAccountRDS.regions[$region] = @{
                    count = $regionInstances.Count
                    instances = $regionInstances
                }
                
                $issue3.evidence.primaryAccountRDS.totalInstances += $regionInstances.Count
                
                if ($regionInstances.Count -gt 0) {
                    Write-Host "      ✅ Found $($regionInstances.Count) instances:" -ForegroundColor Green
                    foreach ($instance in $regionInstances) {
                        Write-Host "         - $($instance.DBInstanceIdentifier) ($($instance.DBInstanceStatus)) - $($instance.Engine)" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "      ⚠️  No instances found" -ForegroundColor Yellow
                }
            } else {
                $issue3.evidence.primaryAccountRDS.regions[$region] = @{
                    count = 0
                    error = "Unable to describe instances or no instances found"
                }
                Write-Host "      ⚠️  No instances found or access error" -ForegroundColor Yellow
            }
        } catch {
            $issue3.evidence.primaryAccountRDS.regions[$region] = @{
                error = $_.Exception.Message
            }
            Write-Host "      ❌ Error checking region $region`: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "   📊 Total instances found across all regions: $($issue3.evidence.primaryAccountRDS.totalInstances)" -ForegroundColor Cyan
    
} catch {
    $issue3.evidence.primaryAccountRDS = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking primary account RDS: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3.2: Discovery Lambda Region Configuration
Write-Host "🔍 Test 3.2: Analyzing discovery Lambda region configuration..." -ForegroundColor Yellow

# This was already checked in Issue 2, so we'll reference that data
if ($issue2.evidence.discoveryLambdas -and $issue2.evidence.discoveryLambdas.functions) {
    $issue3.evidence.discoveryRegionConfig = @{
        source = "from_issue2_analysis"
        functions = @()
    }
    
    foreach ($func in $issue2.evidence.discoveryLambdas.functions) {
        if ($func.environmentVariables.TARGET_REGIONS) {
            $targetRegions = $func.environmentVariables.TARGET_REGIONS
            
            $issue3.evidence.discoveryRegionConfig.functions += @{
                name = $func.name
                targetRegions = $targetRegions
                regionsParsed = try { $targetRegions | ConvertFrom-Json } catch { "PARSE_ERROR" }
            }
            
            Write-Host "   📍 Function $($func.name) targets regions: $targetRegions" -ForegroundColor Cyan
        } else {
            $issue3.evidence.discoveryRegionConfig.functions += @{
                name = $func.name
                targetRegions = "MISSING"
                error = "TARGET_REGIONS environment variable not set"
            }
            Write-Host "   ❌ Function $($func.name) missing TARGET_REGIONS configuration" -ForegroundColor Red
        }
    }
} else {
    $issue3.evidence.discoveryRegionConfig = @{
        error = "No discovery Lambda functions found (from Issue 2 analysis)"
    }
    Write-Host "   ❌ No discovery Lambda functions to analyze" -ForegroundColor Red
}

# Test 3.3: Frontend Instance Display Logic
Write-Host "🔍 Test 3.3: Analyzing frontend instance display logic..." -ForegroundColor Yellow

try {
    # Check Dashboard component for instance display logic
    $dashboardPath = "frontend/src/pages/Dashboard.tsx"
    if (Test-Path $dashboardPath) {
        $dashboardContent = Get-Content $dashboardPath -Raw
        
        # Look for instance mapping/filtering logic
        $instancePattern = "(?s)(instances?\.map|instances?\.filter|instances?\.length)"
        $instanceMatches = [regex]::Matches($dashboardContent, $instancePattern)
        
        $issue3.evidence.frontendDisplayLogic = @{
            fileExists = $true
            instanceReferences = $instanceMatches.Count
            hasFiltering = $dashboardContent -match "filter"
            hasPagination = $dashboardContent -match "page|limit|offset"
            hasLoading = $dashboardContent -match "loading|Loading"
        }
        
        Write-Host "   ✅ Dashboard component found with $($instanceMatches.Count) instance references" -ForegroundColor Green
        Write-Host "      - Has filtering logic: $($issue3.evidence.frontendDisplayLogic.hasFiltering)" -ForegroundColor Gray
        Write-Host "      - Has pagination logic: $($issue3.evidence.frontendDisplayLogic.hasPagination)" -ForegroundColor Gray
        Write-Host "      - Has loading states: $($issue3.evidence.frontendDisplayLogic.hasLoading)" -ForegroundColor Gray
        
    } else {
        $issue3.evidence.frontendDisplayLogic = @{
            fileExists = $false
            error = "Dashboard component not found at $dashboardPath"
        }
        Write-Host "   ❌ Dashboard component not found" -ForegroundColor Red
    }
} catch {
    $issue3.evidence.frontendDisplayLogic = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error analyzing frontend display logic: $($_.Exception.Message)" -ForegroundColor Red
}

$issue3.tests = @{
    primaryAccountRDS = if ($issue3.evidence.primaryAccountRDS.totalInstances -gt 0) { "PASS" } else { "FAIL" }
    discoveryRegionConfig = if ($issue3.evidence.discoveryRegionConfig.functions) { "PASS" } else { "FAIL" }
    frontendDisplayLogic = if ($issue3.evidence.frontendDisplayLogic.fileExists) { "PASS" } else { "FAIL" }
}

$evidence.issues.issue3_missing_third_instance = $issue3

# =============================================================================
# INFRASTRUCTURE AUDIT
# =============================================================================

Write-Host ""
Write-Host "🏗️  INFRASTRUCTURE AUDIT" -ForegroundColor Blue
Write-Host "========================" -ForegroundColor Blue

# Check overall AWS connectivity and permissions
Write-Host "🔍 Checking AWS connectivity and basic permissions..." -ForegroundColor Yellow

try {
    $awsIdentity = aws sts get-caller-identity --output json 2>$null
    if ($awsIdentity) {
        $identity = $awsIdentity | ConvertFrom-Json
        $evidence.infrastructure.awsIdentity = $identity
        Write-Host "   ✅ AWS CLI connected as: $($identity.Arn)" -ForegroundColor Green
        Write-Host "      Account: $($identity.Account)" -ForegroundColor Gray
    } else {
        $evidence.infrastructure.awsIdentity = @{
            error = "AWS CLI not configured or no permissions"
        }
        Write-Host "   ❌ AWS CLI not configured or no permissions" -ForegroundColor Red
    }
} catch {
    $evidence.infrastructure.awsIdentity = @{
        error = $_.Exception.Message
    }
    Write-Host "   ❌ Error checking AWS identity: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# ANALYSIS AND RECOMMENDATIONS
# =============================================================================

Write-Host ""
Write-Host "📊 FORENSIC ANALYSIS SUMMARY" -ForegroundColor Magenta
Write-Host "============================" -ForegroundColor Magenta

# Analyze test results and provide recommendations
$totalTests = 0
$passedTests = 0
$failedTests = 0
$manualTests = 0

foreach ($issue in $evidence.issues.Values) {
    foreach ($test in $issue.tests.Values) {
        $totalTests++
        switch ($test) {
            "PASS" { $passedTests++ }
            "FAIL" { $failedTests++ }
            "MANUAL_REQUIRED" { $manualTests++ }
        }
    }
}

Write-Host "📈 Test Results Summary:" -ForegroundColor Cyan
Write-Host "   Total Tests: $totalTests" -ForegroundColor Gray
Write-Host "   Passed: $passedTests" -ForegroundColor Green
Write-Host "   Failed: $failedTests" -ForegroundColor Red
Write-Host "   Manual Required: $manualTests" -ForegroundColor Yellow

# Generate specific recommendations based on evidence
Write-Host ""
Write-Host "🎯 EVIDENCE-BASED RECOMMENDATIONS:" -ForegroundColor Yellow

$recommendations = @()

# Issue 1 Recommendations
if ($issue1.tests.bffFunctions -eq "FAIL") {
    $recommendations += "CRITICAL: No BFF functions found - deploy BFF Lambda function first"
}
if ($issue1.tests.operationsLambdas -eq "FAIL") {
    $recommendations += "CRITICAL: No operations Lambda functions found - deploy operations Lambda function"
}
if ($issue1.tests.apiGateway -eq "FAIL") {
    $recommendations += "HIGH: API Gateway not configured - set up API Gateway with proper routing"
}

# Issue 2 Recommendations  
if ($issue2.tests.discoveryLambdas -eq "FAIL") {
    $recommendations += "HIGH: No discovery Lambda functions found - deploy discovery Lambda function"
}
if ($issue2.tests.inventoryTable -eq "FAIL") {
    $recommendations += "HIGH: No inventory tables found - create DynamoDB inventory table"
}

# Issue 3 Recommendations
if ($issue3.tests.primaryAccountRDS -eq "FAIL") {
    $recommendations += "MEDIUM: No RDS instances found in primary account - verify instances exist"
}

# General recommendations
$recommendations += "MANUAL: Test cross-account role assumption in account 817214535871"
$recommendations += "MANUAL: Test direct API calls to identify exact 400 error source"
$recommendations += "MANUAL: Verify RDS instances exist in secondary account"

foreach ($i in 0..($recommendations.Count - 1)) {
    Write-Host "   $($i + 1). $($recommendations[$i])" -ForegroundColor White
}

$evidence.recommendations.prioritized = $recommendations

# =============================================================================
# SAVE EVIDENCE
# =============================================================================

if ($SaveEvidence) {
    Write-Host ""
    Write-Host "💾 SAVING FORENSIC EVIDENCE" -ForegroundColor Green
    Write-Host "===========================" -ForegroundColor Green
    
    $evidenceFile = Join-Path $OutputDir "forensic-evidence.json"
    $evidence | ConvertTo-Json -Depth 10 | Out-File -FilePath $evidenceFile -Encoding UTF8
    
    Write-Host "   ✅ Evidence saved to: $evidenceFile" -ForegroundColor Green
    
    # Create summary report
    $summaryFile = Join-Path $OutputDir "forensic-summary.md"
    $summary = @"
# Forensic Analysis Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Test Results
- Total Tests: $totalTests
- Passed: $passedTests  
- Failed: $failedTests
- Manual Required: $manualTests

## Critical Findings

### Issue 1: Instance Operations 400 Errors
- BFF Functions: $($issue1.tests.bffFunctions)
- Operations Lambdas: $($issue1.tests.operationsLambdas)
- API Gateway: $($issue1.tests.apiGateway)

### Issue 2: Cross-Account Discovery  
- Discovery Lambdas: $($issue2.tests.discoveryLambdas)
- Inventory Table: $($issue2.tests.inventoryTable)

### Issue 3: Missing Third Instance
- Primary Account RDS: $($issue3.tests.primaryAccountRDS)
- Frontend Display Logic: $($issue3.tests.frontendDisplayLogic)

## Recommendations
$($recommendations | ForEach-Object { "- $_" } | Out-String)

## Next Steps
1. Address CRITICAL issues first (missing Lambda functions)
2. Complete manual verification tasks
3. Fix issues one at a time with targeted solutions
4. Re-run forensic analysis after each fix to validate progress
"@
    
    $summary | Out-File -FilePath $summaryFile -Encoding UTF8
    Write-Host "   ✅ Summary saved to: $summaryFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "🔍 FORENSIC ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host "Next step: Address the evidence-based recommendations above" -ForegroundColor Yellow
Write-Host "Focus on CRITICAL issues first, then HIGH priority items" -ForegroundColor Yellow
Write-Host ""

if ($SaveEvidence) {
    Write-Host "📁 All evidence and analysis saved to: $OutputDir" -ForegroundColor Green
    Write-Host "   Review the JSON file for detailed technical evidence" -ForegroundColor Gray
    Write-Host "   Review the summary file for actionable next steps" -ForegroundColor Gray
}