# Discovery Lambda Resilience Flow

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EventBridge Trigger                             │
│                    (Scheduled: Every 15 minutes)                        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Lambda Handler                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ TRY:                                                              │  │
│  │   1. Load Config (with fallback)                                 │  │
│  │   2. Discover All Instances ──────────────────────┐              │  │
│  │   3. Persist to DynamoDB (best effort)            │              │  │
│  │   4. Publish Metrics (best effort)                │              │  │
│  │   5. Send Notifications (best effort)             │              │  │
│  │                                                    │              │  │
│  │ CATCH:                                             │              │  │
│  │   - Log error                                      │              │  │
│  │   - Return partial results if available           │              │  │
│  │   - Return 200 (unless catastrophic)              │              │  │
│  │                                                    │              │  │
│  │ ALWAYS:                                            │              │  │
│  │   - Returns HTTP 200                              │              │  │
│  │   - Includes success rate                         │              │  │
│  │   - Includes all errors with remediation          │              │  │
│  └────────────────────────────────────────────────────┼──────────────┘  │
└─────────────────────────────────────────────────────────┼────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Discover All Instances                             │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ TRY:                                                              │  │
│  │   1. Get current account (with error handling)                   │  │
│  │   2. Load cross-account config (with fallback)                   │  │
│  │   3. Detect enabled regions (with fallback)                      │  │
│  │                                                                   │  │
│  │   FOR EACH ACCOUNT:                                              │  │
│  │     TRY:                                                          │  │
│  │       - Validate access (skip if fails)                          │  │
│  │       - Discover account instances ────────────┐                 │  │
│  │       - Collect results                        │                 │  │
│  │     CATCH:                                      │                 │  │
│  │       - Analyze error                           │                 │  │
│  │       - Add to error list                       │                 │  │
│  │       - CONTINUE to next account ◄──────────────┘                 │  │
│  │                                                                   │  │
│  │ CATCH:                                                            │  │
│  │   - Log catastrophic error                                       │  │
│  │   - Add to error list                                            │  │
│  │                                                                   │  │
│  │ ALWAYS:                                                           │  │
│  │   - Returns valid dict                                           │  │
│  │   - Includes all discovered instances                            │  │
│  │   - Includes all errors                                          │  │
│  └────────────────────────────────────────────────────┼──────────────┘  │
└─────────────────────────────────────────────────────────┼────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   Discover Account Instances                            │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ TRY:                                                              │  │
│  │   ThreadPoolExecutor (4 workers):                                │  │
│  │                                                                   │  │
│  │   FOR EACH REGION (parallel):                                    │  │
│  │     TRY:                                                          │  │
│  │       - Submit task                                              │  │
│  │       - Wait for result (60s timeout)                            │  │
│  │       - Discover region instances ──────────┐                    │  │
│  │       - Collect results                     │                    │  │
│  │     CATCH:                                   │                    │  │
│  │       - Analyze error                        │                    │  │
│  │       - Add to error list                    │                    │  │
│  │       - CONTINUE to next region ◄────────────┘                    │  │
│  │                                                                   │  │
│  │ CATCH:                                                            │  │
│  │   - Log ThreadPoolExecutor failure                               │  │
│  │   - Add to error list                                            │  │
│  │                                                                   │  │
│  │ ALWAYS:                                                           │  │
│  │   - Returns tuple (instances, errors)                            │  │
│  └────────────────────────────────────────────────────┼──────────────┘  │
└─────────────────────────────────────────────────────────┼────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Discover Region Instances                            │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ TRY:                                                              │  │
│  │   1. Get RDS client (current or cross-account)                   │  │
│  │   2. Create paginator                                            │  │
│  │                                                                   │  │
│  │   TRY:                                                            │  │
│  │     FOR EACH PAGE:                                               │  │
│  │       FOR EACH INSTANCE:                                         │  │
│  │         TRY:                                                      │  │
│  │           - Extract metadata ──────────┐                         │  │
│  │           - Add to list                │                         │  │
│  │         CATCH:                          │                         │  │
│  │           - Log warning                 │                         │  │
│  │           - SKIP instance ◄─────────────┘                         │  │
│  │           - CONTINUE to next                                     │  │
│  │   CATCH:                                                          │  │
│  │     - Log pagination error                                       │  │
│  │     - RE-RAISE (caught by parent)                                │  │
│  │                                                                   │  │
│  │ CATCH:                                                            │  │
│  │   - Log region failure                                           │  │
│  │   - RE-RAISE (caught by parent)                                  │  │
│  │                                                                   │  │
│  │ SUCCESS:                                                          │  │
│  │   - Returns list of instances                                    │  │
│  └────────────────────────────────────────────────────┼──────────────┘  │
└─────────────────────────────────────────────────────────┼────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   Extract Instance Metadata                             │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ TRY:                                                              │  │
│  │   TRY: Extract tags                                              │  │
│  │   CATCH: Use empty dict                                          │  │
│  │                                                                   │  │
│  │   TRY: Extract endpoint                                          │  │
│  │   CATCH: Use None                                                │  │
│  │                                                                   │  │
│  │   TRY: Extract VPC ID                                            │  │
│  │   CATCH: Use None                                                │  │
│  │                                                                   │  │
│  │   TRY: Extract timestamp                                         │  │
│  │   CATCH: Use None                                                │  │
│  │                                                                   │  │
│  │   Build instance dict with safe defaults                         │  │
│  │                                                                   │  │
│  │ CATCH:                                                            │  │
│  │   - Log error                                                    │  │
│  │   - Return minimal instance data                                 │  │
│  │   - Include extraction_error field                               │  │
│  │                                                                   │  │
│  │ ALWAYS:                                                           │  │
│  │   - Returns valid instance dict                                  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Error Propagation Strategy

