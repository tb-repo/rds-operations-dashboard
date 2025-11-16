# RDS Operations Service

**Service:** Self-Service Operations for Non-Production RDS Instances  
**Status:** ✅ Implemented  
**Date:** 2025-11-13

## Overview

The Operations Service provides self-service capabilities for DBAs to perform common operations on non-production RDS instances directly from the dashboard, without manual AWS console navigation.

**Key Features:**
- ✅ Snapshot creation with automatic status polling
- ✅ Instance reboot with optional failover
- ✅ Backup window modification
- ✅ Environment-based access control (non-production only)
- ✅ Comprehensive audit logging
- ✅ Operation timeout and error handling

## Supported Operations

### 1. Create Snapshot

Create a manual snapshot of an RDS instance.

**Operation:** `create_snapshot`

**Parameters:**
- `snapshot_id` (required): Unique identifier for the snapshot
- `tags` (optional): Array of tags to apply to the snapshot

**Example Request:**
```json
{
  "operation": "create_snapshot",
  "instance_id": "dev-postgres-01",
  "parameters": {
    "snapshot_id": "dev-postgres-01-manual-2025-11-13",
    "tags": [
      {"Key": "Purpose", "Value": "Pre-upgrade backup"},
      {"Key": "CreatedBy", "Value": "john.doe"}
    ]
  }
}
```

**Response:**
```json
{
  "operation": "create_snapshot",
  "snapshot_id": "dev-postgres-01-manual-2025-11-13",
  "status": "available",
  "snapshot_arn": "arn:aws:rds:ap-southeast-1:123456789012:snapshot:dev-postgres-01-manual-2025-11-13",
  "snapshot_create_time": "2025-11-13T10:30:00Z",
  "duration_seconds": 125.3,
  "success": true
}
```

**Status Values:**
- `creating` - Snapshot is being created
- `available` - Snapshot is ready
- `failed` - Snapshot creation failed
- `timeout` - Operation timed out (5 minutes)

### 2. Reboot Instance

Reboot an RDS instance with optional Multi-AZ failover.

**Operation:** `reboot_instance`

**Parameters:**
- `force_failover` (optional, default: false): Force failover to standby replica (Multi-AZ only)

**Example Request:**
```json
{
  "operation": "reboot_instance",
  "instance_id": "test-mysql-01",
  "parameters": {
    "force_failover": false
  }
}
```

**Response:**
```json
{
  "operation": "reboot_instance",
  "instance_id": "test-mysql-01",
  "status": "available",
  "force_failover": false,
  "duration_seconds": 180.7,
  "success": true
}
```

**Status Values:**
- `rebooting` - Instance is rebooting
- `available` - Instance is ready
- `failed` - Reboot failed
- `timeout` - Operation timed out (5 minutes)

**Use Cases:**
- Apply parameter group changes that require reboot
- Test Multi-AZ failover behavior
- Resolve connection issues or performance problems

### 3. Modify Backup Window

Change the preferred backup window for an RDS instance.

**Operation:** `modify_backup_window`

**Parameters:**
- `backup_window` (required): Backup window in format `HH:MM-HH:MM` (UTC)
- `apply_immediately` (optional, default: true): Apply change immediately or during maintenance window

**Example Request:**
```json
{
  "operation": "modify_backup_window",
  "instance_id": "dev-oracle-01",
  "parameters": {
    "backup_window": "03:00-04:00",
    "apply_immediately": true
  }
}
```

**Response:**
```json
{
  "operation": "modify_backup_window",
  "instance_id": "dev-oracle-01",
  "backup_window": "03:00-04:00",
  "apply_immediately": true,
  "status": "available",
  "pending_backup_window": null,
  "duration_seconds": 2.1,
  "success": true
}
```

**Backup Window Format:**
- Must be in UTC timezone
- Format: `HH:MM-HH:MM` (24-hour format)
- Must be at least 30 minutes
- Examples: `03:00-04:00`, `23:30-00:30`

## Security and Access Control

### Environment-Based Restrictions

**Production Instances:** ❌ Operations NOT allowed
- All operations are blocked on production instances
- Returns HTTP 403 with message: "Operations not allowed on production instances. Please create a CloudOps request."

**Non-Production Instances:** ✅ Operations allowed
- Development, Test, Staging, POC, Sandbox environments
- Operations execute immediately with audit logging

### Environment Classification

The service uses the flexible environment classifier to determine instance environment:

**Classification Methods (Priority Order):**
1. AWS Tags (Environment, Env, ENV, Stage, etc.)
2. Manual instance mapping
3. Account-level mapping
4. Naming pattern matching
5. Default environment

