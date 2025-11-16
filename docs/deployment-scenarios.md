# Deployment Scenarios and Alternatives

## Scenario A: Deploying in Non-Management Account

### Overview

The RDS Operations Dashboard does **NOT** need to be deployed in the management/root account. It can be deployed in any AWS account, commonly:

- **Tools Account** (Recommended)
- **Shared Services Account**
- **Operations Account**
- **Security Account**
- Any dedicated monitoring account

### Architecture: Cross-Account Access

```
┌─────────────────────────────────────────────────────────┐
│  Tools Account (Dashboard Deployed Here)                │
│  ┌────────────────────────────────────────────────────┐ │
│  │  RDS Operations Dashboard                          │ │
│  │  - Lambda Functions                                │ │
│  │  - DynamoDB Tables                                 │ │
│  │  - S3 Buckets                                      │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────┬──────────────────────────────────────┘
                   │ Assumes Cross-Account Roles
        ┌──────────┼──────────┬──────────┬──────────┐
        ↓          ↓          ↓          ↓          ↓
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │  Prod   │ │   Dev   │ │  Test   │ │ Staging │ │   POC   │
   │ Account │ │ Account │ │ Account │ │ Account │ │ Account │
   │         │ │         │ │         │ │         │ │         │
   │ RDS     │ │ RDS     │ │ RDS     │ │ RDS     │ │ RDS     │
   │ Instances│ │ Instances│ │ Instances│ │ Instances│ │ Instances│
   └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

### Configuration

**1. Deploy Dashboard in Tools Account**

```bash
# In Tools Account (e.g., 999888777666)
cd infrastructure
cdk deploy --all --context environment=prod
```

**2. Create Cross-Account Roles in Target Accounts**

Each target account needs an IAM role that trusts the Tools Account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::999888777666:role/RDSDashboard-DiscoveryRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "your-unique-external-id"
        }
      }
    }
  ]
}
```

**3. Configure Target Accounts**

Update `config/dashboard-config.json`:

```json
{
  "target_accounts": [
    {
      "account_id": "123456789012",
      "account_name": "Production",
      "role_arn": "arn:aws:iam::123456789012:role/RDSDashboard-CrossAccountRole",
      "external_id": "your-unique-external-id",
      "regions": ["ap-southeast-1", "eu-west-2"]
    },
    {
      "account_id": "234567890123",
      "account_name": "Development",
      "role_arn": "arn:aws:iam::234567890123:role/RDSDashboard-CrossAccountRole",
      "external_id": "your-unique-external-id",
      "regions": ["ap-southeast-1"]
    }
  ]
}
```

### Benefits of Tools Account Deployment

✅ **Security Isolation** - Dashboard separate from production workloads  
✅ **No Root Account Risk** - Management account remains minimal  
✅ **Easier Management** - Dedicated account for operational tools  
✅ **Cost Tracking** - Clear cost attribution for monitoring tools  
✅ **Access Control** - Separate IAM policies for dashboard users

---

## Scenario B: Manual Environment Classification

### Overview

If AWS tagging is not possible or practical, the system supports **manual environment classification** through configuration files.

### Solution 1: Configuration-Based Classification (Recommended)

Create an environment mapping configuration file:

**File:** `config/environment-mapping.json`

```json
{
  "classification_method": "manual",
  "instance_mappings": {
    "prod-postgres-01": "production",
    "prod-mysql-main": "production",
    "prod-oracle-db": "production",
    "dev-postgres-01": "development",
    "dev-mysql-test": "development",
    "test-db-01": "test",
    "test-db-02": "test",
    "poc-experiment": "poc",
    "sandbox-db": "sandbox"
  },
  "account_mappings": {
    "123456789012": "production",
    "234567890123": "development",
    "345678901234": "test",
    "456789012345": "poc"
  },
  "naming_patterns": {
    "production": ["^prod-", "^prd-", "-prod$", "-prd$"],
    "development": ["^dev-", "^development-", "-dev$"],
    "test": ["^test-", "^tst-", "-test$"],
    "staging": ["^stg-", "^staging-", "-stg$"],
    "poc": ["^poc-", "^demo-", "-poc$"],
    "sandbox": ["^sandbox-", "^sbx-", "-sandbox$"]
  },
  "default_environment": "non-production"
}
```

