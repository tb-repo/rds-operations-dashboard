# Environment Classification Guide

**Purpose:** Explains how the RDS Operations Dashboard differentiates between production and non-production environments.

## Overview

The system uses **AWS resource-level tags** (not local code tags) to identify the environment type of each RDS instance. These tags are stored in AWS and retrieved via the RDS API during the discovery process. This tag-based approach provides flexibility and follows AWS best practices for resource organization.

### Important: These Are AWS Resource Tags

- **Storage Location:** Tags are stored in AWS on the RDS instance itself
- **Retrieval Method:** Retrieved via AWS RDS API (`describe_db_instances` and `list_tags_for_resource`)
- **Not Local:** These are NOT local configuration files or code-level tags
- **Persistent:** Tags persist with the RDS instance in AWS

## Tag-Based Classification

### Primary Tag: `Environment`

The system reads the `Environment` tag from each RDS instance to determine its classification.

**Tag Format:**
```
Key: Environment
Value: Production | Development | Test | Staging | POC | Sandbox
```

### Supported Environment Values

| Environment Value | Classification | Compliance Rules |
|-------------------|----------------|------------------|
| `Production` | Production | Strictest rules (Multi-AZ required, deletion protection required) |
| `Staging` | Non-Production | Standard rules (deletion protection required) |
| `Development` | Non-Production | Standard rules (deletion protection required) |
| `Test` | Non-Production | Standard rules (deletion protection required) |
| `POC` | Non-Production | Relaxed rules (deletion protection NOT required) |
| `Sandbox` | Non-Production | Relaxed rules (deletion protection NOT required) |

**Note:** Tag values are case-insensitive (converted to lowercase for comparison).

## How It Works in Code

### 1. Tag Retrieval from AWS

When the discovery service scans RDS instances, it retrieves tags from AWS using the RDS API:

```python
# Discovery service calls AWS RDS API
import boto3

rds = boto3.client('rds', region_name='ap-southeast-1')

# Step 1: Get RDS instance details
response = rds.describe_db_instances(
    DBInstanceIdentifier='prod-postgres-01'
)

db_instance = response['DBInstances'][0]

# Step 2: Extract tags from the response
# Tags are included in the describe_db_instances response
tags_list = db_instance.get('TagList', [])

# Step 3: Convert to dictionary format
tags = {tag['Key']: tag['Value'] for tag in tags_list}

# Result stored in DynamoDB:
instance_metadata = {
    'instance_id': 'prod-postgres-01',
    'engine': 'postgres',
    'region': 'ap-southeast-1',
    'account_id': '123456789012',
    'tags': {
        'Environment': 'Production',  # ← Retrieved from AWS
        'Team': 'DataPlatform',
        'CostCenter': 'CC-1234'
    }
}
```

**Key Points:**
- Tags are retrieved from AWS, not from local configuration
- The `describe_db_instances` API call includes `TagList` in the response
- Tags are stored in DynamoDB during discovery for fast access
- Compliance checker reads tags from DynamoDB (which came from AWS)

### 2. Environment Extraction

Compliance checks extract and normalize the environment tag:

```python
# From compliance-checker/checks.py
tags = instance.get('tags', {})
environment = tags.get('Environment', '').lower()  # Convert to lowercase

# Now environment = 'production'
```

### 3. Rule Application

Different compliance rules apply based on the environment:

#### Multi-AZ Check (Production Only)

```python
def _check_multi_az(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
    violations = []
    multi_az = instance.get('multi_az', False)
    tags = instance.get('tags', {})
    environment = tags.get('Environment', '').lower()
    
    # Only enforce for production
    if environment == 'production' and not multi_az:
        violations.append({
            'instance_id': instance['instance_id'],
            'check_type': 'multi_az',
            'severity': 'High',
            'message': "Multi-AZ is not enabled for production instance"
        })
    
    return violations
```

**Result:** Multi-AZ is only required for instances tagged with `Environment: Production`

#### Deletion Protection Check (Except POC/Sandbox)

```python
def _check_deletion_protection(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
    violations = []
    deletion_protection = instance.get('deletion_protection', False)
    tags = instance.get('tags', {})
    environment = tags.get('Environment', '').lower()
    
    # Skip check for POC and Sandbox
    if environment in ['poc', 'sandbox']:
        return violations  # No violation for POC/Sandbox
    
    if not deletion_protection:
        violations.append({
            'instance_id': instance['instance_id'],
            'check_type': 'deletion_protection',
            'severity': 'High',
            'message': f"Deletion protection is not enabled for {environment} instance"
        })
    
    return violations
```

