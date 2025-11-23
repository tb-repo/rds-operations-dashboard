# CloudOps Feature Implementation Status

## ✅ Completed

### 1. API Endpoints Added
- ✅ POST `/cloudops` - Generate CloudOps request
- ✅ GET `/cloudops/history` - Get request history
- ✅ API Gateway integration with CloudOps generator Lambda
- ✅ Request validation model
- ✅ Deployed to production

### 2. Frontend API Client Updated
- ✅ Added `CloudOpsRequest` interface
- ✅ Added `CloudOpsResponse` interface
- ✅ Added `generateCloudOpsRequest()` method
- ✅ Added `getCloudOpsHistory()` method

### 3. Infrastructure
- ✅ CloudOps generator Lambda already exists
- ✅ S3 templates already exist
- ✅ Connected to API Gateway

## 🔧 Remaining Work

### 1. Fix CloudOps Lambda Handler
The Lambda is returning 500 errors. Needs investigation:
- Check imports and dependencies
- Verify DynamoDB table access
- Verify S3 bucket access
- Test template loading

### 2. Add Frontend UI
Need to add UI components to `InstanceDetail.tsx`:

```tsx
// Add to InstanceDetail page for production instances
{instance.environment === 'production' && (
  <div className="card">
    <h2>Generate Change Request</h2>
    <select value={requestType} onChange={...}>
      <option value="scaling">Scaling Request</option>
      <option value="parameter_change">Parameter Change</option>
      <option value="maintenance">Maintenance Window</option>
    </select>
    
    {/* Dynamic form based on request type */}
    <RequestForm type={requestType} />
    
    <button onClick={handleGenerateRequest}>
      Generate Request
    </button>
    
    {/* Show generated request with download link */}
    {generatedRequest && (
      <div>
        <a href={generatedRequest.markdown_url}>Download Markdown</a>
        <a href={generatedRequest.text_url}>Download Text</a>
      </div>
    )}
  </div>
)}
```

### 3. Add Query Handler Support
The query handler needs to support `get_cloudops_history` action to retrieve past requests from S3 or DynamoDB.

## Quick Fix Steps

### Step 1: Fix CloudOps Lambda (30 min)
```bash
# Check CloudOps Lambda logs
aws logs tail /aws/lambda/rds-cloudops-generator-prod --since 5m

# Common issues to fix:
# - Import paths for shared modules
# - Environment variables (INVENTORY_TABLE, DATA_BUCKET)
# - S3 template paths
```

### Step 2: Add UI Component (1 hour)
Create `frontend/src/components/CloudOpsRequestForm.tsx`:
- Form for each request type
- Validation
- Submit handler
- Display generated request

### Step 3: Test End-to-End (15 min)
1. Generate request for production instance
2. Verify Markdown file created in S3
3. Download and review request
4. Verify audit logging

## Testing Commands

```powershell
# Test CloudOps generation
curl https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/cloudops `
  -Method POST `
  -Body '{"instance_id":"tb-pg-db1","request_type":"scaling","changes":{"from":"db.t3.medium","to":"db.t3.large"},"requested_by":"user@example.com"}' `
  -Headers @{"Content-Type"="application/json"}

# Test history retrieval
curl https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/cloudops/history?instance_id=tb-pg-db1 `
  -Method GET `
  -Headers @{"Content-Type"="application/json"}
```

## What CloudOps Feature Does

### Purpose
For **production instances**, generate pre-filled change request documents that can be submitted to your change management system (ServiceNow, Jira, etc.).

### Request Types

1. **Scaling Request**
   - Instance class changes
   - Storage increases
   - IOPS modifications

2. **Parameter Change Request**
   - Parameter group changes
   - Configuration modifications

3. **Maintenance Request**
   - Maintenance window changes
   - Backup window modifications

### Generated Output

Each request generates:
- **Markdown file** - Formatted for documentation
- **Plain text file** - For copy/paste into ticketing systems

Both files include:
- Instance details
- Current configuration
- Proposed changes
- Impact analysis
- Compliance status
- Rollback plan

### Files Saved To
- S3 bucket: `rds-dashboard-data-{account}-prod`
- Path: `cloudops-requests/{instance_id}/{request_id}.md`
- Path: `cloudops-requests/{instance_id}/{request_id}.txt`

## Architecture

```
User (Production Instance) 
    ↓
Frontend: "Generate Change Request"
    ↓
BFF API
    ↓
Internal API: POST /cloudops
    ↓
CloudOps Generator Lambda
    ├─→ Get instance details from DynamoDB
    ├─→ Get compliance status
    ├─→ Load template from S3
    ├─→ Fill template with data
    └─→ Save to S3 (Markdown + Text)
    ↓
Return S3 URLs to frontend
    ↓
User downloads and submits to change management
```

## Next Steps

1. **Debug CloudOps Lambda** - Check logs and fix errors
2. **Add UI** - Create form component in InstanceDetail page
3. **Test** - Generate sample requests
4. **Document** - Add user guide for change request process

## Estimated Time to Complete

- Fix Lambda: 30 minutes
- Add UI: 1 hour
- Testing: 15 minutes
- **Total**: ~2 hours

The infrastructure is in place, just needs debugging and UI work!
