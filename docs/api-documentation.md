# RDS Operations Dashboard - API Documentation

**Version:** 1.0.0  
**Base URL:** `https://api.rds-dashboard.example.com/prod`  
**Authentication:** API Key (X-Api-Key header)  
**Date:** 2025-11-13

## Overview

The RDS Operations Dashboard API provides RESTful endpoints for managing and monitoring RDS instances across multiple AWS accounts and regions.

### Authentication

All API requests require an API key in the `X-Api-Key` header:

```bash
curl -H "X-Api-Key: your-api-key-here" \
  https://api.rds-dashboard.example.com/prod/instances
```

### Rate Limiting

- **Rate Limit:** 100 requests per minute
- **Burst Limit:** 200 requests
- **Daily Quota:** 10,000 requests

### Response Format

All responses are JSON with the following structure:

**Success Response:**
```json
{
  "data": { ... },
  "total": 52,
  "limit": 100,
  "offset": 0
}
```

**Error Response:**
```json
{
  "error": "Error message description"
}
```

---

## Endpoints

### Instances

#### List All Instances

```
GET /instances
```

List all RDS instances with optional filtering.

**Query Parameters:**
- `account` (string, optional) - Filter by account ID
- `region` (string, optional) - Filter by region
- `engine` (string, optional) - Filter by engine type (postgres, mysql, oracle)
- `status` (string, optional) - Filter by status (available, backing-up, etc.)
- `environment` (string, optional) - Filter by environment (production, development, etc.)
- `limit` (integer, optional, default: 100) - Max results per page
- `offset` (integer, optional, default: 0) - Pagination offset

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/instances?region=ap-southeast-1&limit=10"
```

**Example Response:**
```json
{
  "instances": [
    {
      "instance_id": "prod-postgres-01",
      "account_id": "123456789012",
      "account_name": "Production",
      "region": "ap-southeast-1",
      "engine": "postgres",
      "engine_version": "15.4",
      "instance_class": "db.r6g.xlarge",
      "storage_type": "gp3",
      "allocated_storage": 500,
      "multi_az": true,
      "environment": "production",
      "instance_status": "available",
      "tags": {
        "Environment": "Production",
        "Team": "DataPlatform"
      }
    }
  ],
  "total": 52,
  "limit": 10,
  "offset": 0,
  "has_more": true
}
```

#### Get Instance Details

```
GET /instances/{instanceId}
```

Get detailed information for a specific RDS instance.

**Path Parameters:**
- `instanceId` (string, required) - RDS instance identifier

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  https://api.rds-dashboard.example.com/prod/instances/prod-postgres-01
```

**Example Response:**
```json
{
  "instance": {
    "instance_id": "prod-postgres-01",
    "account_id": "123456789012",
    "region": "ap-southeast-1",
    "engine": "postgres",
    "engine_version": "15.4",
    "instance_class": "db.r6g.xlarge",
    "vcpus": 4,
    "memory_gb": 32,
    "storage_type": "gp3",
    "allocated_storage": 500,
    "iops": 12000,
    "multi_az": true,
    "encryption_enabled": true,
    "deletion_protection": true,
    "backup_retention_days": 7,
    "preferred_backup_window": "02:00-03:00",
    "preferred_maintenance_window": "sun:03:00-sun:04:00",
    "environment": "production",
    "instance_status": "available",
    "endpoint": "prod-postgres-01.abc123.ap-southeast-1.rds.amazonaws.com",
    "port": 5432,
    "vpc_id": "vpc-abc123",
    "subnet_group": "db-subnet-private",
    "security_groups": ["sg-db-prod"],
    "parameter_group": "custom-postgres15",
    "tags": {
      "Environment": "Production",
      "Team": "DataPlatform",
      "CostCenter": "CC-1234"
    },
    "created_at": "2024-01-15T10:30:00Z",
    "last_updated": "2025-11-13T08:45:00Z"
  }
}
```

#### Get Instance Metrics

```
GET /instances/{instanceId}/metrics
```

Get CloudWatch metrics for a specific instance.

**Path Parameters:**
- `instanceId` (string, required) - RDS instance identifier

