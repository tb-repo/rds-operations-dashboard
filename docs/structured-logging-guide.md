# Structured Logging Guide

**Feature:** Structured JSON Logging with Correlation IDs  
**Status:** ✅ Implemented  
**Date:** 2025-11-13  
**Task:** 11.1

## Overview

The RDS Operations Dashboard uses structured JSON logging across all Lambda functions for enhanced observability, debugging, and monitoring. All logs are automatically formatted as JSON and include correlation IDs for request tracing.

## Key Features

✅ **JSON Format** - All logs are structured JSON for programmatic parsing  
✅ **Correlation IDs** - Automatic request tracing across services  
✅ **Lambda Context** - Auto-extraction of request ID, function name, version  
✅ **Log Levels** - Configurable via environment variables (DEBUG, INFO, WARN, ERROR)  
✅ **Sensitive Data Protection** - Automatic redaction of passwords, tokens, keys  
✅ **Performance Metrics** - Built-in execution timing decorator  
✅ **CloudWatch Integration** - Optimized for CloudWatch Logs Insights

## Usage

### Basic Usage

```python
from shared.logger import get_logger

# In Lambda handler
def lambda_handler(event, context):
    # Create logger with Lambda context (auto-extracts correlation ID)
    logger = get_logger('my-service', lambda_context=context)
    
    # Log messages with additional fields
    logger.info('Processing started', account_id='123456789012', region='ap-southeast-1')
    logger.warn('High CPU detected', instance_id='prod-db-01', cpu_percent=92.5)
    logger.error('Operation failed', error='Connection timeout', retry_count=3)
    
    return {'statusCode': 200}
```

### With Manual Correlation ID

```python
from shared.logger import get_logger

# Create logger with custom correlation ID
logger = get_logger('my-service', correlation_id='custom-trace-123')

logger.info('Custom trace', operation='snapshot', instance_id='dev-db-01')
```

### Function Execution Logging

```python
from shared.logger import get_logger, log_execution

logger = get_logger('my-service')

@log_execution(logger)
def process_instances(instances):
    """
    Automatically logs:
    - Function start with parameter counts
    - Function completion with duration
    - Function errors with exception details
    """
    for instance in instances:
        # process instance
        pass
    return len(instances)

# Logs:
# {"timestamp": "2025-11-13T10:30:00Z", "level": "INFO", "message": "Function started: process_instances", ...}
# {"timestamp": "2025-11-13T10:30:05Z", "level": "INFO", "message": "Function completed: process_instances", "duration_ms": 5234, ...}
```

### Sensitive Data Protection

```python
from shared.logger import get_logger, sanitize_log_data

logger = get_logger('my-service')

# Sensitive data is automatically redacted
user_data = {
    'username': 'john.doe',
    'password': 'secret123',  # Will be redacted
    'api_key': 'abc123',      # Will be redacted
    'instance_id': 'i-123'    # Will be logged
}

logger.info('User login', **user_data)
# Output: {"username": "john.doe", "password": "[REDACTED]", "api_key": "[REDACTED]", "instance_id": "i-123"}
```

## Log Format

### Standard Log Entry

```json
{
  "timestamp": "2025-11-13T10:30:00.123Z",
  "level": "INFO",
  "service": "discovery-service",
  "message": "Discovery completed",
  "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "function_name": "rds-discovery-lambda",
  "function_version": "$LATEST",
  "account_id": "123456789012",
  "region": "ap-southeast-1",
  "instances_found": 52,
  "duration_ms": 3456
}
```

### Error Log Entry

```json
{
  "timestamp": "2025-11-13T10:30:00.123Z",
  "level": "ERROR",
  "service": "health-monitor",
  "message": "Health check failed",
  "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "function_name": "rds-health-monitor-lambda",
  "instance_id": "prod-postgres-01",
  "error_type": "ConnectionTimeout",
  "error_message": "Connection to CloudWatch timed out after 30s",
  "retry_count": 3
}
```

## Log Levels

### Configuration

Set log level via environment variable:

