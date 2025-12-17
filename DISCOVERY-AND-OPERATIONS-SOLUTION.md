# Discovery and Operations Solution

## Issue Summary

You were experiencing two main issues:
1. **"Trigger Discovery" button on dashboard not working** - It was just a placeholder with TODO comment
2. **"Instance not found" error when trying to start/stop RDS instances** - Instances weren't discovered yet

## Root Cause

The RDS instances weren't in the DynamoDB inventory table because:
- Discovery Lambda (`rds-discovery`) exists and works correctly
- The frontend "Trigger Discovery" button wasn't implemented
- Discovery needs to be run manually or wait for the hourly EventBridge schedule

## Solution Implemented

### 1. Fixed Frontend API Client (`frontend/src/lib/api.ts`)

Added the `triggerDiscovery` function:

```typescript
// Discovery
triggerDiscovery: async () => {
  const response = await apiClient.post<{ message: string; execution_id?: string }>(
    '/api/discovery/trigger'
  )
  return response.data
},
```

### 2. Fixed Dashboard Component (`frontend/src/pages/Dashboard.tsx`)

Implemented the `handleTriggerDiscovery` function:

```typescript
const handleTriggerDiscovery = async () => {
  try {
    console.log('Triggering discovery...')
    const result = await api.triggerDiscovery()
    console.log('Discovery triggered successfully:', result)
    alert('Discovery triggered successfully! Instances will be refreshed shortly.')
    // Refresh instances after a short delay to allow discovery to complete
    setTimeout(() => {
      refetchInstances()
    }, 5000)
  } catch (error) {
    console.error('Failed to trigger discovery:', error)
    alert('Failed to trigger discovery. Please check your permissions and try again.')
  }
}
```

### 3. Discovery Lambda Results

Successfully discovered **2 RDS instances**:

1. **tb-pg-db1**
   - Engine: PostgreSQL 18.1
   - Region: ap-southeast-1
   - Status: stopped
   - Instance Class: db.t4g.micro

2. **database-1**
   - Engine: MySQL 8.0.43
   - Region: eu-west-2
   - Status: stopped
   - Instance Class: db.t4g.micro

### 4. DynamoDB Inventory

Both instances are now in the `rds-inventory-prod` table and ready for operations.

## How to Use

### Option 1: Use the Dashboard (Recommended)

1. Log in to the dashboard at your CloudFront URL
2. Click the **"Trigger Discovery"** button in the top-right corner
3. Wait 5-10 seconds for discovery to complete
4. The instances will appear in the dashboard
5. Navigate to an instance and use the Start/Stop buttons

### Option 2: Manual Lambda Invocation

```powershell
# Trigger discovery
aws lambda invoke \
  --function-name rds-discovery \
  --payload '{}' \
  response.json

# Check results
cat response.json
```

### Option 3: Wait for Scheduled Discovery

The EventBridge rule `rds-discovery-schedule` runs hourly and will automatically discover instances.

## Testing RDS Operations

Now that instances are discovered, you can test operations:

### Via Dashboard:
1. Go to Instance List page
2. Click on "tb-pg-db1"
3. Click "Start Instance" button
4. Monitor the status change

### Via BFF API:
```bash
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "instance_id": "tb-pg-db1",
    "operation_type": "start_instance",
    "parameters": {}
  }'
```

## Permissions Verified

Your user (admin@example.com) now has:
- **Admin** group: Full access including `execute_operations`
- **DBA** group: Operations access including `execute_operations`

Both groups have the `execute_operations` permission, so you can start/stop instances.

## Next Steps

1. **Deploy Frontend Changes**: The frontend code changes need to be deployed
   ```powershell
   cd rds-operations-dashboard/frontend
   npm run build
   aws s3 sync dist/ s3://your-frontend-bucket/
   aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
   ```

2. **Test Discovery Button**: After deployment, test the "Trigger Discovery" button

3. **Test Operations**: Try starting the stopped instance through the dashboard

4. **Monitor**: Check CloudWatch logs for any errors

## Architecture Notes

- **Discovery Lambda**: `rds-discovery` - Scans all regions for RDS instances
- **Operations Lambda**: `rds-operations` - Executes start/stop/snapshot operations
- **BFF Endpoint**: `/api/discovery/trigger` - Triggers discovery manually
- **Permission Required**: `trigger_discovery` (granted to DBA and Admin groups)
- **Inventory Table**: `rds-inventory-prod` - Stores discovered instances

## Troubleshooting

### If instances don't appear after discovery:
```powershell
# Check DynamoDB directly
aws dynamodb scan --table-name rds-inventory-prod \
  --query 'Items[].{InstanceId:instance_id.S, Status:status.S, Region:region.S}' \
  --output table
```

### If operations fail:
```powershell
# Check Lambda logs
aws logs tail /aws/lambda/rds-operations --since 10m --follow
```

### If discovery fails:
```powershell
# Check discovery logs
aws logs tail /aws/lambda/rds-discovery --since 10m --follow
```

## Success Criteria

✅ Discovery Lambda finds instances across all regions  
✅ Instances persisted to DynamoDB  
✅ Frontend "Trigger Discovery" button implemented  
✅ User has correct permissions (Admin + DBA groups)  
✅ Operations Lambda can read from DynamoDB  
✅ Ready to test start/stop operations  

## Status: READY FOR TESTING

The discovery system is working correctly. Once you deploy the frontend changes, you'll be able to:
1. Click "Trigger Discovery" button on dashboard
2. See your RDS instances appear
3. Start/stop instances through the UI
4. Monitor operations in real-time