**Query Parameters:**
- `period` (string, optional, default: "1h") - Time period (1h, 6h, 24h, 7d)
- `start` (string, optional) - Start time (ISO 8601)
- `end` (string, optional) - End time (ISO 8601)

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/instances/prod-postgres-01/metrics?period=6h"
```

**Example Response:**
```json
{
  "instance_id": "prod-postgres-01",
  "period": "6h",
  "metrics": [
    {
      "timestamp": "2025-11-13T10:00:00Z",
      "cpu_utilization": 45.2,
      "database_connections": 120,
      "free_storage_space": 220000000000,
      "read_iops": 1500,
      "write_iops": 800,
      "read_latency": 0.002,
      "write_latency": 0.003
    }
  ]
}
```

---

### Health

#### Get Health Status

```
GET /health
```

Get health status and active alerts for all instances.

**Query Parameters:**
- `severity` (string, optional) - Filter by severity (critical, warning)
- `limit` (integer, optional, default: 100) - Max results

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/health?severity=critical"
```

**Example Response:**
```json
{
  "alerts": [
    {
      "alert_id": "alert-001",
      "instance_id": "prod-postgres-01",
      "severity": "critical",
      "alert_type": "high_cpu",
      "message": "CPU utilization above 90%",
      "current_value": 92.5,
      "threshold": 90,
      "alert_status": "active",
      "created_at": "2025-11-13T10:30:00Z",
      "consecutive_breaches": 3
    }
  ],
  "total": 5
}
```

#### Get Active Alerts

```
GET /health/alerts
```

Get list of active alerts.

**Query Parameters:**
- `severity` (string, optional) - Filter by severity
- `status` (string, optional) - Filter by status (active, acknowledged, resolved)
- `limit` (integer, optional, default: 100) - Max results

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  https://api.rds-dashboard.example.com/prod/health/alerts
```

---

### Costs

#### Get Cost Analysis

```
GET /costs
```

Get cost analysis and breakdown.

**Query Parameters:**
- `groupBy` (string, optional, default: "account") - Group by (account, region, engine)
- `period` (string, optional, default: "month") - Time period

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/costs?groupBy=region"
```

**Example Response:**
```json
{
  "total_cost": 2847.32,
  "group_by": "region",
  "costs": {
    "ap-southeast-1": 2145.50,
    "eu-west-2": 512.30,
    "ap-south-1": 124.52,
    "us-east-1": 65.00
  }
}
```

#### Get Cost Trends

```
GET /costs/trends
```

Get cost trends over time.

**Query Parameters:**
- `days` (integer, optional, default: 30) - Number of days

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/costs/trends?days=30"
```

**Example Response:**
```json
{
  "days": 30,
  "trends": [
    {
      "date": "2025-11-13",
      "total_cost": 2847.32
    },
    {
      "date": "2025-11-12",
      "total_cost": 2823.15
    }
  ]
}
```

#### Get Optimization Recommendations

```
GET /costs/recommendations
```

Get cost optimization recommendations.

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  https://api.rds-dashboard.example.com/prod/costs/recommendations
```

**Example Response:**
```json
{
  "recommendations": [
    {
      "instance_id": "dev-postgres-01",
      "recommendation_type": "right_size",
      "current_class": "db.r6g.xlarge",
      "recommended_class": "db.r6g.large",
      "potential_savings": 156.00,
      "reason": "Average CPU utilization < 20% for 7 days"
    }
  ],
  "total": 5
}
```

---

### Compliance

#### Get Compliance Status

```
GET /compliance
```

Get compliance status for all instances.

**Query Parameters:**
- `severity` (string, optional) - Filter by violation severity

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  https://api.rds-dashboard.example.com/prod/compliance
```

**Example Response:**
```json
{
  "total_instances": 52,
  "compliant_instances": 44,
  "compliance_score": 84.6,
  "instances": [
    {
      "instance_id": "prod-postgres-01",
      "compliant": false,
      "violations": [
        {
          "check": "multi_az_enabled",
          "severity": "critical",
          "message": "Multi-AZ not enabled for production instance"
        }
      ]
    }
  ]
}
```

#### Get Compliance Violations

```
GET /compliance/violations
```

Get list of compliance violations.

**Query Parameters:**
- `severity` (string, optional) - Filter by severity (critical, high, medium, low)
- `limit` (integer, optional, default: 100) - Max results

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/compliance/violations?severity=critical"
```

---

### Operations

#### Execute Operation

```
POST /operations
```

Execute a self-service operation on a non-production RDS instance.

**Request Body:**
```json
{
  "operation": "create_snapshot|reboot_instance|modify_backup_window",
  "instance_id": "string",
  "parameters": {
    // Operation-specific parameters
  }
}
```

**Create Snapshot Example:**
```bash
curl -X POST \
  -H "X-Api-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "create_snapshot",
    "instance_id": "dev-postgres-01",
    "parameters": {
      "snapshot_id": "dev-postgres-01-manual-2025-11-13",
      "tags": [
        {"Key": "Purpose", "Value": "Pre-upgrade backup"}
      ]
    }
  }' \
  https://api.rds-dashboard.example.com/prod/operations
```

