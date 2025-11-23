# Post-Mortem: CloudFront 403 Errors & Lambda Import Issues

**Date:** November 20, 2025  
**Severity:** High (Production-blocking)  
**Duration:** Multiple debugging sessions  
**Status:** Resolved

## Executive Summary

Multiple code-level issues prevented the RDS Operations Dashboard from functioning in production, manifesting as CloudFront 403 errors. Root cause analysis revealed systematic gaps in our development and testing processes that allowed incompatible code to reach deployment.

---

## Issues Discovered

### 1. **Import Mismatches** (Critical)
**Problem:** Lambda functions imported `get_rds_client` as a standalone function, but it was implemented as `AWSClients.get_rds_client()` (class method).

```python
# Incorrect (what was written)
from shared.aws_clients import get_rds_client
rds = get_rds_client()

# Correct (what should have been)
from shared.aws_clients import AWSClients
rds = AWSClients.get_rds_client()
```

**Why it happened:**
- Design document specified class-based implementation
- Code was written with function-style imports
- No import validation during code generation
- Tests didn't catch the mismatch (tests weren't run)

---

### 2. **Missing Shared Module in Lambda Packages** (Critical)
**Problem:** Lambda deployment packages didn't include the `shared/` directory, causing `ModuleNotFoundError`.

**Why it happened:**
- CDK used `lambda.Code.fromAsset('../lambda/compliance-checker')` which only packages that specific directory
- Shared module was in `../lambda/shared/` (parent directory)
- No build/packaging validation step
- Assumed CDK would automatically include dependencies

---

### 3. **Config API Incompatibility** (High)
**Problem:** Code used `config.get('key')` but Config returned a dataclass without a `get()` method.

```python
# What was written
table_name = config.get('dynamodb_tables', {}).get('rds_inventory')

# What Config actually returned
config.dynamodb.inventory_table  # dataclass attribute
```

**Why it happened:**
- Config implementation changed from dict to dataclass mid-development
- Existing code wasn't updated to match new API
- No type checking or linting enabled
- No integration tests validating config usage

---

### 4. **Logger Method Name Mismatch** (Medium)
**Problem:** Code used `logger.warning()` but implementation only had `logger.warn()`.

**Why it happened:**
- Python's standard logging uses `warning()`
- Custom logger used `warn()` for brevity
- No API documentation for custom logger
- No IDE autocomplete validation

---

### 5. **Lambda Context Attribute Error** (Medium)
**Problem:** Code accessed `context.request_id` but Lambda context uses `context.aws_request_id`.

**Why it happened:**
- Incorrect assumption about Lambda context API
- No reference to AWS Lambda documentation
- No type hints for Lambda context
- Tests used mock context with wrong attributes

---

### 6. **API Gateway Endpoint Type** (High)
**Problem:** Internal API Gateway used EDGE endpoint (with CloudFront), causing CloudFront to block BFF requests.

**Why it happened:**
- CDK defaults to EDGE endpoint when not specified
- Design didn't explicitly specify REGIONAL endpoint
- No understanding of EDGE vs REGIONAL implications
- No network architecture review

---

## Root Cause Analysis

### Why These Issues Weren't Caught Earlier

#### 1. **No Unit Tests Executed**
- Tests were written but never run before deployment
- No CI/CD pipeline enforcing test execution
- Manual testing focused on happy paths only
- Assumed code would work if it "looked right"

#### 2. **No Integration Testing**
- Lambda functions never invoked in isolation before deployment
- No end-to-end testing of request flow
- First real test was in production environment
- No staging environment for validation

#### 3. **No Static Analysis**
- No linting (pylint, flake8) to catch import errors
- No type checking (mypy) to catch type mismatches
- No IDE warnings enabled or heeded
- Code review focused on logic, not syntax

#### 4. **Incomplete Code Review**
- AI-generated code assumed to be correct
- No human validation of imports and APIs
- No cross-reference with design documents
- No verification against AWS documentation

#### 5. **Deployment Without Validation**
- CDK deploy succeeded (infrastructure created)
- No smoke tests after deployment
- No health checks or monitoring alerts
- Assumed "deployed = working"

#### 6. **Incremental Development Issues**
- Shared module created after Lambda functions
- Config API changed without updating consumers
- No dependency tracking between components
- No impact analysis for API changes

---

## What Should Have Prevented These Issues

### Pre-Commit Checks (Should Have Caught 80% of Issues)

```bash
# Python linting
pylint lambda/**/*.py --errors-only

# Type checking
mypy lambda/ --strict

# Import validation
python -m py_compile lambda/**/*.py

# Test execution
pytest lambda/tests/ --tb=short
```

### Build-Time Validation (Should Have Caught 95% of Issues)

