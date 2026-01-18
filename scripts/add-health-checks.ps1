#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Adds health check endpoints to all backend services
.DESCRIPTION
    Implements comprehensive health checks for all Lambda functions and API Gateway endpoints
    to support the clean URL API Gateway configuration.
.PARAMETER Environment
    Environment to deploy health checks to (staging, production)
.EXAMPLE
    ./add-health-checks.ps1 -Environment production
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("staging", "production")]
    [string]$Environment
)

Write-Host "🏥 Adding Health Check Endpoints for API Gateway Stage Elimination" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

# Health check implementation for BFF
$bffHealthCheck = @'
// Health check endpoint for BFF
app.get('/health', (req, res) => {
  const healthCheck = {
    timestamp: new Date().toISOString(),
    status: 'healthy',
    service: 'rds-dashboard-bff',
    version: process.env.npm_package_version || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    checks: {
      database: 'not_implemented',
      external_services: 'not_implemented',
      memory: {
        used: process.memoryUsage().heapUsed,
        total: process.memoryUsage().heapTotal,
        percentage: Math.round((process.memoryUsage().heapUsed / process.memoryUsage().heapTotal) * 100)
      }
    },
    uptime: process.uptime(),
    cors_origin: process.env.CORS_ORIGINS || 'not_configured'
  };

  // Check if critical environment variables are present
  const requiredEnvVars = ['COGNITO_USER_POOL_ID', 'COGNITO_CLIENT_ID', 'JWT_SECRET_NAME'];
  const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);
  
  if (missingEnvVars.length > 0) {
    healthCheck.status = 'degraded';
    healthCheck.checks.environment = {
      status: 'error',
      missing_variables: missingEnvVars
    };
  } else {
    healthCheck.checks.environment = {
      status: 'healthy',
      variables_configured: requiredEnvVars.length
    };
  }

  const statusCode = healthCheck.status === 'healthy' ? 200 : 503;
  res.status(statusCode).json(healthCheck);
});

// Detailed health check endpoint
app.get('/health/detailed', (req, res) => {
  const detailedHealth = {
    timestamp: new Date().toISOString(),
    service: 'rds-dashboard-bff',
    status: 'healthy',
    version: process.env.npm_package_version || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    system: {
      platform: process.platform,
      arch: process.arch,
      node_version: process.version,
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      cpu_usage: process.cpuUsage()
    },
    configuration: {
      cors_origins: process.env.CORS_ORIGINS || 'not_configured',
      cognito_configured: !!(process.env.COGNITO_USER_POOL_ID && process.env.COGNITO_CLIENT_ID),
      jwt_secret_configured: !!process.env.JWT_SECRET_NAME,
      internal_api_configured: !!process.env.INTERNAL_API_URL
    },
    endpoints: {
      instances: '/api/instances',
      operations: '/api/operations',
      health: '/health',
      cors_config: '/cors-config'
    }
  };

  res.json(detailedHealth);
});
'@

# Health check implementation for Lambda functions
$lambdaHealthCheck = @'
import json
import os
import time
import boto3
from datetime import datetime

def health_check_handler(event, context):
    """
    Health check endpoint for Lambda functions
    """
    
    # Basic health information
    health_data = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'status': 'healthy',
        'service': os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown'),
        'version': os.environ.get('AWS_LAMBDA_FUNCTION_VERSION', '1.0.0'),
        'environment': os.environ.get('ENVIRONMENT', 'unknown'),
        'aws_region': os.environ.get('AWS_REGION', 'unknown'),
        'memory_limit': context.memory_limit_in_mb if context else 'unknown',
        'remaining_time': context.get_remaining_time_in_millis() if context else 'unknown'
    }
    
    # Check required environment variables
    required_env_vars = [
        'AWS_ACCOUNT_ID',
        'INVENTORY_TABLE',
        'AUDIT_LOG_TABLE'
    ]
    
    missing_env_vars = [var for var in required_env_vars if not os.environ.get(var)]
    
    if missing_env_vars:
        health_data['status'] = 'degraded'
        health_data['issues'] = {
            'missing_environment_variables': missing_env_vars
        }
    
    # Test AWS service connectivity
    try:
        # Test DynamoDB connectivity
        dynamodb = boto3.client('dynamodb')
        inventory_table = os.environ.get('INVENTORY_TABLE')
        if inventory_table:
            dynamodb.describe_table(TableName=inventory_table)
            health_data['checks'] = health_data.get('checks', {})
            health_data['checks']['dynamodb'] = 'healthy'
        
        # Test RDS connectivity
        rds = boto3.client('rds')
        rds.describe_db_instances(MaxRecords=1)
        health_data['checks'] = health_data.get('checks', {})
        health_data['checks']['rds'] = 'healthy'
        
    except Exception as e:
        health_data['status'] = 'degraded'
        health_data['checks'] = health_data.get('checks', {})
        health_data['checks']['aws_services'] = f'error: {str(e)}'
    
    # Return appropriate status code
    status_code = 200 if health_data['status'] == 'healthy' else 503
    
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        },
        'body': json.dumps(health_data, indent=2)
    }