**Example:**
```json
{
  "tags": {
    "Environment": "Development"  // ✅ Allows operations
  }
}
```

```json
{
  "tags": {
    "Environment": "Production"  // ❌ Blocks operations
  }
}
```

### IAM Permissions Required

**Cross-Account Role Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBSnapshot",
        "rds:DescribeDBSnapshots",
        "rds:RebootDBInstance",
        "rds:ModifyDBInstance",
        "rds:DescribeDBInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:ResourceTag/Environment": "Production"
        }
      }
    }
  ]
}
```

## Audit Logging

All operations are logged to the `rds_audit_log` DynamoDB table for compliance and troubleshooting.

### Audit Log Schema

```json
{
  "audit_id": "dev-postgres-01#2025-11-13T10:30:00Z",
  "timestamp": "2025-11-13T10:30:00Z",
  "operation": "create_snapshot",
  "instance_id": "dev-postgres-01",
  "parameters": "{\"snapshot_id\": \"dev-postgres-01-manual-2025-11-13\"}",
  "user_identity": "{\"userId\": \"john.doe\", \"sourceIp\": \"203.0.113.42\"}",
  "result": "{\"success\": true, \"duration_seconds\": 125.3}",
  "success": true,
  "ttl": 1739404800
}
```

### Audit Log Retention

- **Retention Period:** 90 days
- **Automatic Cleanup:** DynamoDB TTL removes expired records
- **Export:** Audit logs can be exported to S3 for long-term archival

### Querying Audit Logs

**By Instance:**
```python
response = dynamodb.query(
    TableName='rds_audit_log',
    KeyConditionExpression='instance_id = :id',
    ExpressionAttributeValues={':id': 'dev-postgres-01'}
)
```

**By User:**
```python
response = dynamodb.scan(
    TableName='rds_audit_log',
    FilterExpression='contains(user_identity, :user)',
    ExpressionAttributeValues={':user': 'john.doe'}
)
```

**Failed Operations:**
```python
response = dynamodb.scan(
    TableName='rds_audit_log',
    FilterExpression='success = :false',
    ExpressionAttributeValues={':false': False}
)
```

## Operation Timeouts and Polling

### Timeout Configuration

- **Default Timeout:** 5 minutes (300 seconds)
- **Poll Interval:** 30 seconds
- **Maximum Polls:** 10 attempts

### Status Polling

The service automatically polls operation status until completion or timeout:

**Snapshot Creation:**
- Polls `describe_db_snapshots` every 30 seconds
- Waits for status: `available`, `failed`, or timeout

**Instance Reboot:**
- Polls `describe_db_instances` every 30 seconds
- Waits for status: `available`, `failed`, or timeout

**Backup Window Modification:**
- No polling required (immediate response)

### Timeout Handling

If an operation times out:
- Status returned as `timeout`
- Operation may still complete in background
- Check AWS console or audit logs for final status

## Error Handling

### Validation Errors (HTTP 400)

**Missing Required Parameters:**
```json
{
  "error": "snapshot_id is required"
}
```

**Invalid Operation:**
```json
{
  "error": "Operation 'delete_instance' not allowed. Allowed: create_snapshot, reboot_instance, modify_backup_window"
}
```

**Invalid Backup Window Format:**
```json
{
  "error": "Invalid backup_window format. Use HH:MM-HH:MM"
}
```

### Authorization Errors (HTTP 403)

**Production Instance:**
```json
{
  "error": "Operations not allowed on production instances. Please create a CloudOps request."
}
```

### Not Found Errors (HTTP 404)

**Instance Not Found:**
```json
{
  "error": "Instance dev-postgres-01 not found"
}
```

### Operation Errors (HTTP 200 with success: false)

**AWS API Error:**
```json
{
  "operation": "create_snapshot",
  "success": false,
  "error": "DBSnapshotAlreadyExists: Snapshot dev-postgres-01-manual-2025-11-13 already exists",
  "duration_seconds": 1.2
}
```

**Timeout:**
```json
{
  "operation": "reboot_instance",
  "status": "timeout",
  "success": false,
  "duration_seconds": 300.0
}
```

## API Integration

### API Gateway Endpoint

**Method:** POST  
**Path:** `/operations`  
**Authentication:** IAM or API Key

### Request Format

```http
POST /operations HTTP/1.1
Host: api.rds-dashboard.example.com
Content-Type: application/json
Authorization: Bearer <token>