**Result:** Deletion protection is required for all environments EXCEPT POC and Sandbox

## Compliance Rules by Environment

### Production Environment

**Tag:** `Environment: Production`

**Compliance Requirements:**
- ✅ Backup retention >= 7 days (Critical)
- ✅ Storage encryption enabled (Critical)
- ✅ PostgreSQL version compliance (High/Critical)
- ✅ **Multi-AZ enabled** (High) - **Production Only**
- ✅ Deletion protection enabled (High)
- ✅ Pending maintenance monitoring (Medium)

### Non-Production (Dev, Test, Staging)

**Tags:** `Environment: Development | Test | Staging`

**Compliance Requirements:**
- ✅ Backup retention >= 7 days (Critical)
- ✅ Storage encryption enabled (Critical)
- ✅ PostgreSQL version compliance (High/Critical)
- ⚪ Multi-AZ NOT required
- ✅ Deletion protection enabled (High)
- ✅ Pending maintenance monitoring (Medium)

### POC / Sandbox

**Tags:** `Environment: POC | Sandbox`

**Compliance Requirements:**
- ✅ Backup retention >= 7 days (Critical)
- ✅ Storage encryption enabled (Critical)
- ✅ PostgreSQL version compliance (High/Critical)
- ⚪ Multi-AZ NOT required
- ⚪ Deletion protection NOT required
- ✅ Pending maintenance monitoring (Medium)

## Tagging Best Practices

### 1. Consistent Naming

Use consistent capitalization for environment tags:

**Recommended:**
```
Environment: Production
Environment: Development
Environment: Test
Environment: Staging
Environment: POC
Environment: Sandbox
```

**Also Accepted (case-insensitive):**
```
Environment: production
Environment: PRODUCTION
Environment: dev (will be treated as 'dev', not 'development')
```

### 2. Required Tags

Every RDS instance should have at minimum:

```
Environment: <value>
Team: <team-name>
CostCenter: <cost-center-id>
```

### 3. Tag Application

Tags can be applied:

**During Instance Creation:**
```bash
aws rds create-db-instance \
  --db-instance-identifier my-instance \
  --tags Key=Environment,Value=Production \
         Key=Team,Value=DataPlatform \
         Key=CostCenter,Value=CC-1234
```

**After Instance Creation:**
```bash
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:region:account:db:my-instance \
  --tags Key=Environment,Value=Production
```

## What If an AWS Resource is Not Tagged?

### Behavior for Untagged Instances

If an RDS instance has NO `Environment` tag in AWS:

```python
tags = instance.get('tags', {})  # Returns empty dict {}
environment = tags.get('Environment', '').lower()  # Returns empty string ''

# Result: environment = ''
```

### Compliance Rules Applied to Untagged Instances

| Check | Applied? | Severity | Reason |
|-------|----------|----------|--------|
| Backup Retention | ✅ Yes | Critical | Always enforced |
| Storage Encryption | ✅ Yes | Critical | Always enforced |
| PostgreSQL Version | ✅ Yes | High/Critical | Always enforced |
| **Multi-AZ** | ❌ **No** | - | Only enforced if `environment == 'production'` |
| **Deletion Protection** | ✅ **Yes** | High | Enforced unless `environment in ['poc', 'sandbox']` |
| Pending Maintenance | ✅ Yes | Medium | Always monitored |

### Key Point: Untagged = Treated as Non-Production with Standard Rules

**What This Means:**
- ✅ **Safer Default:** Untagged instances get deletion protection (better than no protection)
- ❌ **No Multi-AZ Requirement:** Won't flag missing Multi-AZ (could be a gap for production instances)
- ⚠️ **Potential Issue:** If a production instance is untagged, it won't get production-level checks

### Example Scenarios

#### Scenario 1: Untagged Production Instance (Problem!)

```
Instance: prod-postgres-01
Tags: (none)
```

**Result:**
- Multi-AZ check: **SKIPPED** ❌ (should be checked!)
- Deletion protection: Required ✅
- Other checks: Applied ✅

**Risk:** Production instance not getting full production compliance checks!

#### Scenario 2: Untagged Development Instance (OK)

```
Instance: dev-mysql-01
Tags: (none)
```

**Result:**
- Multi-AZ check: Skipped ✅ (correct for dev)
- Deletion protection: Required ✅ (good safety measure)
- Other checks: Applied ✅

**Risk:** Low - appropriate rules applied

#### Scenario 3: Untagged POC Instance (Problem!)

```
Instance: poc-test-db
Tags: (none)
```

**Result:**
- Deletion protection: **REQUIRED** ❌ (should be optional for POC!)
- Other checks: Applied ✅

