# Test RDS Operations Lambda
# This script tests the operations Lambda function directly

param(
    [Parameter(Mandatory=$true)]
    [string]$InstanceId,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('start_instance', 'stop_instance', 'reboot_instance', 'create_snapshot')]
    [string]$Operation = 'start_instance'
)

Write-Host "Testing RDS Operations Lambda..." -ForegroundColor Cyan
Write-Host "Instance ID: $InstanceId" -ForegroundColor Yellow
Write-Host "Operation: $Operation" -ForegroundColor Yellow
Write-Host ""

# Create test payload
$payload = @{
    body = @{
        operation = $Operation
        instance_id = $InstanceId
        parameters = @{}
    } | ConvertTo-Json
    requestContext = @{
        identity = @{
            userArn = "arn:aws:iam::123456789012:user/test-user"
            sourceIp = "127.0.0.1"
        }
    }
} | ConvertTo-Json -Depth 10

# Save payload to file
$payload | Out-File -FilePath "test-operations-payload.json" -Encoding UTF8

Write-Host "Payload created:" -ForegroundColor Green
Write-Host $payload
Write-Host ""

# Invoke Lambda
Write-Host "Invoking Lambda function..." -ForegroundColor Cyan
aws lambda invoke `
    --function-name rds-dashboard-operations `
    --payload file://test-operations-payload.json `
    --cli-binary-format raw-in-base64-out `
    test-operations-response.json

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Lambda Response:" -ForegroundColor Green
    Get-Content test-operations-response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
    Write-Host ""
    
    # Check CloudWatch logs
    Write-Host "Fetching CloudWatch logs..." -ForegroundColor Cyan
    aws logs tail /aws/lambda/rds-dashboard-operations --since 5m --format short
} else {
    Write-Host "Lambda invocation failed!" -ForegroundColor Red
}

# Cleanup
Remove-Item test-operations-payload.json -ErrorAction SilentlyContinue
