# Quality Gates Implementation Guide

**Purpose:** Prevent code issues from reaching production through automated validation gates.

---

## Overview

Quality gates are automated checkpoints that code must pass before progressing to the next stage. Each gate validates specific aspects of code quality, functionality, and reliability.

```
Code Written → Gate 1: Syntax → Gate 2: Tests → Gate 3: Integration → Gate 4: Staging → Production
                 ↓ Fail          ↓ Fail          ↓ Fail              ↓ Fail
              [Block]          [Block]          [Block]            [Block]
```

---

## Gate 1: Pre-Commit Validation

**When:** Before code is committed to Git  
**Purpose:** Catch syntax errors, style issues, and basic problems  
**Enforcement:** Git pre-commit hooks

### Setup

```bash
# Install pre-commit
pip install pre-commit

# Create .pre-commit-config.yaml
cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-added-large-files

  - repo: https://github.com/psf/black
    rev: 23.12.0
    hooks:
      - id: black
        language_version: python3.11

  - repo: https://github.com/pycqa/flake8
    rev: 6.1.0
    hooks:
      - id: flake8
        args: ['--max-line-length=120', '--ignore=E203,W503']

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.7.1
    hooks:
      - id: mypy
        additional_dependencies: [types-all]
        args: ['--strict', '--ignore-missing-imports']
EOF

# Install hooks
pre-commit install
```

### What It Catches

- ✅ Syntax errors (invalid Python)
- ✅ Import errors (missing modules)
- ✅ Type mismatches (wrong types)
- ✅ Style violations (PEP 8)
- ✅ Trailing whitespace
- ✅ Large files accidentally committed

### Example Output

```bash
$ git commit -m "Add compliance checker"

black....................................................................Failed
- hook id: black
- files were modified by this hook

reformatted lambda/compliance-checker/handler.py

flake8...................................................................Failed
- hook id: flake8
- exit code: 1

lambda/compliance-checker/handler.py:15:1: F401 'sys' imported but unused

mypy.....................................................................Failed
- hook id: mypy
- exit code: 1

lambda/compliance-checker/handler.py:48: error: "AppConfig" has no attribute "get"
```

---

## Gate 2: Unit Test Validation

**When:** On every push to Git  
**Purpose:** Verify individual components work correctly  
**Enforcement:** GitHub Actions CI

### Setup

```yaml
# .github/workflows/unit-tests.yml
name: Unit Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r lambda/requirements.txt
          pip install pytest pytest-cov pytest-mock
      
      - name: Run unit tests
        run: |
          pytest lambda/tests/ \
            --cov=lambda \
            --cov-report=term-missing \
            --cov-fail-under=70 \
            --tb=short
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml
```

### What It Catches

- ✅ Function logic errors
- ✅ Edge case handling
- ✅ Exception handling
- ✅ Return value correctness
- ✅ Mock integration issues

### Example Test

```python
# lambda/tests/test_aws_clients.py
import pytest
from shared.aws_clients import AWSClients

def test_get_rds_client_returns_client():
    """Verify get_rds_client returns a boto3 client."""
    client = AWSClients.get_rds_client()
    assert client is not None
    assert hasattr(client, 'describe_db_instances')

def test_get_rds_client_with_region():
    """Verify get_rds_client accepts region parameter."""
    client = AWSClients.get_rds_client(region='us-east-1')
    assert client.meta.region_name == 'us-east-1'

def test_config_has_get_method():
    """Verify Config supports dict-like get() method."""
    from shared.config import Config
    config = Config.load()
    
    # Should support both styles
    assert config.dynamodb.inventory_table is not None
    assert config.get('dynamodb_tables') is not None
```

---

## Gate 3: Integration Test Validation

**When:** Before merging to main branch  
**Purpose:** Verify components work together  
**Enforcement:** GitHub Actions + Branch Protection

### Setup

```yaml
# .github/workflows/integration-tests.yml
name: Integration Tests

on:
  pull_request:
    branches: [main]

jobs:
  integration:
    runs-on: ubuntu-latest
    
    services:
      dynamodb:
        image: amazon/dynamodb-local
        ports:
          - 8000:8000
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r lambda/requirements.txt
          pip install pytest boto3 moto
      
      - name: Run integration tests
        env:
          AWS_ACCESS_KEY_ID: test
          AWS_SECRET_ACCESS_KEY: test
          AWS_DEFAULT_REGION: ap-southeast-1
        run: |
          pytest tests/integration/ \
            --tb=short \
            -v
```

### What It Catches

- ✅ Module import issues
- ✅ API contract violations
- ✅ Database schema mismatches
- ✅ Configuration errors
- ✅ Cross-module communication issues

### Example Test