```bash
# Package validation
python -c "import sys; sys.path.append('lambda/shared'); from aws_clients import AWSClients"

# Lambda package testing
zip -r lambda.zip lambda/compliance-checker lambda/shared
python -m zipfile -t lambda.zip

# CDK synth validation
cdk synth --strict
```

### Deployment-Time Validation (Should Have Caught 100% of Issues)

```bash
# Smoke tests after deployment
aws lambda invoke --function-name rds-compliance-checker-prod test.json
cat test.json | jq '.errorMessage'

# Health check endpoints
curl -f https://api.example.com/health || exit 1

# Integration tests
pytest tests/integration/ --env=prod
```

---

## Process Improvements Required

### 1. **Mandatory Pre-Deployment Testing**

**Policy:** No code reaches production without passing all tests.

**Implementation:**
```yaml
# .github/workflows/test.yml
name: Test Before Deploy
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Lint Python
        run: pylint lambda/ --fail-under=8.0
      
      - name: Type Check
        run: mypy lambda/ --strict
      
      - name: Unit Tests
        run: pytest lambda/tests/ --cov=lambda --cov-fail-under=70
      
      - name: Integration Tests
        run: pytest tests/integration/
      
      - name: Package Validation
        run: ./scripts/validate-lambda-packages.sh
```

**Enforcement:**
- GitHub branch protection: require passing tests
- CDK deploy blocked if tests fail
- Manual override requires dual approval

---

### 2. **Lambda Packaging Standards**

**Policy:** All Lambda functions must include shared dependencies.

**Implementation:**
```typescript
// infrastructure/lib/compute-stack.ts
const lambdaCode = lambda.Code.fromAsset('../lambda', {
  bundling: {
    image: lambda.Runtime.PYTHON_3_11.bundlingImage,
    command: [
      'bash', '-c',
      'pip install -r requirements.txt -t /asset-output && ' +
      'cp -r /asset-input/compliance-checker /asset-output/ && ' +
      'cp -r /asset-input/shared /asset-output/'
    ],
  },
});
```

**Validation Script:**
```bash
# scripts/validate-lambda-packages.sh
for dir in lambda/*/; do
  if [ ! -d "$dir/shared" ]; then
    echo "ERROR: $dir missing shared module"
    exit 1
  fi
done
```

---

### 3. **API Contract Testing**

**Policy:** All module interfaces must have contract tests.

**Implementation:**
```python
# lambda/tests/test_contracts.py
def test_aws_clients_interface():
    """Verify AWSClients provides expected methods."""
    from shared.aws_clients import AWSClients
    
    assert hasattr(AWSClients, 'get_rds_client')
    assert hasattr(AWSClients, 'get_dynamodb_client')
    assert callable(AWSClients.get_rds_client)

def test_config_interface():
    """Verify Config provides expected attributes."""
    from shared.config import Config
    
    config = Config.load()
    assert hasattr(config, 'dynamodb')
    assert hasattr(config.dynamodb, 'inventory_table')
    assert hasattr(config, 'get')  # Backward compatibility

def test_logger_interface():
    """Verify Logger provides expected methods."""
    from shared.logger import StructuredLogger
    
    logger = StructuredLogger('test')
    assert hasattr(logger, 'info')
    assert hasattr(logger, 'warn')
    assert hasattr(logger, 'error')
```

---

### 4. **Deployment Smoke Tests**

**Policy:** Every deployment must pass smoke tests before marking as successful.

**Implementation:**
```bash
# scripts/smoke-test.sh
#!/bin/bash
set -e

echo "Running smoke tests..."

# Test each Lambda function
for func in rds-compliance-checker-prod rds-query-handler-prod; do
  echo "Testing $func..."
  aws lambda invoke \
    --function-name $func \
    --payload '{"httpMethod":"GET","path":"/health"}' \
    response.json
  
  if grep -q "errorMessage" response.json; then
    echo "ERROR: $func failed smoke test"
    cat response.json
    exit 1
  fi
done

# Test API endpoints
curl -f https://api.example.com/instances || exit 1

echo "All smoke tests passed!"
```

**Integration with CDK:**
```typescript
// After deployment
new cdk.CustomResource(this, 'SmokeTest', {
  serviceToken: smokeTestFunction.functionArn,
  properties: {
    apiUrl: api.url,
    functions: [complianceFunction.functionName],
  },
});
```

---

### 5. **Type Safety Enforcement**

**Policy:** All Python code must pass mypy strict type checking.

**Implementation:**
```python
# lambda/shared/aws_clients.py
from typing import Optional
import boto3

class AWSClients:
    @staticmethod
    def get_rds_client(
        region: Optional[str] = None,
        account_id: Optional[str] = None,
        role_name: Optional[str] = None,
        external_id: Optional[str] = None
    ) -> boto3.client:
        """Get RDS client with type hints."""
        ...
```

