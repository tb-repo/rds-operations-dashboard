# RDS Dashboard Enhancement Plan

## Overview

Three major enhancements requested for production readiness:

1. **Access Management** - Role-based access control
2. **Extended RDS Operations** - More modification options
3. **Change Request Feature** - CloudOps request generation (restore visibility)

---

## 1. Access Management (RBAC)

### Current State
- No authentication or authorization
- All users have full access
- No audit trail of who performed operations

### Proposed Solution

#### Option A: AWS Cognito + API Gateway Authorizer (Recommended)
**Pros**: Native AWS integration, scalable, secure  
**Cons**: Requires user management setup

**Implementation**:
```
User → Cognito Authentication → JWT Token → API Gateway Authorizer → Lambda
```

**Roles**:
- `viewer` - Read-only access (dashboard, metrics, compliance)
- `operator` - View + Execute operations on non-prod instances
- `admin` - Full access including configuration

#### Option B: Custom Auth with DynamoDB
**Pros**: Simple, no external dependencies  
**Cons**: Manual user management, less secure

**Implementation**:
- Store users/roles in DynamoDB
- API key per user
- Middleware checks permissions

### Recommended Approach: **Option A (Cognito)**

**Steps**:
1. Create Cognito User Pool
2. Define user groups (viewer, operator, admin)
3. Add Cognito Authorizer to API Gateway
4. Update frontend to handle authentication
5. Add permission checks in Lambda functions
6. Update audit logging to capture user identity

**Effort**: 2-3 days

---

## 2. Extended RDS/Aurora Operations

### Current Operations
- ✅ Create Snapshot
- ✅ Reboot Instance
- ✅ Modify Backup Window

### Additional Operations to Add

#### Instance Modifications
- **Modify Instance Class** - Scale compute (e.g., db.t3.medium → db.t3.large)
- **Modify Storage** - Increase allocated storage, change storage type
- **Modify IOPS** - Adjust provisioned IOPS
- **Enable/Disable Multi-AZ** - Toggle high availability
- **Modify Security Groups** - Change network access
- **Modify Parameter Group** - Apply different parameter group
- **Modify Option Group** - Change option group (Oracle/SQL Server)
- **Enable/Disable Deletion Protection** - Toggle deletion protection
- **Modify Maintenance Window** - Change maintenance schedule
- **Enable/Disable Auto Minor Version Upgrade** - Toggle automatic upgrades

#### Lifecycle Operations
- **Start Instance** - Start stopped instance
- **Stop Instance** - Stop running instance (non-prod only)
- **Promote Read Replica** - Promote replica to standalone
- **Create Read Replica** - Create new read replica

#### Aurora-Specific Operations
- **Add/Remove Aurora Replica** - Scale read capacity
- **Modify Aurora Cluster** - Change cluster settings
- **Failover Aurora Cluster** - Manual failover to replica
- **Enable/Disable Backtrack** - Configure backtrack (Aurora MySQL)
- **Clone Aurora Cluster** - Create clone for testing

#### Backup & Recovery
- **Restore from Snapshot** - Create new instance from snapshot
- **Point-in-Time Recovery** - Restore to specific timestamp
- **Copy Snapshot** - Copy snapshot to another region
- **Delete Snapshot** - Remove old snapshots

### Implementation Plan

**Phase 1: Core Modifications** (1-2 days)
- Modify instance class
- Modify storage
- Start/Stop instance
- Modify maintenance window

**Phase 2: Advanced Operations** (2-3 days)
- Multi-AZ toggle
- Parameter/Option group changes
- Read replica operations

**Phase 3: Aurora-Specific** (1-2 days)
- Aurora cluster operations
- Backtrack configuration
- Cluster cloning

**Phase 4: Backup & Recovery** (2-3 days)
- Restore operations
- Snapshot management
- Cross-region copy

### Code Changes Required

1. **Update IAM Permissions** (`infrastructure/lib/iam-stack.ts`):
```typescript
'rds:ModifyDBInstance',
'rds:ModifyDBCluster',
'rds:AddTagsToResource',
'rds:RemoveTagsFromResource',
'rds:CreateDBInstanceReadReplica',
'rds:PromoteReadReplica',
'rds:RestoreDBInstanceFromDBSnapshot',
'rds:RestoreDBInstanceToPointInTime',
'rds:CopyDBSnapshot',
'rds:DeleteDBSnapshot',
// Aurora-specific
'rds:FailoverDBCluster',
'rds:BacktrackDBCluster',
'rds:RestoreDBClusterToPointInTime',
```

2. **Extend Operations Handler** (`lambda/operations/handler.py`):
- Add new operation methods
- Add validation for each operation type
- Add parameter validation

3. **Update Frontend** (`frontend/src/pages/InstanceDetail.tsx`):
- Add operation forms with parameters
- Add validation
- Add confirmation dialogs with impact warnings

4. **Update API** (`infrastructure/lib/api-stack.ts`):
- Existing POST /operations endpoint supports all operations
- No changes needed (already generic)

---

## 3. Change Request Feature (CloudOps)

### Current State
- ✅ CloudOps generator Lambda exists
- ✅ Templates exist in S3
- ❌ **NOT exposed through API**
- ❌ **NOT visible in frontend**

### What Exists

**Backend**:
- `lambda/cloudops-generator/handler.py` - Generates CloudOps requests
- `s3-templates/` - Markdown templates for different request types
- Supports: scaling, parameter_change, maintenance

**Templates**:
- Pre-filled with instance details
- Includes compliance status
- Includes change impact analysis
- Saved to S3 in Markdown and plain text formats

### What's Missing