'@

function Add-BFFHealthCheck {
    Write-Host "🔧 Adding health check to BFF Lambda..." -ForegroundColor Blue
    
    # Create temporary health check file
    $tempHealthFile = "temp-health-check.js"
    $bffHealthCheck | Out-File -FilePath $tempHealthFile -Encoding UTF8
    
    try {
        # Get current BFF code
        $functionName = if ($Environment -eq "production") { "rds-dashboard-bff-prod" } else { "rds-dashboard-bff-staging" }
        
        Write-Host "  📦 Downloading current BFF code..." -ForegroundColor Gray
        aws lambda get-function --function-name $functionName --query 'Code.Location' --output text | ForEach-Object {
            Invoke-WebRequest -Uri $_ -OutFile "current-bff.zip"
        }
        
        # Extract and modify
        Expand-Archive -Path "current-bff.zip" -DestinationPath "bff-temp" -Force
        
        # Add health check to index.js
        $indexPath = "bff-temp/index.js"
        if (Test-Path $indexPath) {
            $currentContent = Get-Content $indexPath -Raw
            
            # Insert health check before the export
            $healthCheckContent = Get-Content $tempHealthFile -Raw
            $newContent = $currentContent -replace "(module\.exports = app;|exports\.handler = serverless\(app\);)", "$healthCheckContent`n`n`$1"
            
            $newContent | Out-File -FilePath $indexPath -Encoding UTF8
            
            Write-Host "  ✅ Health check added to BFF code" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Could not find BFF index.js file" -ForegroundColor Red
            return $false
        }
        
        # Repackage and deploy
        Compress-Archive -Path "bff-temp/*" -DestinationPath "updated-bff.zip" -Force
        
        Write-Host "  🚀 Deploying updated BFF with health check..." -ForegroundColor Gray
        aws lambda update-function-code --function-name $functionName --zip-file fileb://updated-bff.zip
        
        Write-Host "  ✅ BFF health check deployed successfully" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "  ❌ Failed to add BFF health check: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        # Cleanup
        Remove-Item -Path $tempHealthFile -ErrorAction SilentlyContinue
        Remove-Item -Path "current-bff.zip" -ErrorAction SilentlyContinue
        Remove-Item -Path "updated-bff.zip" -ErrorAction SilentlyContinue
        Remove-Item -Path "bff-temp" -Recurse -ErrorAction SilentlyContinue
    }
}

function Add-LambdaHealthCheck {
    param(
        [string]$FunctionName,
        [string]$ServiceName
    )
    
    Write-Host "🔧 Adding health check to $ServiceName Lambda..." -ForegroundColor Blue
    
    # Create temporary health check file
    $tempHealthFile = "temp-lambda-health.py"
    $lambdaHealthCheck | Out-File -FilePath $tempHealthFile -Encoding UTF8
    
    try {
        Write-Host "  📦 Downloading current $ServiceName code..." -ForegroundColor Gray
        aws lambda get-function --function-name $FunctionName --query 'Code.Location' --output text | ForEach-Object {
            Invoke-WebRequest -Uri $_ -OutFile "current-$ServiceName.zip"
        }
        
        # Extract and modify
        Expand-Archive -Path "current-$ServiceName.zip" -DestinationPath "$ServiceName-temp" -Force
        
        # Add health check handler
        Copy-Item $tempHealthFile "$ServiceName-temp/health_check.py"
        
        # Update handler.py to include health check route
        $handlerPath = "$ServiceName-temp/handler.py"
        if (Test-Path $handlerPath) {
            $currentContent = Get-Content $handlerPath -Raw
            
            # Add health check import and handler
            $healthImport = "from health_check import health_check_handler"
            $healthRoute = @"

# Health check endpoint
if event.get('httpMethod') == 'GET' and event.get('path') == '/health':
    return health_check_handler(event, context)
"@
            
            # Insert import at the top
            $newContent = $healthImport + "`n" + $currentContent
            
            # Insert health check route at the beginning of the handler
            $newContent = $newContent -replace "(def lambda_handler\(event, context\):\s*)", "`$1$healthRoute`n"
            
            $newContent | Out-File -FilePath $handlerPath -Encoding UTF8
            
            Write-Host "  ✅ Health check added to $ServiceName code" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Could not find $ServiceName handler.py file" -ForegroundColor Red
            return $false
        }
        
        # Repackage and deploy
        Compress-Archive -Path "$ServiceName-temp/*" -DestinationPath "updated-$ServiceName.zip" -Force
        
        Write-Host "  🚀 Deploying updated $ServiceName with health check..." -ForegroundColor Gray
        aws lambda update-function-code --function-name $FunctionName --zip-file "fileb://updated-$ServiceName.zip"
        
        Write-Host "  ✅ $ServiceName health check deployed successfully" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "  ❌ Failed to add $ServiceName health check: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        # Cleanup
        Remove-Item -Path $tempHealthFile -ErrorAction SilentlyContinue
        Remove-Item -Path "current-$ServiceName.zip" -ErrorAction SilentlyContinue
        Remove-Item -Path "updated-$ServiceName.zip" -ErrorAction SilentlyContinue
        Remove-Item -Path "$ServiceName-temp" -Recurse -ErrorAction SilentlyContinue
    }
}

