# Environment Classification FAQ

## Q1: Is it a local code-level tag or AWS resource-level tag?

### Answer: AWS Resource-Level Tags

**These are AWS resource-level tags stored in AWS, NOT local code tags.**

### How It Works

```
AWS RDS Instance (in AWS Cloud)
    ↓
Tags stored on the resource:
  - Environment: Production
  - Team: DataPlatform
  - CostCenter: CC-1234
    ↓
Discovery Service calls AWS API:
  rds.describe_db_instances()
    ↓
Tags retrieved and stored in DynamoDB
    ↓
Compliance Checker reads from DynamoDB
```

### Verification

```bash
# View tags directly in AWS
aws rds list-tags-for-resource \
  --resource-name arn:aws:rds:region:account:db:instance-id

# Output shows tags stored in AWS:
{
  "TagList": [
    {"Key": "Environment", "Value": "Production"}
  ]
}
```

---

## Q2: What if an AWS resource is not tagged?

### Answer: Multiple Fallback Options Available

The system now supports **4 classification methods** with automatic fallback:

### Method 1: AWS Tags (Preferred)
```python
tags = instance.get('tags', {})
if 'Environment' in tags:
    environment = tags['Environment']  # ← From AWS
```

### Method 2: Manual Instance Mapping
```json
{
  "instance_mappings": {
    "my-database-01": "production",
    "test-db-02": "development"
  }
}
```

### Method 3: Account-Based Classification
```json
{
  "account_mappings": {
    "123456789012": "production",
    "234567890123": "development"
  }
}
```

### Method 4: Naming Pattern Matching
```json
{
  "naming_patterns": {
    "production": ["^prod-", "-prod$"],
    "development": ["^dev-", "-dev$"]
  }
}
```

### Priority Order

```
1. AWS Tags (if present)
   ↓ (if missing)
2. Manual Instance Mapping
   ↓ (if not mapped)
3. Account-Based Classification
   ↓ (if not mapped)
4. Naming Pattern Matching
   ↓ (if no match)
5. Default Environment ("non-production")
```

---

## Q3: Can app owners manually classify instances?

### Answer: Yes! Multiple Ways

### Option A: Configuration File (Immediate)

**File:** `config/environment-mapping.json`

```json
{
  "instance_mappings": {
    "my-special-db": "production",
    "legacy-system-db": "production",
    "experimental-db": "poc"
  }
}
```

**Pros:**
- ✅ Works immediately
- ✅ No AWS changes needed
- ✅ Version controlled (Git)

**Cons:**
- ❌ Requires code deployment to update
- ❌ Not self-service for app owners

### Option B: DynamoDB Manual Overrides (Future Enhancement)

Create a `environment_overrides` table:

```json
{
  "instance_id": "my-database-01",
  "environment": "production",
  "override_reason": "Critical customer-facing database",
  "updated_by": "john.doe@company.com",
  "updated_at": "2025-11-13T10:30:00Z",
  "approved_by": "manager@company.com"
}
```

**Pros:**
- ✅ Self-service via dashboard UI
- ✅ No code deployment needed
- ✅ Audit trail built-in
- ✅ Approval workflow possible

**Cons:**
- ❌ Requires additional implementation

### Option C: Dashboard UI (Future Enhancement)

Add UI feature in the dashboard:

```
Instance Detail Page
┌─────────────────────────────────────────┐
│ Instance: my-database-01                │
│ Current Classification: development     │
│ Source: naming_pattern                  │
│                                         │
│ [Change Environment ▼]                  │
│   ○ Production                          │
│   ● Development                         │
│   ○ Test                                │
│   ○ POC                                 │
│                                         │
│ Reason: [text field]                    │
│ [Save] [Cancel]                         │
└─────────────────────────────────────────┘
```

---

## Implementation Status

### ✅ Currently Implemented
- AWS tag-based classification
- Fallback to default for untagged instances

### ✨ New Implementation (Just Added)
- `environment_classifier.py` module with 4 classification methods
- `environment-mapping-example.json` configuration template
- Priority-based fallback system

### 🔮 Future Enhancements
- Dashboard UI for manual classification
- DynamoDB override table
- Approval workflow for production classification
- Classification audit trail

---

## Quick Start Guide

### If You CAN'T Use AWS Tags

**Step 1:** Copy the example configuration

```bash
cp config/environment-mapping-example.json config/environment-mapping.json
```

**Step 2:** Choose your classification method

**Option A - Account-Based (Simplest):**
```json
{
  "account_mappings": {
    "123456789012": "production",
    "234567890123": "development"
  }
}
```

**Option B - Naming Patterns:**
```json
{
  "naming_patterns": {
    "production": ["^prod-", "-prod$"],
    "development": ["^dev-", "-dev$"]
  }
}
```

**Option C - Manual Mapping:**
```json
{
  "instance_mappings": {
    "database-01": "production",
    "database-02": "development"
  }
}
```

**Step 3:** Update compliance checker to use classifier

```python
from shared.environment_classifier import EnvironmentClassifier

classifier = EnvironmentClassifier(config)
environment = classifier.get_environment(instance)
```

### If You CAN Use AWS Tags (Recommended)

**Just tag your RDS instances:**

```bash
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:region:account:db:instance-id \
  --tags Key=Environment,Value=Production
```

The system will automatically use tags (highest priority).

---

## Summary

| Question | Answer |
|----------|--------|
| **Tag Type?** | AWS resource-level tags (stored in AWS, not code) |
| **If Untagged?** | Falls back to: manual mapping → account mapping → naming pattern → default |
| **Manual Control?** | Yes! Via configuration file or future dashboard UI |
| **Deploy in Root?** | No! Can deploy in any account (Tools/Shared Services recommended) |
| **Flexibility?** | High - supports 4 classification methods with priority fallback |

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-11-13  
**Maintained By:** DBA Team