### Solution 2: Account-Based Classification

Map entire AWS accounts to environments:

```json
{
  "classification_method": "account",
  "account_environments": {
    "123456789012": {
      "environment": "production",
      "description": "Production Account"
    },
    "234567890123": {
      "environment": "development",
      "description": "Development Account"
    },
    "345678901234": {
      "environment": "test",
      "description": "Test Account"
    },
    "456789012345": {
      "environment": "poc",
      "description": "POC/Sandbox Account"
    }
  }
}
```

### Solution 3: Naming Convention-Based

Use instance naming patterns to determine environment:

```json
{
  "classification_method": "naming",
  "patterns": {
    "production": {
      "prefixes": ["prod-", "prd-", "p-"],
      "suffixes": ["-prod", "-prd", "-p"],
      "contains": []
    },
    "development": {
      "prefixes": ["dev-", "d-"],
      "suffixes": ["-dev", "-d"],
      "contains": []
    },
    "test": {
      "prefixes": ["test-", "tst-", "t-"],
      "suffixes": ["-test", "-tst", "-t"],
      "contains": []
    },
    "poc": {
      "prefixes": ["poc-", "demo-", "exp-"],
      "suffixes": ["-poc", "-demo"],
      "contains": ["poc", "demo", "experiment"]
    }
  }
}
```

### Implementation: Enhanced Environment Classifier

Create a new module: `lambda/shared/environment_classifier.py`

```python
#!/usr/bin/env python3
"""
Environment Classifier

Determines environment type using multiple methods:
1. AWS Tags (preferred)
2. Manual configuration mapping
3. Account-based classification
4. Naming pattern matching
"""

import json
import re
from typing import Dict, Any, Optional


class EnvironmentClassifier:
    """Classify RDS instances into environments using multiple methods."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize classifier with configuration.
        
        Args:
            config: Configuration including environment mappings
        """
        self.config = config
        self.classification_method = config.get('classification_method', 'tags')
        self.instance_mappings = config.get('instance_mappings', {})
        self.account_mappings = config.get('account_mappings', {})
        self.naming_patterns = config.get('naming_patterns', {})
        self.default_environment = config.get('default_environment', 'non-production')
    
    def get_environment(self, instance: Dict[str, Any]) -> str:
        """
        Determine environment for an instance using configured method.
        
        Priority order:
        1. AWS Tags (if present)
        2. Manual instance mapping
        3. Account-based classification
        4. Naming pattern matching
        5. Default environment
        
        Args:
            instance: RDS instance metadata
            
        Returns:
            str: Environment type (lowercase)
        """
        instance_id = instance.get('instance_id', '')
        account_id = instance.get('account_id', '')
        tags = instance.get('tags', {})
        
        # Method 1: AWS Tags (highest priority)
        if 'Environment' in tags:
            return tags['Environment'].lower()
        
        # Method 2: Manual instance mapping
        if instance_id in self.instance_mappings:
            return self.instance_mappings[instance_id].lower()
        
        # Method 3: Account-based classification
        if account_id in self.account_mappings:
            return self.account_mappings[account_id].lower()
        
        # Method 4: Naming pattern matching
        pattern_env = self._match_naming_pattern(instance_id)
        if pattern_env:
            return pattern_env.lower()
        
        # Method 5: Default
        return self.default_environment.lower()
    
    def _match_naming_pattern(self, instance_id: str) -> Optional[str]:
        """
        Match instance ID against naming patterns.
        
        Args:
            instance_id: RDS instance identifier
            
        Returns:
            str: Matched environment or None
        """
        for environment, patterns in self.naming_patterns.items():
            # Check prefixes
            for prefix in patterns:
                if instance_id.startswith(prefix):
                    return environment
            
            # Check suffixes
            for suffix in patterns:
                if instance_id.endswith(suffix):
                    return environment
            
            # Check regex patterns
            for pattern in patterns:
                if re.search(pattern, instance_id, re.IGNORECASE):
                    return environment
        
        return None
    
    def get_classification_source(self, instance: Dict[str, Any]) -> str:
        """
        Identify which method was used to classify the instance.
        
        Args:
            instance: RDS instance metadata
            
        Returns:
            str: Classification source
        """
        instance_id = instance.get('instance_id', '')
        account_id = instance.get('account_id', '')
        tags = instance.get('tags', {})
        
        if 'Environment' in tags:
            return 'aws_tag'
        elif instance_id in self.instance_mappings:
            return 'manual_mapping'
        elif account_id in self.account_mappings:
            return 'account_mapping'
        elif self._match_naming_pattern(instance_id):
            return 'naming_pattern'
        else:
            return 'default'
```