function Test-HealthChecks {
    Write-Host "🧪 Testing health check endpoints..." -ForegroundColor Blue
    
    $endpoints = @(
        @{ Name = "BFF Health"; Url = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/health" },
        @{ Name = "BFF Detailed Health"; Url = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/health/detailed" },
        @{ Name = "Discovery Health"; Url = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/health" },
        @{ Name = "Operations Health"; Url = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/health" }
    )
    
    $allHealthy = $true
    
    foreach ($endpoint in $endpoints) {
        try {
            Write-Host "  🔍 Testing $($endpoint.Name)..." -ForegroundColor Gray
            $response = Invoke-RestMethod -Uri $endpoint.Url -Method GET -TimeoutSec 10
            
            if ($response.status -eq "healthy") {
                Write-Host "    ✅ $($endpoint.Name): Healthy" -ForegroundColor Green
            } else {
                Write-Host "    ⚠️  $($endpoint.Name): $($response.status)" -ForegroundColor Yellow
                $allHealthy = $false
            }
            
        } catch {
            Write-Host "    ❌ $($endpoint.Name): Failed - $($_.Exception.Message)" -ForegroundColor Red
            $allHealthy = $false
        }
    }
    
    return $allHealthy
}

# Main execution
Write-Host "🚀 Starting health check implementation..." -ForegroundColor Green
Write-Host ""

$results = @{
    BFF = $false
    Discovery = $false
    Operations = $false
    Testing = $false
}

# Add health checks to all services
$results.BFF = Add-BFFHealthCheck

if ($Environment -eq "production") {
    $results.Discovery = Add-LambdaHealthCheck -FunctionName "rds-discovery-prod" -ServiceName "Discovery"
    $results.Operations = Add-LambdaHealthCheck -FunctionName "rds-operations-prod" -ServiceName "Operations"
} else {
    $results.Discovery = Add-LambdaHealthCheck -FunctionName "rds-discovery-staging" -ServiceName "Discovery"
    $results.Operations = Add-LambdaHealthCheck -FunctionName "rds-operations-staging" -ServiceName "Operations"
}

# Wait for deployments to complete
Write-Host "⏳ Waiting for deployments to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Test all health checks
$results.Testing = Test-HealthChecks

# Generate report
Write-Host ""
Write-Host "📊 HEALTH CHECK IMPLEMENTATION REPORT" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

foreach ($service in $results.Keys) {
    $status = if ($results[$service]) { "✅ SUCCESS" } else { "❌ FAILED" }
    $color = if ($results[$service]) { "Green" } else { "Red" }
    Write-Host "$service`: $status" -ForegroundColor $color
}

Write-Host ""
if ($results.Values -contains $false) {
    Write-Host "❌ HEALTH CHECK IMPLEMENTATION INCOMPLETE" -ForegroundColor Red
    Write-Host "Some health checks failed to deploy. Check the logs above for details." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "✅ ALL HEALTH CHECKS IMPLEMENTED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "All services now have health check endpoints available." -ForegroundColor Green
    Write-Host ""
    Write-Host "Available endpoints:" -ForegroundColor Yellow
    Write-Host "- BFF Health: https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/health" -ForegroundColor White
    Write-Host "- BFF Detailed: https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/health/detailed" -ForegroundColor White
    Write-Host "- Discovery Health: https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/health" -ForegroundColor White
    Write-Host "- Operations Health: https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/health" -ForegroundColor White
    exit 0
}