```bash
# In Lambda configuration
LOG_LEVEL=INFO  # Default
LOG_LEVEL=DEBUG # Verbose logging
LOG_LEVEL=WARN  # Warnings and errors only
LOG_LEVEL=ERROR # Errors only
```

### Level Usage

```python
logger = get_logger('my-service')

# DEBUG - Detailed diagnostic information
logger.debug('Cache lookup', key='instance:prod-db-01', cache_hit=True)

# INFO - General informational messages
logger.info('Discovery started', account_count=5, region_count=4)

# WARN - Warning messages for potential issues
logger.warn('High memory usage', instance_id='dev-db-01', memory_percent=85)

# ERROR - Error messages for failures
logger.error('API call failed', api='CloudWatch', error='RateLimitExceeded')
```

## Correlation ID Tracing

### Automatic Extraction from Lambda Context

```python
def lambda_handler(event, context):
    # Correlation ID automatically extracted from context.aws_request_id
    logger = get_logger('my-service', lambda_context=context)
    
    logger.info('Request received')
    # Output includes: "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

### Cross-Service Tracing

```python
# Service A: Discovery
def lambda_handler(event, context):
    logger = get_logger('discovery', lambda_context=context)
    correlation_id = context.aws_request_id
    
    logger.info('Invoking health check', correlation_id=correlation_id)
    
    # Pass correlation ID to Service B
    invoke_health_check(correlation_id=correlation_id)

# Service B: Health Monitor
def health_check_handler(event, context):
    # Extract correlation ID from event
    correlation_id = event.get('correlation_id', context.aws_request_id)
    logger = get_logger('health-monitor', correlation_id=correlation_id)
    
    logger.info('Health check started')
    # Both services now share the same correlation_id for tracing
```

## CloudWatch Logs Insights Queries

### Find All Logs for a Correlation ID

```
fields @timestamp, level, service, message
| filter correlation_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
| sort @timestamp asc
```

### Find All Errors in Last Hour

```
fields @timestamp, service, message, error_type, error_message
| filter level = "ERROR"
| filter @timestamp > ago(1h)
| sort @timestamp desc
```

### Find Slow Operations (> 5 seconds)

```
fields @timestamp, service, function, duration_ms
| filter duration_ms > 5000
| sort duration_ms desc
| limit 20
```

### Count Errors by Service

```
fields service
| filter level = "ERROR"
| stats count() by service
| sort count() desc
```

### Track Request Flow Across Services

```
fields @timestamp, service, message, correlation_id
| filter correlation_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
| sort @timestamp asc
| display @timestamp, service, message
```

### Find Cache Performance

```
fields @timestamp, cache_hit, cache_miss
| filter service = "health-monitor"
| stats sum(cache_hit) as hits, sum(cache_miss) as misses
| fields hits, misses, (hits / (hits + misses) * 100) as hit_rate
```

## Sensitive Data Protection

### Automatically Redacted Fields

The following field names are automatically redacted:
- `password`
- `secret`
- `token`
- `api_key`
- `access_key`
- `secret_key`
- `credential`
- `authorization`
- `session_token`

### Manual Sanitization

```python
from shared.logger import sanitize_log_data

sensitive_data = {
    'username': 'john.doe',
    'password': 'secret123',
    'instance_id': 'i-123'
}

# Manually sanitize before logging
sanitized = sanitize_log_data(sensitive_data)
logger.info('User data', **sanitized)
```

## Best Practices

### DO ✅

```python
# Include relevant context
logger.info('Instance discovered', 
    instance_id='prod-db-01',
    account_id='123456789012',
    region='ap-southeast-1',
    engine='postgres'
)

# Log at appropriate levels
logger.debug('Cache lookup', key='metric:cpu')  # Diagnostic
logger.info('Discovery completed', count=52)     # Informational
logger.warn('High CPU', instance_id='db-01')     # Warning
logger.error('API failed', error='Timeout')      # Error

# Use structured fields instead of string formatting
logger.info('Found instances', count=52, region='ap-southeast-1')
# NOT: logger.info(f'Found {count} instances in {region}')