{
  "operation": "create_snapshot",
  "instance_id": "dev-postgres-01",
  "parameters": {
    "snapshot_id": "dev-postgres-01-manual-2025-11-13"
  }
}
```

### Response Format

**Success (HTTP 200):**
```json
{
  "operation": "create_snapshot",
  "snapshot_id": "dev-postgres-01-manual-2025-11-13",
  "status": "available",
  "duration_seconds": 125.3,
  "success": true
}
```

**Error (HTTP 4xx/5xx):**
```json
{
  "error": "Error message"
}
```

### CORS Configuration

```json
{
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
}
```

## Testing

### Unit Tests

**File:** `lambda/tests/test_operations.py`

**Test Coverage:**
- ✅ Request validation (operation type, parameters, format)
- ✅ Backup window format validation
- ✅ Instance retrieval from inventory
- ✅ Snapshot creation and status polling
- ✅ Instance reboot with failover options
- ✅ Backup window modification
- ✅ Audit logging
- ✅ Production instance blocking
- ✅ Error handling and responses

**Run Tests:**
```bash
cd lambda/tests
python test_operations.py
```

### Integration Testing

**Test Snapshot Creation:**
```bash
curl -X POST https://api.rds-dashboard.example.com/operations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "operation": "create_snapshot",
    "instance_id": "dev-postgres-01",
    "parameters": {
      "snapshot_id": "test-snapshot-'$(date +%s)'"
    }
  }'
```

**Test Instance Reboot:**
```bash
curl -X POST https://api.rds-dashboard.example.com/operations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "operation": "reboot_instance",
    "instance_id": "test-mysql-01",
    "parameters": {
      "force_failover": false
    }
  }'
```

**Test Backup Window Modification:**
```bash
curl -X POST https://api.rds-dashboard.example.com/operations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "operation": "modify_backup_window",
    "instance_id": "dev-oracle-01",
    "parameters": {
      "backup_window": "03:00-04:00",
      "apply_immediately": true
    }
  }'
```

## Monitoring and Metrics

### CloudWatch Metrics

**Custom Metrics Published:**
- `OperationsExecuted` - Count of operations executed
- `OperationSuccessRate` - Percentage of successful operations
- `OperationDuration` - Duration of operations in seconds
- `OperationErrors` - Count of failed operations

**Dimensions:**
- `Operation` - Operation type (create_snapshot, reboot_instance, etc.)
- `Environment` - Instance environment (development, test, staging)
- `Region` - AWS region

### CloudWatch Logs

**Log Group:** `/aws/lambda/rds-operations-service`

**Log Events:**
- Operation requests and validation
- AWS API calls and responses
- Status polling progress
- Audit log creation
- Errors and exceptions

### Alarms

**Recommended Alarms:**
- High operation failure rate (> 10%)
- Operation timeout rate (> 5%)
- Audit log write failures
- API Gateway 5xx errors

## Best Practices

### Snapshot Naming

Use descriptive snapshot IDs with timestamps:
```
{instance-id}-{purpose}-{date}
dev-postgres-01-pre-upgrade-2025-11-13
test-mysql-01-backup-20251113-1030
```

### Reboot Timing

- Schedule reboots during low-traffic periods
- Test failover in non-production first
- Monitor application connections during reboot

### Backup Window Selection

- Choose off-peak hours (typically 2-5 AM local time)
- Avoid overlapping with maintenance windows
- Consider backup duration for large databases

### Audit Log Review

- Regularly review audit logs for unauthorized operations
- Export logs to S3 for compliance reporting
- Set up alerts for suspicious activity patterns

## Troubleshooting

### Operation Timeout

**Symptom:** Operation returns `timeout` status after 5 minutes

**Causes:**
- Large snapshot creation (> 1TB database)
- Instance in unhealthy state
- AWS API throttling

**Resolution:**
- Check AWS console for operation status
- Review CloudWatch logs for errors
- Increase timeout if needed for large databases

### Permission Denied

**Symptom:** HTTP 403 or AWS access denied error

**Causes:**
- Instance tagged as production
- Insufficient IAM permissions
- Cross-account role not configured

**Resolution:**
- Verify instance environment classification
- Check IAM role permissions
- Ensure cross-account trust relationship

### Snapshot Already Exists

**Symptom:** `DBSnapshotAlreadyExists` error

**Causes:**
- Duplicate snapshot ID
- Previous snapshot not deleted

**Resolution:**
- Use unique snapshot IDs with timestamps
- Delete old snapshots if no longer needed
- Check existing snapshots before creating new ones

## Related Documentation

- [Environment Classification](./environment-classification.md)
- [Flexible Tag Names](./flexible-tag-names.md)
- [Cross-Account Setup](./cross-account-setup.md)
- [Deployment Guide](./deployment.md)

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-11-13  
**Maintained By:** DBA Team
