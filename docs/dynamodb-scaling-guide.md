# DynamoDB Scaling Guide

## Current Configuration: On-Demand Mode

All DynamoDB tables are currently configured with **PAY_PER_REQUEST** (on-demand) billing mode, which provides:

- **Automatic scaling**: No capacity planning required
- **Pay-per-request pricing**: Only pay for what you use
- **Instant scaling**: Handles up to 40,000 read/write requests per second
- **No throttling**: (unless you exceed account limits)
- **Cost-effective for unpredictable workloads**

### When to Use On-Demand Mode

✅ **Use on-demand mode when:**
- Traffic is unpredictable or spiky
- You're starting a new application
- You want to avoid capacity planning
- Cost is less important than simplicity

### When to Switch to Provisioned Mode

Consider switching to **PROVISIONED** mode with auto-scaling when:
- Traffic patterns are predictable
- You want to optimize costs (can be 50-70% cheaper)
- You have steady baseline traffic with occasional spikes
- You need more control over capacity

## Switching to Provisioned Mode with Auto-Scaling

### Step 1: Analyze Current Usage

```bash
# Get table metrics for the last 7 days
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=rds-inventory \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average,Maximum

aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=rds-inventory \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average,Maximum
```

### Step 2: Calculate Baseline Capacity

Based on your analysis:
- **Read Capacity Units (RCU)**: Set to 70% of average usage
- **Write Capacity Units (WCU)**: Set to 70% of average usage
- **Auto-scaling will handle spikes**

Example calculation:
```
Average reads: 100 RCU
Baseline: 100 * 0.7 = 70 RCU

Average writes: 50 WCU
Baseline: 50 * 0.7 = 35 WCU
```

### Step 3: Update CDK Configuration

Edit `infrastructure/lib/data-stack.ts`:

```typescript
// Change from on-demand to provisioned
this.rdsInventoryTable = new dynamodb.Table(this, 'RdsInventoryTable', {
  tableName: 'rds-inventory',
  partitionKey: {
    name: 'instance_id',
    type: dynamodb.AttributeType.STRING,
  },
  billingMode: dynamodb.BillingMode.PROVISIONED, // Changed from PAY_PER_REQUEST
  readCapacity: 70,  // Set based on your analysis
  writeCapacity: 35, // Set based on your analysis
  encryption: dynamodb.TableEncryption.AWS_MANAGED,
  pointInTimeRecovery: true,
  removalPolicy: cdk.RemovalPolicy.RETAIN,
});

// Enable auto-scaling for reads
const readScaling = this.rdsInventoryTable.autoScaleReadCapacity({
  minCapacity: 70,   // Minimum RCU
  maxCapacity: 500,  // Maximum RCU (adjust based on expected peak)
});

readScaling.scaleOnUtilization({
  targetUtilizationPercent: 70, // Scale when utilization exceeds 70%
});

// Enable auto-scaling for writes
const writeScaling = this.rdsInventoryTable.autoScaleWriteCapacity({
  minCapacity: 35,   // Minimum WCU
  maxCapacity: 300,  // Maximum WCU (adjust based on expected peak)
});

writeScaling.scaleOnUtilization({
  targetUtilizationPercent: 70, // Scale when utilization exceeds 70%
});
```

### Step 4: Deploy Changes

```bash
cd infrastructure
npm run build
cdk diff DataStack  # Review changes
cdk deploy DataStack
```

### Step 5: Monitor Auto-Scaling

```bash
# Check auto-scaling activities
aws application-autoscaling describe-scaling-activities \
  --service-namespace dynamodb \
  --resource-id table/rds-inventory

# Monitor consumed vs provisioned capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=rds-inventory \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Auto-Scaling Configuration Reference

### Recommended Settings by Table

| Table | Min Read | Max Read | Min Write | Max Write | Target % |
|-------|----------|----------|-----------|-----------|----------|
| rds-inventory | 50 | 500 | 25 | 300 | 70% |
| health-alerts | 20 | 200 | 10 | 100 | 70% |
| audit-log | 30 | 300 | 50 | 500 | 70% |
| cost-snapshots | 10 | 100 | 5 | 50 | 70% |
| rds-approvals | 20 | 200 | 10 | 100 | 70% |

**Note:** metrics-cache should remain on-demand due to unpredictable access patterns.

### Auto-Scaling Behavior

- **Scale-up**: Happens within 1-2 minutes when utilization exceeds target
- **Scale-down**: Happens gradually over 15 minutes to avoid thrashing
- **Cooldown period**: 5 minutes between scaling activities
- **Minimum scaling increment**: 10% of current capacity

## Cost Comparison

### On-Demand Pricing (Current)
- **Reads**: $0.25 per million read request units
- **Writes**: $1.25 per million write request units
- **No minimum cost**

Example monthly cost (100M reads, 50M writes):
```
Reads:  100M * $0.25 = $25
Writes: 50M * $1.25 = $62.50
Total: $87.50/month
```

### Provisioned with Auto-Scaling
- **Reads**: $0.00013 per RCU-hour
- **Writes**: $0.00065 per WCU-hour
- **Minimum cost based on baseline capacity**

Example monthly cost (70 RCU, 35 WCU baseline):
```
Reads:  70 RCU * 730 hours * $0.00013 = $6.64
Writes: 35 WCU * 730 hours * $0.00065 = $16.61
Total: $23.25/month (baseline)
```

**Savings**: ~73% for predictable workloads

## Monitoring and Alerts

### Key Metrics to Monitor

1. **ConsumedReadCapacityUnits** vs **ProvisionedReadCapacityUnits**
2. **ConsumedWriteCapacityUnits** vs **ProvisionedWriteCapacityUnits**
3. **ReadThrottleEvents** (should be 0)
4. **WriteThrottleEvents** (should be 0)
5. **UserErrors** (throttling errors)

### CloudWatch Alarms

```bash
# Create alarm for read throttling
aws cloudwatch put-metric-alarm \
  --alarm-name rds-inventory-read-throttle \
  --alarm-description "Alert when DynamoDB reads are throttled" \
  --metric-name ReadThrottleEvents \
  --namespace AWS/DynamoDB \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=TableName,Value=rds-inventory

# Create alarm for write throttling
aws cloudwatch put-metric-alarm \
  --alarm-name rds-inventory-write-throttle \
  --alarm-description "Alert when DynamoDB writes are throttled" \
  --metric-name WriteThrottleEvents \
  --namespace AWS/DynamoDB \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=TableName,Value=rds-inventory
```

## Rollback to On-Demand

If auto-scaling isn't working as expected:

```typescript
// Revert to on-demand in data-stack.ts
billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
// Remove readCapacity, writeCapacity, and auto-scaling configuration
```

```bash
cdk deploy DataStack
```

## Best Practices

1. **Start with on-demand** for new applications
2. **Monitor for 2-4 weeks** before switching to provisioned
3. **Set conservative baselines** (70% of average usage)
4. **Set generous maximums** (2-3x peak usage)
5. **Monitor throttling** closely after switching
6. **Review monthly** and adjust capacity as needed
7. **Use on-demand for GSIs** with unpredictable access patterns

## Related Documentation

- [AWS DynamoDB Auto Scaling](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/AutoScaling.html)
- [DynamoDB Pricing](https://aws.amazon.com/dynamodb/pricing/)
- [Disaster Recovery Runbook](./disaster-recovery-runbook.md)

---

**Metadata:**
```json
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-04T11:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-7.4 → DESIGN-AutoScaling → TASK-10.3",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
```