# Include metrics in logs
logger.info('Operation completed', 
    duration_ms=1234,
    items_processed=100,
    success_rate=98.5
)
```

### DON'T ❌

```python
# Don't log sensitive data
logger.info('User login', password='secret123')  # BAD!

# Don't use string formatting (breaks structured logging)
logger.info(f'Found {count} instances')  # BAD!

# Don't log at wrong levels
logger.error('Discovery started')  # Should be INFO
logger.info('Database connection failed')  # Should be ERROR

# Don't log excessive data
logger.debug('Full response', response=huge_json_object)  # BAD!
```

## Integration with Services

### Discovery Service

```python
from shared.logger import get_logger, log_execution

def lambda_handler(event, context):
    logger = get_logger('discovery-service', lambda_context=context)
    
    logger.info('Discovery started', 
        account_count=len(accounts),
        region_count=len(regions)
    )
    
    # ... discovery logic ...
    
    logger.info('Discovery completed',
        total_instances=52,
        new_instances=3,
        updated_instances=5,
        duration_ms=3456
    )
```

### Health Monitor

```python
from shared.logger import get_logger

def lambda_handler(event, context):
    logger = get_logger('health-monitor', lambda_context=context)
    
    logger.info('Health check started', instances_to_check=50)
    
    for instance in instances:
        logger.debug('Checking instance', instance_id=instance['id'])
        
        if cpu > 90:
            logger.warn('High CPU detected',
                instance_id=instance['id'],
                cpu_percent=cpu,
                threshold=90
            )
```

### Operations Service

```python
from shared.logger import get_logger

def lambda_handler(event, context):
    logger = get_logger('operations-service', lambda_context=context)
    
    operation = event['operation']
    instance_id = event['instance_id']
    
    logger.info('Operation requested',
        operation=operation,
        instance_id=instance_id,
        user=event['user']
    )
    
    try:
        result = execute_operation(operation, instance_id)
        logger.info('Operation succeeded',
            operation=operation,
            instance_id=instance_id,
            duration_ms=result['duration']
        )
    except Exception as e:
        logger.error('Operation failed',
            operation=operation,
            instance_id=instance_id,
            error_type=type(e).__name__,
            error_message=str(e)
        )
        raise
```

## Troubleshooting

### Issue: Logs Not Appearing in CloudWatch

**Check:**
1. Lambda execution role has `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` permissions
2. Log level is not set too high (e.g., ERROR when logging INFO messages)
3. Lambda function is actually being invoked

### Issue: Correlation ID Not Showing

**Check:**
1. Logger is created with `lambda_context=context` parameter
2. Lambda context is being passed correctly to handler

**Fix:**
```python
# Correct
logger = get_logger('my-service', lambda_context=context)

# Incorrect
logger = get_logger('my-service')  # Missing context
```

### Issue: Sensitive Data in Logs

**Check:**
1. Field names match redaction patterns
2. Manual sanitization is applied if needed

**Fix:**
```python
# Automatic redaction
logger.info('User data', password='secret')  # Automatically redacted

# Manual sanitization
data = sanitize_log_data(user_data)
logger.info('User data', **data)
```

## Performance Considerations

### Log Volume

- **DEBUG**: High volume, use only for development
- **INFO**: Moderate volume, suitable for production
- **WARN/ERROR**: Low volume, always enabled

### Buffering

Logs are written to stdout/stderr and buffered by Lambda. They appear in CloudWatch Logs after:
- Lambda function completes
- Buffer fills (typically 4KB)
- Periodic flush (every few seconds)

### Cost Impact

- CloudWatch Logs: $0.50 per GB ingested
- Typical log volume: 1-5 MB per 1000 invocations
- Estimated cost: $0.50-$2.50 per million invocations

## Related Documentation

- [Monitoring Stack](./monitoring-stack.md)
- [CloudWatch Dashboard](./cloudwatch-dashboard.md)
- [Deployment Guide](./deployment.md)

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-11-13  
**Maintained By:** DBA Team
