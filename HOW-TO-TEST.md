# How to Test - Quick Start

**Quick reference for testing the RDS Operations Dashboard**

## 🚀 Fastest Way to Test (5 minutes)

### 1. Quick Syntax Check

```bash
cd rds-operations-dashboard

# Make script executable
chmod +x quick-test.sh

# Run quick test
./quick-test.sh
```

This will check:
- ✅ Python syntax for all Lambda functions
- ✅ Configuration file validity
- ✅ TypeScript compilation
- ✅ AWS CLI configuration
- ✅ Python dependencies

### 2. Run Unit Tests

```bash
cd lambda

# Install test dependencies
pip install pytest pytest-cov

# Run tests
pytest tests/test_basic.py -v

# Expected output:
# test_imports PASSED
# test_logger_creation PASSED
# test_sanitize_log_data PASSED
# ... etc
```

---

## 🔧 Local Testing (No AWS Required)

### Test Individual Modules

```bash
cd lambda

# Test logger
python3 -c "
from shared.logger import StructuredLogger
logger = StructuredLogger('test')
logger.info('Test message', key='value')
print('✓ Logger works!')
"

# Test config structure
python3 -c "
from shared.config import DynamoDBConfig
config = DynamoDBConfig(
    inventory_table='test',
    metrics_cache_table='test',
    health_alerts_table='test',
    audit_log_table='test'
)
print('✓ Config works!')
"

# Test discovery handler structure
python3 -c "
from discovery import handler
print('✓ Discovery handler imports successfully!')
print(f'  - lambda_handler: {callable(handler.lambda_handler)}')
print(f'  - discover_all_instances: {callable(handler.discover_all_instances)}')
"

# Test health monitor handler structure
python3 -c "
from health_monitor import handler
print('✓ Health monitor handler imports successfully!')
print(f'  - lambda_handler: {callable(handler.lambda_handler)}')
print(f'  - monitor_all_instances: {callable(handler.monitor_all_instances)}')
"
```

---

## ☁️ AWS Integration Testing

### Prerequisites

```bash
# 1. Configure AWS credentials
aws configure

# 2. Deploy infrastructure
cd infrastructure
npm install
cdk bootstrap
cdk deploy --all

# 3. Note the deployed function names from output
```

### Test Discovery Lambda

```bash
# Invoke discovery Lambda
aws lambda invoke \
  --function-name rds-discovery-prod \
  --payload '{}' \
  response.json

# View results
cat response.json | jq .

# Expected output:
# {
#   "statusCode": 200,
#   "body": {
#     "total_instances": 5,
#     "accounts_scanned": 2,
#     "regions_scanned": 4,
#     ...
#   }
# }

# Check CloudWatch Logs
aws logs tail /aws/lambda/rds-discovery-prod --follow
```

### Test Health Monitor Lambda

```bash
# Invoke health monitor Lambda
aws lambda invoke \
  --function-name rds-health-monitor-prod \
  --payload '{}' \
  response.json

# View results
cat response.json | jq .

# Expected output:
# {
#   "statusCode": 200,
#   "body": {
#     "instances_monitored": 5,
#     "cache_hit_rate": 75.5,
#     ...
#   }
# }

# Check CloudWatch Logs
aws logs tail /aws/lambda/rds-health-monitor-prod --follow
```

### Verify Data in DynamoDB

```bash
# Check discovered instances
aws dynamodb scan \
  --table-name rds-inventory-prod \
  --max-items 5 \
  | jq '.Items[].instance_id'

# Check metrics cache
aws dynamodb scan \
  --table-name metrics-cache-prod \
  --max-items 5 \
  | jq '.Items[].cache_key'
```

### Check CloudWatch Metrics

```bash
# List all metrics
aws cloudwatch list-metrics \
  --namespace DBMRDSDashboard

# Get cache hit rate
aws cloudwatch get-metric-statistics \
  --namespace DBMRDSDashboard \
  --metric-name CacheHitRate \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## 🐛 Troubleshooting

### Python Import Errors

```bash
# Add lambda directory to Python path
export PYTHONPATH="${PYTHONPATH}:$(pwd)/lambda"

# Or install as package
cd lambda
pip install -e .
```

### AWS Credentials Not Found

```bash
# Configure AWS CLI
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_DEFAULT_REGION=ap-southeast-1
```

### Lambda Function Not Found

```bash
# Check if deployed
aws lambda list-functions | grep rds-discovery

# If not found, deploy infrastructure
cd infrastructure
cdk deploy --all
```

---

## ✅ Testing Checklist

Before deployment:
- [ ] `./quick-test.sh` passes
- [ ] `pytest tests/test_basic.py` passes
- [ ] `cdk synth` succeeds
- [ ] Config file has real account IDs

After deployment:
- [ ] Discovery Lambda runs successfully
- [ ] Instances appear in DynamoDB
- [ ] Health Monitor Lambda runs successfully
- [ ] Metrics cached in DynamoDB
- [ ] CloudWatch metrics visible
- [ ] No errors in CloudWatch Logs

---

## 📚 More Testing Options

For comprehensive testing guide, see: [TESTING-GUIDE.md](TESTING-GUIDE.md)

Includes:
- Unit tests with moto (AWS mocking)
- LocalStack testing
- Performance testing
- End-to-end testing scripts
- CI/CD integration examples

---

## 🎯 Quick Commands Reference

```bash
# Syntax check
./quick-test.sh

# Unit tests
cd lambda && pytest tests/ -v

# Deploy
cd infrastructure && cdk deploy --all

# Test discovery
aws lambda invoke --function-name rds-discovery-prod --payload '{}' response.json

# Test health monitor
aws lambda invoke --function-name rds-health-monitor-prod --payload '{}' response.json

# Check logs
aws logs tail /aws/lambda/rds-discovery-prod --follow

# Check DynamoDB
aws dynamodb scan --table-name rds-inventory-prod --max-items 5

# Check metrics
aws cloudwatch list-metrics --namespace DBMRDSDashboard
```

---

## 💡 Tips

1. **Start Simple** - Run `./quick-test.sh` first
2. **Test Locally** - Use unit tests before deploying
3. **Deploy to Test** - Use separate test environment
4. **Check Logs** - CloudWatch Logs are your friend
5. **Verify Data** - Check DynamoDB after each Lambda run

Happy testing! 🚀