```python
# tests/integration/test_compliance_flow.py
import pytest
from moto import mock_dynamodb, mock_rds
import boto3

@mock_dynamodb
@mock_rds
def test_compliance_checker_end_to_end():
    """Test complete compliance checking flow."""
    # Setup
    dynamodb = boto3.resource('dynamodb', region_name='ap-southeast-1')
    table = dynamodb.create_table(
        TableName='rds-inventory-test',
        KeySchema=[{'AttributeName': 'instance_id', 'KeyType': 'HASH'}],
        AttributeDefinitions=[{'AttributeName': 'instance_id', 'AttributeType': 'S'}],
        BillingMode='PAY_PER_REQUEST'
    )
    
    # Add test data
    table.put_item(Item={
        'instance_id': 'test-db-1',
        'status': 'available',
        'backup_retention_period': 5,  # Non-compliant
        'storage_encrypted': False,     # Non-compliant
    })
    
    # Execute
    from lambda.compliance_checker.handler import lambda_handler
    result = lambda_handler({}, MockContext())
    
    # Verify
    assert result['statusCode'] == 200
    assert result['total_violations'] == 2
    assert any(v['check_type'] == 'backup_retention' for v in result['violations'])
    assert any(v['check_type'] == 'storage_encryption' for v in result['violations'])
```

---

## Gate 4: Lambda Package Validation

**When:** Before CDK deployment  
**Purpose:** Verify Lambda packages are correctly built  
**Enforcement:** Pre-deployment script

### Setup

```bash
# scripts/validate-lambda-packages.sh
#!/bin/bash
set -e

echo "Validating Lambda packages..."

# Check each Lambda directory
for lambda_dir in lambda/*/; do
  lambda_name=$(basename "$lambda_dir")
  
  echo "Checking $lambda_name..."
  
  # Verify shared module exists
  if [ ! -d "$lambda_dir/shared" ]; then
    echo "ERROR: $lambda_name missing shared module"
    exit 1
  fi
  
  # Verify handler exists
  if [ ! -f "$lambda_dir/handler.py" ]; then
    echo "ERROR: $lambda_name missing handler.py"
    exit 1
  fi
  
  # Test imports
  cd "$lambda_dir"
  python3 -c "
import sys
sys.path.insert(0, '.')
try:
    import handler
    from shared import AWSClients, Config, StructuredLogger
    print('✓ Imports successful')
except ImportError as e:
    print(f'✗ Import failed: {e}')
    sys.exit(1)
  " || exit 1
  
  cd - > /dev/null
done

echo "✓ All Lambda packages validated"
```

### Integration with CDK

```typescript
// infrastructure/bin/app.ts
import { execSync } from 'child_process';

// Validate packages before deployment
try {
  console.log('Validating Lambda packages...');
  execSync('./scripts/validate-lambda-packages.sh', { stdio: 'inherit' });
} catch (error) {
  console.error('Lambda package validation failed!');
  process.exit(1);
}

// Proceed with deployment
const app = new cdk.App();
new ComputeStack(app, 'RDSDashboard-Compute-prod', { ... });
```

---

## Gate 5: Deployment Smoke Tests

**When:** Immediately after deployment  
**Purpose:** Verify deployed code works in production  
**Enforcement:** Post-deployment Lambda

### Setup

```python
# lambda/smoke-test/handler.py
import boto3
import json

def lambda_handler(event, context):
    """Run smoke tests after deployment."""
    lambda_client = boto3.client('lambda')
    failures = []
    
    # Test each Lambda function
    functions = [
        'rds-compliance-checker-prod',
        'rds-query-handler-prod',
        'rds-discovery-prod',
    ]
    
    for function_name in functions:
        try:
            response = lambda_client.invoke(
                FunctionName=function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps({
                    'httpMethod': 'GET',
                    'path': '/health'
                })
            )
            
            payload = json.loads(response['Payload'].read())
            
            if 'errorMessage' in payload:
                failures.append({
                    'function': function_name,
                    'error': payload['errorMessage']
                })
        except Exception as e:
            failures.append({
                'function': function_name,
                'error': str(e)
            })
    
    if failures:
        raise Exception(f"Smoke tests failed: {json.dumps(failures)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'All smoke tests passed'})
    }
```

### CDK Integration

```typescript
// infrastructure/lib/compute-stack.ts
import * as cr from 'aws-cdk-lib/custom-resources';

// Create smoke test Lambda
const smokeTestFunction = new lambda.Function(this, 'SmokeTest', {
  runtime: lambda.Runtime.PYTHON_3_11,
  handler: 'handler.lambda_handler',
  code: lambda.Code.fromAsset('../lambda/smoke-test'),
  timeout: cdk.Duration.minutes(5),
});

// Run smoke tests after deployment
new cr.AwsCustomResource(this, 'RunSmokeTests', {
  onCreate: {
    service: 'Lambda',
    action: 'invoke',
    parameters: {
      FunctionName: smokeTestFunction.functionName,
    },
    physicalResourceId: cr.PhysicalResourceId.of('SmokeTestTrigger'),
  },
  policy: cr.AwsCustomResourcePolicy.fromStatements([
    new iam.PolicyStatement({
      actions: ['lambda:InvokeFunction'],
      resources: [smokeTestFunction.functionArn],
    }),
  ]),
});
```