```
┌──────────────────────────────────────────────────────────────────┐
│ Level 1: Lambda Handler                                         │
│ Strategy: CATCH ALL, NEVER THROW                                │
│ Returns: Always HTTP 200 (unless catastrophic)                  │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Never throws
                              │
┌──────────────────────────────────────────────────────────────────┐
│ Level 2: Discover All Instances                                 │
│ Strategy: CATCH ALL, NEVER THROW                                │
│ Returns: Always valid dict with instances and errors            │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Never throws
                              │
┌──────────────────────────────────────────────────────────────────┐
│ Level 3: Discover Account Instances                             │
│ Strategy: CATCH ALL, NEVER THROW                                │
│ Returns: Always valid tuple (instances, errors)                 │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Throws on failure
                              │ (caught by parent)
┌──────────────────────────────────────────────────────────────────┐
│ Level 4: Discover Region Instances                              │
│ Strategy: CATCH, RE-RAISE to signal failure                     │
│ Returns: List of instances OR throws                            │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ Never throws
                              │
┌──────────────────────────────────────────────────────────────────┐
│ Level 5: Extract Instance Metadata                              │
│ Strategy: CATCH ALL, NEVER THROW                                │
│ Returns: Always valid instance dict (minimal on error)          │
└──────────────────────────────────────────────────────────────────┘
```

## Example Execution Flow

### Scenario: 3 Accounts, 2 Regions Each, Account 2 Fails

