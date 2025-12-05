# Remaining CDK Stack Updates

## Completed So Far
✅ Task 1.1: app.ts
✅ Task 1.2: DataStack
✅ Task 1.3: IAMStack  
✅ Task 1.4: ComputeStack

## Remaining Stacks - Update Pattern

For each remaining stack, apply these changes:

### 1. Remove `environment` from interface
### 2. Remove `environment` from constructor destructuring
### 3. Update all resource names to remove `-${environment}` suffix
### 4. Remove environment from tags
### 5. Update CloudFormation exports to remove `${environment}-` prefix

## Task 1.5: APIStack

**File:** `infrastructure/lib/api-stack.ts`

**Changes needed:**
- Remove `readonly environment: string;` from interface
- Remove `environment` from constructor
- Update API Gateway name
- Update API key name
- Remove environment from tags
- Update exports

## Task 1.6: AuthStack

**File:** `infrastructure/lib/auth-stack.ts`

**Changes needed:**
- Remove `readonly environment: string;` from interface
- Remove `environment` from constructor
- Update Cognito User Pool name
- Update Cognito Client name
- Update Cognito groups
- Remove environment from tags
- Update exports

## Task 1.7: BFFStack

**File:** `infrastructure/lib/bff-stack.ts`

**Changes needed:**
- Remove `readonly environment: string;` from interface
- Remove `environment` from constructor
- Update BFF Lambda function name
- Update Secrets Manager secret names
- Remove environment from tags
- Update exports

## Task 1.8: OrchestrationStack

**File:** `infrastructure/lib/orchestration-stack.ts`

**Changes needed:**
- Remove `readonly environment: string;` from interface
- Remove `environment` from constructor
- Update EventBridge rule names
- Remove environment from tags
- Update exports

## Task 1.9: MonitoringStack

**File:** `infrastructure/lib/monitoring-stack.ts`

**Changes needed:**
- Remove `readonly environment: string;` from interface
- Remove `environment` from constructor
- Update CloudWatch dashboard name
- Update SNS topic name
- Update alarm names
- Remove environment from tags
- Update exports

## Quick Reference Commands

After completing all stack updates, verify with:

```bash
# Check for remaining environment references
cd rds-operations-dashboard/infrastructure
grep -r "environment" lib/ | grep -v "// " | grep -v "environment:"

# Synthesize to check for errors
cdk synth

# List what will be deployed
cdk list
```

Expected stack names (no environment suffixes):
- RDSDashboard-Data
- RDSDashboard-IAM
- RDSDashboard-Compute
- RDSDashboard-API
- RDSDashboard-Auth
- RDSDashboard-BFF
- RDSDashboard-Orchestration
- RDSDashboard-Monitoring