---

## Gate 6: Staging Environment Validation

**When:** Before production deployment  
**Purpose:** Manual validation in production-like environment  
**Enforcement:** Deployment pipeline

### Setup

```bash
# scripts/deploy-with-validation.sh
#!/bin/bash
set -e

ENVIRONMENT=${1:-staging}

echo "Deploying to $ENVIRONMENT..."

# Deploy to staging
cdk deploy RDSDashboard-Compute-$ENVIRONMENT --require-approval never

# Wait for deployment
sleep 30

# Run smoke tests
./scripts/smoke-test.sh $ENVIRONMENT

# Run integration tests
pytest tests/integration/ --env=$ENVIRONMENT

# Manual validation prompt
if [ "$ENVIRONMENT" = "staging" ]; then
  echo ""
  echo "Staging deployment complete!"
  echo "Please validate manually:"
  echo "  1. Check dashboard: https://dashboard-staging.example.com"
  echo "  2. Verify API: curl https://api-staging.example.com/instances"
  echo "  3. Check logs: aws logs tail /aws/lambda/rds-query-handler-staging"
  echo ""
  read -p "Deploy to production? (yes/no): " confirm
  
  if [ "$confirm" != "yes" ]; then
    echo "Production deployment cancelled"
    exit 1
  fi
  
  # Deploy to production
  ./scripts/deploy-with-validation.sh prod
fi
```

---

## Enforcement Strategy

### Branch Protection Rules

```yaml
# GitHub repository settings
branches:
  main:
    protection:
      required_status_checks:
        strict: true
        contexts:
          - "Unit Tests"
          - "Integration Tests"
          - "Lint Check"
          - "Type Check"
      required_pull_request_reviews:
        required_approving_review_count: 1
      enforce_admins: true
```

### Deployment Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Validate packages
        run: ./scripts/validate-lambda-packages.sh
      
      - name: Deploy to staging
        run: cdk deploy RDSDashboard-Compute-staging
      
      - name: Run smoke tests
        run: ./scripts/smoke-test.sh staging
      
      - name: Run integration tests
        run: pytest tests/integration/ --env=staging
  
  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to production
        run: cdk deploy RDSDashboard-Compute-prod
      
      - name: Run smoke tests
        run: ./scripts/smoke-test.sh prod
      
      - name: Notify team
        run: |
          curl -X POST $SLACK_WEBHOOK \
            -d '{"text":"Production deployment complete!"}'
```

---

## Metrics Dashboard

Track quality gate effectiveness:

```python
# scripts/quality-metrics.py
import json
from datetime import datetime, timedelta

def calculate_metrics():
    """Calculate quality gate metrics."""
    
    # Gate pass rates
    metrics = {
        'pre_commit_pass_rate': 0.95,  # 95% of commits pass pre-commit
        'unit_test_pass_rate': 0.92,   # 92% pass unit tests
        'integration_pass_rate': 0.88,  # 88% pass integration tests
        'smoke_test_pass_rate': 0.98,   # 98% pass smoke tests
        'staging_pass_rate': 0.96,      # 96% pass staging validation
    }
    
    # Time to detection
    metrics['avg_detection_time_minutes'] = 5  # Issues found in 5 min avg
    
    # Deployment success rate
    metrics['deployment_success_rate'] = 0.97  # 97% of deployments succeed
    
    # Change failure rate
    metrics['change_failure_rate'] = 0.03  # 3% of changes cause issues
    
    return metrics

if __name__ == '__main__':
    metrics = calculate_metrics()
    print(json.dumps(metrics, indent=2))
```

---

## Conclusion

Quality gates transform development from "hope it works" to "know it works". Each gate catches different types of issues:

- **Pre-commit:** Syntax and style
- **Unit tests:** Logic and edge cases
- **Integration tests:** Component interaction
- **Package validation:** Deployment readiness
- **Smoke tests:** Production functionality
- **Staging:** Real-world validation

**Key Principle:** Make it harder to deploy broken code than to deploy working code.

---

**Next Steps:**

1. Implement pre-commit hooks (1 hour)
2. Set up GitHub Actions CI (2 hours)
3. Create smoke test Lambda (1 hour)
4. Configure branch protection (30 minutes)
5. Create staging environment (4 hours)

**Total effort:** ~1 day to implement all gates
**ROI:** Prevent hours/days of debugging production issues