```
Start Lambda
  │
  ├─ Load Config ✓
  │
  ├─ Discover All Instances
  │   │
  │   ├─ Account 1 (Current)
  │   │   ├─ Region us-east-1
  │   │   │   ├─ Instance A ✓
  │   │   │   ├─ Instance B ✓
  │   │   │   └─ Instance C ✓
  │   │   │
  │   │   └─ Region ap-southeast-1
  │   │       ├─ Instance D ✓
  │   │       └─ Instance E ✓
  │   │
  │   ├─ Account 2 (Cross-Account)
  │   │   └─ ✗ Access Denied
  │   │       └─ Error logged with remediation
  │   │       └─ CONTINUE to next account
  │   │
  │   └─ Account 3 (Cross-Account)
  │       ├─ Region us-east-1
  │       │   ├─ Instance F ✓
  │       │   └─ Instance G ✓
  │       │
  │       └─ Region ap-southeast-1
  │           └─ ✗ Region not enabled
  │               └─ Error logged with remediation
  │               └─ CONTINUE to next region
  │
  ├─ Persist to DynamoDB ✓
  │   └─ 7 instances saved
  │
  ├─ Publish Metrics ✓
  │
  └─ Return HTTP 200
      └─ Body:
          ├─ total_instances: 7
          ├─ accounts_attempted: 3
          ├─ accounts_scanned: 2
          ├─ regions_scanned: 3
          ├─ errors: [
          │     {account: 2, type: "access_denied", remediation: "..."},
          │     {account: 3, region: "ap-southeast-1", type: "region_not_enabled", remediation: "..."}
          │   ]
          └─ execution_status: "completed_with_errors"
```

## Error Isolation Visualization

```
┌─────────────────────────────────────────────────────────────────┐
│                         Lambda Execution                        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  Account 1   │  │  Account 2   │  │  Account 3   │         │
│  │              │  │              │  │              │         │
│  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │         │
│  │  │Region A│  │  │  │ ERROR  │  │  │  │Region A│  │         │
│  │  │  ✓✓✓   │  │  │  │   ✗    │  │  │  │  ✓✓    │  │         │
│  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │         │
│  │              │  │      │       │  │              │         │
│  │  ┌────────┐  │  │      │       │  │  ┌────────┐  │         │
│  │  │Region B│  │  │      │       │  │  │ ERROR  │  │         │
│  │  │  ✓✓    │  │  │      │       │  │  │   ✗    │  │         │
│  │  └────────┘  │  │      │       │  │  └────────┘  │         │
│  │              │  │      │       │  │              │         │
│  │   SUCCESS    │  │   FAILED     │  │  PARTIAL     │         │
│  │   5 inst.    │  │   Logged     │  │  2 inst.     │         │
│  └──────────────┘  │   Continue   │  └──────────────┘         │
│                    └──────────────┘                            │
│                                                                 │
│  Result: 7 instances discovered, 2 errors logged               │
│  Status: HTTP 200 (Success with errors)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Parallel Region Scanning

```
Account Discovery
      │
      ├─ ThreadPoolExecutor (4 workers)
      │
      ├─ Worker 1: us-east-1      ──┐
      ├─ Worker 2: us-west-2      ──┤
      ├─ Worker 3: eu-west-1      ──┼─► All run in parallel
      └─ Worker 4: ap-southeast-1 ──┘
                                     │
                                     │ Each isolated
                                     │ Failures don't propagate
                                     │
                                     ▼
                            Collect all results
                            (instances + errors)
```

## Key Takeaways

1. **Isolation**: Each level is isolated from failures in child levels
2. **Continuation**: Errors are logged and execution continues
3. **Resilience**: Multiple layers of try-catch ensure no propagation
4. **Visibility**: All errors logged with context and remediation
5. **Success**: Lambda succeeds as long as ANY discovery succeeds

## Monitoring Points

```
┌─────────────────────────────────────────────────────────────────┐
│                      Monitoring Points                          │
│                                                                 │
│  1. Lambda Invocation                                           │
│     └─ Metric: Invocations, Errors, Duration                   │
│                                                                 │
│  2. Account Discovery                                           │
│     └─ Metric: AccountsAttempted, AccountsScanned              │
│                                                                 │
│  3. Region Discovery                                            │
│     └─ Metric: RegionsScanned, RegionErrors                    │
│                                                                 │
│  4. Instance Discovery                                          │
│     └─ Metric: InstancesDiscovered, InstanceErrors             │
│                                                                 │
│  5. Error Analysis                                              │
│     └─ Metric: ErrorCount, ErrorTypes, ErrorSeverity           │
│                                                                 │
│  6. Success Rate                                                │
│     └─ Metric: SuccessRate = AccountsScanned/AccountsAttempted │
└─────────────────────────────────────────────────────────────────┘
```
