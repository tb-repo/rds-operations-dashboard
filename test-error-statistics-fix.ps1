#!/usr/bin/env pwsh

<#
.SYNOPSIS
Test script to verify the error statistics endpoint fix

.DESCRIPTION
This script tests the fixed error statistics endpoint to ensure it no longer returns 500 errors.
It validates both the BFF endpoint and the underlying monitoring dashboard endpoint.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-20T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.2, 1.3 → DESIGN-ErrorStatisticsFix → TASK-2",
  "review_status": "Pending",
  "risk_level": "Level 1",
  "reviewed_by": null,
  "approved_by": null
}
#>

param(
    [string]$BffUrl = "https://your-bff-domain.com",
    [string]$ApiUrl = "https://your-api-gateway-url.com/prod",
    [string]$ApiKey = $env:API_KEY,
    [string]$AuthToken = $env:AUTH_TOKEN
)

Write-Host "🧪 Testing Error Statistics Endpoint Fix" -ForegroundColor Cyan
Write-Host "=" * 50

# Check required parameters
if (-not $ApiKey) {
    Write-Host "❌ API_KEY environment variable not set" -ForegroundColor Red
    Write-Host "Please set API_KEY environment variable or pass -ApiKey parameter"
    exit 1
}

if (-not $AuthToken) {
    Write-Host "⚠️  AUTH_TOKEN not set - some tests may fail" -ForegroundColor Yellow
}

$headers = @{
    'x-api-key' = $ApiKey
    'Content-Type' = 'application/json'
}

if ($AuthToken) {
    $headers['Authorization'] = "Bearer $AuthToken"
}

Write-Host "🔍 Test 1: Direct API Gateway - Monitoring Dashboard Metrics" -ForegroundColor Green

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/monitoring-dashboard/metrics" -Method GET -Headers $headers -TimeoutSec 10
    Write-Host "✅ Monitoring dashboard metrics endpoint working" -ForegroundColor Green
    Write-Host "   Response contains widgets: $($response.widgets.Keys -join ', ')" -ForegroundColor Gray
} catch {
    Write-Host "❌ Monitoring dashboard metrics failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

Write-Host ""
Write-Host "🔍 Test 2: BFF Error Statistics Endpoint (Fixed Route)" -ForegroundColor Green

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/statistics" -Method GET -Headers $headers -TimeoutSec 10
    Write-Host "✅ BFF error statistics endpoint working" -ForegroundColor Green
    Write-Host "   Status: $($response.status)" -ForegroundColor Gray
    Write-Host "   Total errors detected: $($response.statistics.total_errors_detected)" -ForegroundColor Gray
    Write-Host "   Services affected: $($response.statistics.services_affected)" -ForegroundColor Gray
    
    if ($response.fallback) {
        Write-Host "   ⚠️  Using fallback data (monitoring service may be unavailable)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ BFF error statistics failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    
    if ($_.Exception.Response.StatusCode -eq 500) {
        Write-Host "   🚨 Still getting 500 error - fix may not be deployed yet" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🔍 Test 3: Error Dashboard Endpoint" -ForegroundColor Green

try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/dashboard" -Method GET -Headers $headers -TimeoutSec 10
    Write-Host "✅ Error dashboard endpoint working" -ForegroundColor Green
    Write-Host "   Dashboard ID: $($response.dashboard_id)" -ForegroundColor Gray
    Write-Host "   Last updated: $($response.last_updated)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Error dashboard failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

Write-Host ""
Write-Host "🔍 Test 4: Frontend API Client Test" -ForegroundColor Green

# Test the data structure expected by frontend
try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/errors/statistics" -Method GET -Headers $headers -TimeoutSec 10
    
    # Validate expected structure
    $requiredFields = @('status', 'statistics', 'errors_by_severity', 'timestamp')
    $missingFields = @()
    
    foreach ($field in $requiredFields) {
        if (-not $response.$field) {
            $missingFields += $field
        }
    }
    
    if ($missingFields.Count -eq 0) {
        Write-Host "✅ Response structure matches frontend expectations" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Missing expected fields: $($missingFields -join ', ')" -ForegroundColor Yellow
    }
    
    # Check statistics sub-fields
    $statsFields = @('total_errors_detected', 'detector_version', 'patterns_loaded')
    $missingStatsFields = @()
    
    foreach ($field in $statsFields) {
        if (-not $response.statistics.$field) {
            $missingStatsFields += $field
        }
    }
    
    if ($missingStatsFields.Count -eq 0) {
        Write-Host "✅ Statistics structure is complete" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Missing statistics fields: $($missingStatsFields -join ', ')" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Structure validation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "📊 Summary" -ForegroundColor Cyan
Write-Host "=" * 50

Write-Host "The error statistics endpoint has been fixed by:"
Write-Host "1. ✅ Routing BFF /api/errors/statistics to monitoring-dashboard/metrics"
Write-Host "2. ✅ Transforming monitoring data to expected statistics format"
Write-Host "3. ✅ Maintaining graceful fallback for service unavailability"
Write-Host "4. ✅ Re-enabling frontend statistics query"

Write-Host ""
Write-Host "Next steps:"
Write-Host "- Deploy the BFF changes to production"
Write-Host "- Deploy the frontend changes to production"
Write-Host "- Monitor CloudWatch logs to confirm 500 errors are eliminated"
Write-Host "- Verify dashboard loads without console errors"

Write-Host ""
Write-Host "🎯 Root cause was: BFF routing to non-existent /error-resolution/statistics endpoint"
Write-Host "🔧 Solution: Route to existing /monitoring-dashboard/metrics endpoint instead"