**Response:**
```json
{
  "operation": "create_snapshot",
  "snapshot_id": "dev-postgres-01-manual-2025-11-13",
  "status": "available",
  "duration_seconds": 125.3,
  "success": true
}
```

**Reboot Instance Example:**
```bash
curl -X POST \
  -H "X-Api-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "reboot_instance",
    "instance_id": "test-mysql-01",
    "parameters": {
      "force_failover": false
    }
  }' \
  https://api.rds-dashboard.example.com/prod/operations
```

**Modify Backup Window Example:**
```bash
curl -X POST \
  -H "X-Api-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "modify_backup_window",
    "instance_id": "dev-oracle-01",
    "parameters": {
      "backup_window": "03:00-04:00",
      "apply_immediately": true
    }
  }' \
  https://api.rds-dashboard.example.com/prod/operations
```

#### Get Operations History

```
GET /operations/history
```

Get history of executed operations.

**Query Parameters:**
- `instance_id` (string, optional) - Filter by instance
- `operation` (string, optional) - Filter by operation type
- `limit` (integer, optional, default: 50) - Max results

**Example Request:**
```bash
curl -H "X-Api-Key: your-key" \
  "https://api.rds-dashboard.example.com/prod/operations/history?instance_id=dev-postgres-01"
```

**Example Response:**
```json
{
  "operations": [
    {
      "audit_id": "dev-postgres-01#2025-11-13T10:30:00Z",
      "timestamp": "2025-11-13T10:30:00Z",
      "operation": "create_snapshot",
      "instance_id": "dev-postgres-01",
      "user_identity": {
        "userId": "john.doe",
        "sourceIp": "203.0.113.42"
      },
      "success": true,
      "duration_seconds": 125.3
    }
  ],
  "total": 15
}
```

---

## Error Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid or missing API key |
| 403 | Forbidden - Operation not allowed (e.g., production instance) |
| 404 | Not Found - Resource not found |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |

---

## Code Examples

### Python

```python
import requests

API_KEY = 'your-api-key-here'
BASE_URL = 'https://api.rds-dashboard.example.com/prod'

headers = {
    'X-Api-Key': API_KEY,
    'Content-Type': 'application/json'
}

# List instances
response = requests.get(f'{BASE_URL}/instances', headers=headers)
instances = response.json()

# Get instance details
response = requests.get(f'{BASE_URL}/instances/prod-postgres-01', headers=headers)
instance = response.json()

# Execute operation
payload = {
    'operation': 'create_snapshot',
    'instance_id': 'dev-postgres-01',
    'parameters': {
        'snapshot_id': 'dev-postgres-01-backup'
    }
}
response = requests.post(f'{BASE_URL}/operations', headers=headers, json=payload)
result = response.json()
```

### JavaScript/Node.js

```javascript
const axios = require('axios');

const API_KEY = 'your-api-key-here';
const BASE_URL = 'https://api.rds-dashboard.example.com/prod';

const headers = {
  'X-Api-Key': API_KEY,
  'Content-Type': 'application/json'
};

// List instances
const instances = await axios.get(`${BASE_URL}/instances`, { headers });
console.log(instances.data);

// Get instance details
const instance = await axios.get(`${BASE_URL}/instances/prod-postgres-01`, { headers });
console.log(instance.data);

// Execute operation
const payload = {
  operation: 'create_snapshot',
  instance_id: 'dev-postgres-01',
  parameters: {
    snapshot_id: 'dev-postgres-01-backup'
  }
};
const result = await axios.post(`${BASE_URL}/operations`, payload, { headers });
console.log(result.data);
```

### cURL

```bash
# Set API key
API_KEY="your-api-key-here"
BASE_URL="https://api.rds-dashboard.example.com/prod"

# List instances
curl -H "X-Api-Key: $API_KEY" \
  "$BASE_URL/instances"

# Get instance details
curl -H "X-Api-Key: $API_KEY" \
  "$BASE_URL/instances/prod-postgres-01"

# Execute operation
curl -X POST \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "create_snapshot",
    "instance_id": "dev-postgres-01",
    "parameters": {
      "snapshot_id": "dev-postgres-01-backup"
    }
  }' \
  "$BASE_URL/operations"
```

---

## Changelog

### Version 1.0.0 (2025-11-13)
- Initial API release
- Instances endpoints
- Health and alerts endpoints
- Costs and recommendations endpoints
- Compliance endpoints
- Operations endpoints

---

**Support:** dba-team@company.com  
**Documentation:** https://docs.rds-dashboard.example.com  
**Status Page:** https://status.rds-dashboard.example.com