1. **API Endpoint** - Not exposed in API Gateway
2. **Frontend UI** - No UI to generate requests
3. **Request History** - No way to view past requests
4. **Integration** - Not integrated with instance detail page

### Implementation Plan

#### Step 1: Add API Endpoint (30 minutes)

**File**: `infrastructure/lib/api-stack.ts`

Add to `createOperationsEndpoints()`:
```typescript
// POST /cloudops - Generate CloudOps request
const cloudops = operations.addResource('cloudops');
cloudops.addMethod(
  'POST',
  new apigateway.LambdaIntegration(cloudOpsGeneratorFunction, {
    proxy: true,
  }),
  {
    apiKeyRequired: true,
  }
);

// GET /cloudops/history - Get CloudOps request history
const cloudopsHistory = cloudops.addResource('history');
cloudopsHistory.addMethod(
  'GET',
  new apigateway.LambdaIntegration(queryHandler, {
    proxy: true,
  }),
  {
    apiKeyRequired: true,
  }
);
```

#### Step 2: Update Frontend API Client (15 minutes)

**File**: `frontend/src/lib/api.ts`

```typescript
export interface CloudOpsRequest {
  instance_id: string;
  request_type: 'scaling' | 'parameter_change' | 'maintenance';
  changes: Record<string, any>;
  requested_by?: string;
}

export interface CloudOpsResponse {
  request_id: string;
  markdown_url: string;
  text_url: string;
  created_at: string;
}

generateCloudOpsRequest: async (request: CloudOpsRequest): Promise<CloudOpsResponse> => {
  const response = await fetch(`${API_BASE_URL}/cloudops`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!response.ok) throw new Error('Failed to generate CloudOps request');
  return response.json();
},

getCloudOpsHistory: async (instanceId?: string): Promise<CloudOpsResponse[]> => {
  const url = instanceId 
    ? `${API_BASE_URL}/cloudops/history?instance_id=${instanceId}`
    : `${API_BASE_URL}/cloudops/history`;
  const response = await fetch(url, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!response.ok) throw new Error('Failed to fetch CloudOps history');
  return response.json();
},
```

#### Step 3: Add UI to Instance Detail Page (1-2 hours)

**File**: `frontend/src/pages/InstanceDetail.tsx`

Add new section:
```tsx
{/* CloudOps Request Generation */}
{instance.environment === 'production' && (
  <div className="card">
    <h2 className="text-lg font-semibold text-gray-900 mb-4">
      Generate Change Request
    </h2>
    <p className="text-sm text-gray-600 mb-4">
      For production instances, generate a pre-filled CloudOps request
    </p>
    <div className="space-y-4">
      <select
        value={requestType}
        onChange={(e) => setRequestType(e.target.value)}
        className="w-full px-3 py-2 border rounded-md"
      >
        <option value="">Select request type...</option>
        <option value="scaling">Scaling (Instance Class/Storage)</option>
        <option value="parameter_change">Parameter Group Change</option>
        <option value="maintenance">Maintenance Window Change</option>
      </select>
      
      {requestType && (
        <div className="space-y-3">
          {/* Dynamic form based on request type */}
          <RequestForm type={requestType} onChange={setChanges} />
          
          <button
            onClick={handleGenerateRequest}
            disabled={!requestType || generating}
            className="btn-primary"
          >
            {generating ? 'Generating...' : 'Generate Request'}
          </button>
        </div>
      )}
    </div>
    
    {/* Request History */}
    {cloudOpsHistory.length > 0 && (
      <div className="mt-6">
        <h3 className="text-sm font-medium text-gray-700 mb-2">
          Recent Requests
        </h3>
        <div className="space-y-2">
          {cloudOpsHistory.map((req) => (
            <div key={req.request_id} className="flex justify-between items-center p-2 bg-gray-50 rounded">
              <span className="text-sm">{req.request_type}</span>
              <a href={req.markdown_url} className="text-blue-600 text-sm">
                Download
              </a>
            </div>
          ))}
        </div>
      </div>
    )}
  </div>
)}
```

#### Step 4: Deploy Changes (30 minutes)

```powershell
# Deploy API changes
cd infrastructure
npx aws-cdk deploy RDSDashboard-API-prod --require-approval never

# Deploy frontend
cd ../frontend
npm run build
# Deploy to S3/CloudFront
```

---

## Implementation Priority

### Phase 1: Quick Wins (1 day)
1. ✅ **Restore CloudOps Feature** - Add API endpoint + basic UI
2. ✅ **Add 4-5 Core Operations** - Instance class, storage, start/stop, maintenance window

### Phase 2: Access Management (2-3 days)
1. Setup Cognito User Pool
2. Add API Gateway Authorizer
3. Update frontend authentication
4. Add permission checks

### Phase 3: Extended Operations (3-5 days)
1. Add remaining RDS operations
2. Add Aurora-specific operations
3. Add backup/recovery operations
4. Comprehensive testing

### Phase 4: Polish (1-2 days)
1. Enhanced UI/UX
2. Operation impact warnings
3. Approval workflows
4. Documentation

---

## Estimated Total Effort

- **CloudOps Feature**: 0.5 days
- **Core Operations**: 0.5 days
- **Access Management**: 2-3 days
- **Extended Operations**: 3-5 days
- **Polish & Testing**: 1-2 days

**Total**: 7-11 days

---

## Next Steps

**Immediate Actions**:
1. Confirm priority and scope
2. Start with CloudOps feature restoration (quickest win)
3. Add 4-5 most-needed operations
4. Plan access management implementation

**Questions to Answer**:
1. Which operations are highest priority?
2. Do you have existing Cognito setup or prefer custom auth?
3. What's the timeline/urgency?
4. Any specific compliance requirements for access control?

Would you like me to start implementing any of these features?