**Risk:** POC instance flagged for deletion protection when it shouldn't be

### Recommendations for Untagged Resources

#### 1. Implement Tagging Policy (Recommended)

**Require all RDS instances to have Environment tag:**

```bash
# Tag existing instances
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:region:account:db:instance-id \
  --tags Key=Environment,Value=Production

# Use AWS Config to enforce tagging
# Create AWS Config rule: required-tags
```

#### 2. Add Compliance Check for Missing Tags

Add a new compliance check to flag untagged instances:

```python
def _check_required_tags(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Check if required tags are present."""
    violations = []
    tags = instance.get('tags', {})
    
    if 'Environment' not in tags:
        violations.append({
            'instance_id': instance['instance_id'],
            'check_type': 'missing_environment_tag',
            'severity': 'High',
            'message': "Environment tag is missing - cannot determine environment type",
            'remediation': f"Add Environment tag: aws rds add-tags-to-resource --resource-name arn:aws:rds:{{region}}:{{account}}:db:{instance['instance_id']} --tags Key=Environment,Value=Production"
        })
    
    return violations
```

#### 3. Use Account-Based Classification as Fallback

If tagging is not feasible, use AWS account ID as fallback:

```python
def _get_environment(self, instance: Dict[str, Any]) -> str:
    """Get environment with fallback to account-based classification."""
    tags = instance.get('tags', {})
    environment = tags.get('Environment', '').lower()
    
    # If no tag, use account-based classification
    if not environment:
        account_id = instance.get('account_id')
        production_accounts = ['123456789012', '234567890123']
        
        if account_id in production_accounts:
            return 'production'
        else:
            return 'non-production'
    
    return environment
```

### Missing or Invalid Tags

### If Environment Tag is Missing

```python
tags = instance.get('tags', {})
environment = tags.get('Environment', '').lower()

# If tag is missing, environment = ''
```

**Behavior:**
- Multi-AZ check: Skipped (not 'production')
- Deletion protection: **Required** (not in ['poc', 'sandbox'])
- All other checks: Applied normally

**Recommendation:** Always tag instances to ensure correct compliance rules are applied.

### If Environment Tag Has Unknown Value

Example: `Environment: QA`

**Behavior:**
- Treated as non-production
- Multi-AZ: NOT required
- Deletion protection: **Required** (not POC/Sandbox)
- All other checks: Applied

## Configuration

### Customizing Environment Values

To add or modify environment classifications, update the compliance checks:

**File:** `lambda/compliance-checker/checks.py`

```python
# Add new environment to POC/Sandbox exemption list
if environment in ['poc', 'sandbox', 'demo', 'training']:
    return violations  # Skip deletion protection check

# Add new production-like environment
if environment in ['production', 'prod', 'live']:
    # Enforce Multi-AZ
```

### Account-Level Classification (Alternative Approach)

If you prefer to classify by AWS account instead of tags:

```python
# In checks.py
production_accounts = ['123456789012', '234567890123']
account_id = instance.get('account_id')

if account_id in production_accounts:
    # Apply production rules
```

**Note:** Tag-based approach is more flexible and follows AWS best practices.

## Verification

### Check Instance Tags

```bash
# View tags for an instance
aws rds list-tags-for-resource \
  --resource-name arn:aws:rds:region:account:db:instance-id

# Output:
{
  "TagList": [
    {
      "Key": "Environment",
      "Value": "Production"
    },
    {
      "Key": "Team",
      "Value": "DataPlatform"
    }
  ]
}
```

### Check Compliance Report

The compliance report shows which environment each instance belongs to:

```json
{
  "detailed_violations": [
    {
      "instance_id": "prod-postgres-01",
      "check_type": "multi_az",
      "severity": "High",
      "message": "Multi-AZ is not enabled for production instance"
    }
  ]
}
```

## Summary

| Aspect | Implementation |
|--------|----------------|
| **Classification Method** | AWS Resource Tags |
| **Primary Tag** | `Environment` |
| **Case Sensitivity** | Case-insensitive (converted to lowercase) |
| **Production Identifier** | `Environment: Production` |
| **POC/Sandbox Identifiers** | `Environment: POC` or `Environment: Sandbox` |
| **Default Behavior** | If tag missing, treated as non-production with standard rules |
| **Flexibility** | Easy to add new environment types by updating code |

## Related Documentation

- [Compliance Checker Implementation](../TASK-5-SUMMARY.md)
- [AWS Tagging Best Practices](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
- [RDS Tagging](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Tagging.html)

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-11-13  
**Maintained By:** DBA Team