```ini
# mypy.ini
[mypy]
python_version = 3.11
strict = True
warn_return_any = True
warn_unused_configs = True
disallow_untyped_defs = True
```

---

### 6. **Documentation Requirements**

**Policy:** All shared modules must have API documentation and usage examples.

**Implementation:**
```python
# lambda/shared/README.md
# Shared Modules

## AWSClients

Factory class for creating AWS service clients.

### Usage

```python
from shared.aws_clients import AWSClients

# Local account
rds = AWSClients.get_rds_client()

# Cross-account
rds = AWSClients.get_rds_client(
    account_id='123456789012',
    role_name='CrossAccountRole',
    external_id='unique-id'
)
```

### Available Methods

- `get_rds_client()` - Returns boto3 RDS client
- `get_dynamodb_client()` - Returns boto3 DynamoDB client
- `get_s3_client()` - Returns boto3 S3 client
```

---

### 7. **Staging Environment**

**Policy:** All changes must be tested in staging before production.

**Implementation:**
```bash
# Deploy to staging first
cdk deploy --context environment=staging

# Run integration tests
pytest tests/integration/ --env=staging

# Manual validation
./scripts/manual-validation.sh staging

# Deploy to production only if staging passes
cdk deploy --context environment=prod
```

---

## Recommended Testing Strategy

### Test Pyramid

```
                    /\
                   /  \
                  / E2E \          10% - End-to-end tests
                 /______\
                /        \
               /Integration\       20% - Integration tests
              /____________\
             /              \
            /   Unit Tests   \     70% - Unit tests
           /__________________\
```

### Test Coverage Requirements

| Component | Unit Tests | Integration Tests | E2E Tests |
|-----------|-----------|-------------------|-----------|
| Lambda Functions | 80% | Required | Optional |
| Shared Modules | 90% | Required | N/A |
| API Endpoints | N/A | Required | Required |
| Infrastructure | N/A | Smoke Tests | Required |

---

## Action Items

### Immediate (This Week)

- [ ] Create `scripts/validate-lambda-packages.sh`
- [ ] Add pre-commit hooks for linting and type checking
- [ ] Write contract tests for all shared modules
- [ ] Create smoke test script for post-deployment validation
- [ ] Document all shared module APIs

### Short-term (This Month)

- [ ] Set up GitHub Actions CI/CD pipeline
- [ ] Create staging environment
- [ ] Implement automated integration tests
- [ ] Add mypy strict type checking to all Python code
- [ ] Create Lambda packaging standards document

### Long-term (This Quarter)

- [ ] Implement full test pyramid (70/20/10 split)
- [ ] Set up monitoring and alerting for production
- [ ] Create automated rollback on smoke test failure
- [ ] Implement blue-green deployments
- [ ] Add performance testing to CI/CD

---

## Lessons Learned

### What Went Wrong

1. **Over-reliance on AI-generated code** - Assumed correctness without validation
2. **No testing culture** - Tests written but never executed
3. **Deployment without validation** - "It deployed" ≠ "It works"
4. **Missing integration points** - Components tested in isolation only
5. **No staging environment** - First test was in production

### What Went Right

1. **Comprehensive logging** - Made debugging possible
2. **Systematic debugging** - Followed errors from frontend to backend
3. **Quick iteration** - Fixed issues rapidly once identified
4. **Documentation** - Created scripts to prevent recurrence

### Key Takeaways

> **"Deployed successfully" is not the same as "working correctly"**

> **"Tests exist" is not the same as "tests pass"**

> **"Code looks right" is not the same as "code runs right"**

---

## Metrics to Track

### Quality Metrics

- **Test Coverage:** Target 80% for Lambda functions
- **Type Coverage:** Target 100% with mypy strict
- **Lint Score:** Target 9.0/10 with pylint
- **Deployment Success Rate:** Target 95% (smoke tests pass)

### Process Metrics

- **Time to Detection:** How long until issues found (target: < 5 min)
- **Time to Resolution:** How long to fix issues (target: < 1 hour)
- **Deployment Frequency:** How often we deploy (target: daily)
- **Change Failure Rate:** % of deployments causing issues (target: < 5%)

---

## Conclusion

These issues were **preventable** with proper testing and validation processes. The root cause wasn't the code itself, but the **absence of quality gates** that should have caught these issues before deployment.

**Key Principle:** Every line of code should pass through multiple validation layers before reaching production:

1. **Developer validation** - Linting, type checking, unit tests
2. **CI/CD validation** - Automated tests, integration tests
3. **Staging validation** - Manual testing, smoke tests
4. **Production validation** - Health checks, monitoring

By implementing these processes, we can prevent similar issues in the future and build more reliable systems.

---

**Document Owner:** Development Team  
**Last Updated:** November 20, 2025  
**Next Review:** December 20, 2025