### Usage in Compliance Checker

Update `lambda/compliance-checker/checks.py`:

```python
from shared.environment_classifier import EnvironmentClassifier

class ComplianceChecker:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.env_classifier = EnvironmentClassifier(config)
    
    def _check_multi_az(self, instance: Dict[str, Any]) -> List[Dict[str, Any]]:
        violations = []
        multi_az = instance.get('multi_az', False)
        
        # Use classifier instead of direct tag reading
        environment = self.env_classifier.get_environment(instance)
        
        # Only enforce for production
        if environment == 'production' and not multi_az:
            violations.append({
                'instance_id': instance['instance_id'],
                'check_type': 'multi_az',
                'severity': 'High',
                'message': f"Multi-AZ is not enabled for production instance (classified via {self.env_classifier.get_classification_source(instance)})"
            })
        
        return violations
```

### Dashboard UI for Manual Classification

Add a UI feature to allow app owners to manually classify instances:

**API Endpoint:** `POST /instances/{instance_id}/environment`

```json
{
  "instance_id": "my-database-01",
  "environment": "production",
  "reason": "Critical customer-facing database",
  "updated_by": "john.doe@company.com"
}
```

This stores the classification in DynamoDB and overrides automatic detection.

### Hybrid Approach (Best Practice)

Combine multiple methods with priority:

```json
{
  "classification_strategy": "hybrid",
  "priority_order": [
    "manual_override",
    "aws_tags",
    "account_mapping",
    "naming_pattern",
    "default"
  ],
  "allow_manual_override": true,
  "require_approval_for_production": true
}
```

### Benefits of Manual Classification

✅ **Flexibility** - Works without AWS tagging  
✅ **Gradual Migration** - Can transition from manual to tags over time  
✅ **Override Capability** - App owners can correct misclassifications  
✅ **Audit Trail** - Track who classified what and why  
✅ **Multiple Methods** - Fallback options if one method fails

---

## Comparison Matrix

| Aspect | AWS Tags | Manual Config | Account-Based | Naming Pattern |
|--------|----------|---------------|---------------|----------------|
| **Setup Effort** | Medium | Low | Low | Low |
| **Maintenance** | Low | High | Low | Medium |
| **Flexibility** | High | High | Low | Medium |
| **Accuracy** | High | High | Medium | Low |
| **Scalability** | High | Low | High | High |
| **Override Capability** | Yes (retag) | Yes (edit config) | No | No |
| **Audit Trail** | AWS CloudTrail | Git history | N/A | N/A |
| **Best For** | Long-term | Quick start | Simple setups | Consistent naming |

## Recommendations

### For New Deployments
1. **Start with account-based** classification (simplest)
2. **Add naming patterns** for within-account differentiation
3. **Migrate to AWS tags** over time (best practice)
4. **Enable manual overrides** for exceptions

### For Existing Environments
1. **Use hybrid approach** with multiple fallback methods
2. **Implement manual override UI** for app owners
3. **Gradually add tags** to resources
4. **Monitor classification accuracy** via compliance reports

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-11-13  
**Maintained By:** DBA Team
