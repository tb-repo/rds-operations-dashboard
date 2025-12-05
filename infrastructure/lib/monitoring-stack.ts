import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export interface MonitoringStackProps extends cdk.StackProps {
  discoveryFunction: lambda.IFunction;
  healthMonitorFunction: lambda.IFunction;
  costAnalyzerFunction: lambda.IFunction;
  complianceCheckerFunction: lambda.IFunction;
  operationsFunction: lambda.IFunction;
  alertEmail: string;
  apiGatewayName?: string;
  dynamoDbTableNames?: string[];
}

export class MonitoringStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    // SNS Topic for Alerts
    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      displayName: 'RDS Operations Dashboard Alerts',
      topicName: 'rds-ops-dashboard-alerts',
    });

    // Email subscription for alerts
    this.alarmTopic.addSubscription(
      new subscriptions.EmailSubscription(props.alertEmail)
    );

    // CloudWatch Dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'OperationsDashboard', {
      dashboardName: 'RDS-Operations-Dashboard',
    });

    // Create alarms and add widgets
    this.createDiscoveryAlarms(props.discoveryFunction);
    this.createHealthMonitorAlarms(props.healthMonitorFunction);
    this.createCostAnalyzerAlarms(props.costAnalyzerFunction);
    this.createComplianceAlarms(props.complianceCheckerFunction);
    this.createOperationsAlarms(props.operationsFunction);
    
    this.createDashboardWidgets(props);

    // Create DynamoDB alarms if table names provided
    if (props.dynamoDbTableNames && props.dynamoDbTableNames.length > 0) {
      this.createDynamoDbAlarms(props.dynamoDbTableNames);
    }

    // Outputs
    new cdk.CfnOutput(this, 'AlarmTopicArn', {
      value: this.alarmTopic.topicArn,
      description: 'SNS Topic ARN for alarms',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });
  }

  private createDynamoDbAlarms(tableNames: string[]): void {
    // Create throttling alarm for each table (REQ-5.5: DynamoDB throttling)
    tableNames.forEach((tableName, index) => {
      const throttleAlarm = new cloudwatch.Alarm(this, `DynamoDbThrottle${index}`, {
        metric: new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'UserErrors',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: `DynamoDB table ${tableName} is experiencing throttling`,
        alarmName: `RDS-DynamoDB-Throttle-${tableName}`,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      throttleAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

      // High read capacity alarm
      const highReadCapacity = new cloudwatch.Alarm(this, `DynamoDbHighRead${index}`, {
        metric: new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'ConsumedReadCapacityUnits',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 80, // 80% of provisioned capacity (adjust based on actual provisioning)
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: `DynamoDB table ${tableName} read capacity is high`,
        alarmName: `RDS-DynamoDB-HighRead-${tableName}`,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      highReadCapacity.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

      // High write capacity alarm
      const highWriteCapacity = new cloudwatch.Alarm(this, `DynamoDbHighWrite${index}`, {
        metric: new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'ConsumedWriteCapacityUnits',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 80, // 80% of provisioned capacity (adjust based on actual provisioning)
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        alarmDescription: `DynamoDB table ${tableName} write capacity is high`,
        alarmName: `RDS-DynamoDB-HighWrite-${tableName}`,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      highWriteCapacity.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    });
  }

  private createDiscoveryAlarms(discoveryFunction: lambda.IFunction): void {
    // Discovery Function Errors
    const discoveryErrors = new cloudwatch.Alarm(this, 'DiscoveryErrors', {
      metric: discoveryFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Discovery function has errors',
      alarmName: 'RDS-Discovery-Errors',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    discoveryErrors.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Discovery Function Duration
    const discoveryDuration = new cloudwatch.Alarm(this, 'DiscoveryDuration', {
      metric: discoveryFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 180000, // 3 minutes
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Discovery function taking too long',
      alarmName: 'RDS-Discovery-Duration',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    discoveryDuration.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Discovery Function Throttles
    const discoveryThrottles = new cloudwatch.Alarm(this, 'DiscoveryThrottles', {
      metric: discoveryFunction.metricThrottles({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Discovery function is being throttled',
      alarmName: 'RDS-Discovery-Throttles',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    discoveryThrottles.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }

  private createHealthMonitorAlarms(healthMonitorFunction: lambda.IFunction): void {
    // Health Monitor Errors
    const healthErrors = new cloudwatch.Alarm(this, 'HealthMonitorErrors', {
      metric: healthMonitorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 3,
      evaluationPeriods: 2,
      alarmDescription: 'Health monitor has multiple errors',
      alarmName: 'RDS-HealthMonitor-Errors',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    healthErrors.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Cache Hit Rate (Custom Metric)
    const cacheHitRate = new cloudwatch.Metric({
      namespace: 'RDS/Operations',
      metricName: 'CacheHitRate',
      statistic: 'Average',
      period: cdk.Duration.minutes(15),
    });

    const lowCacheHitRate = new cloudwatch.Alarm(this, 'LowCacheHitRate', {
      metric: cacheHitRate,
      threshold: 50,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      alarmDescription: 'Cache hit rate is below 50%',
      alarmName: 'RDS-LowCacheHitRate',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    lowCacheHitRate.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }

  private createCostAnalyzerAlarms(costAnalyzerFunction: lambda.IFunction): void {
    // Cost Analyzer Errors
    const costErrors = new cloudwatch.Alarm(this, 'CostAnalyzerErrors', {
      metric: costAnalyzerFunction.metricErrors({
        period: cdk.Duration.hours(1),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Cost analyzer has errors',
      alarmName: 'RDS-CostAnalyzer-Errors',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    costErrors.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Total Monthly Cost (Custom Metric)
    const totalCost = new cloudwatch.Metric({
      namespace: 'RDS/Operations',
      metricName: 'TotalMonthlyCost',
      statistic: 'Maximum',
      period: cdk.Duration.days(1),
    });

    const highCost = new cloudwatch.Alarm(this, 'HighMonthlyCost', {
      metric: totalCost,
      threshold: 5000, // $5000/month
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Monthly RDS cost exceeds $5000',
      alarmName: 'RDS-HighMonthlyCost',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    highCost.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }

  private createComplianceAlarms(complianceFunction: lambda.IFunction): void {
    // Compliance Checker Errors
    const complianceErrors = new cloudwatch.Alarm(this, 'ComplianceErrors', {
      metric: complianceFunction.metricErrors({
        period: cdk.Duration.hours(1),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Compliance checker has errors',
      alarmName: 'RDS-Compliance-Errors',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    complianceErrors.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Critical Violations (Custom Metric)
    const criticalViolations = new cloudwatch.Metric({
      namespace: 'RDS/Operations',
      metricName: 'CriticalViolations',
      statistic: 'Maximum',
      period: cdk.Duration.hours(1),
    });

    const highViolations = new cloudwatch.Alarm(this, 'HighCriticalViolations', {
      metric: criticalViolations,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'More than 5 critical compliance violations',
      alarmName: 'RDS-HighCriticalViolations',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    highViolations.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }

  private createOperationsAlarms(operationsFunction: lambda.IFunction): void {
    // Operations Function Errors
    const opsErrors = new cloudwatch.Alarm(this, 'OperationsErrors', {
      metric: operationsFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 3,
      evaluationPeriods: 1,
      alarmDescription: 'Operations service has multiple errors',
      alarmName: 'RDS-Operations-Errors',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    opsErrors.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Error Rate Alarm (REQ-5.5: error rate > 5% for 5 minutes)
    const errorRate = new cloudwatch.MathExpression({
      expression: '(errors / invocations) * 100',
      usingMetrics: {
        errors: operationsFunction.metricErrors({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        }),
        invocations: operationsFunction.metricInvocations({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        }),
      },
      period: cdk.Duration.minutes(5),
    });

    const highErrorRate = new cloudwatch.Alarm(this, 'HighOperationsErrorRate', {
      metric: errorRate,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Operations error rate exceeds 5% for 5 minutes',
      alarmName: 'RDS-Operations-HighErrorRate',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    highErrorRate.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // P99 Latency Alarm (REQ-5.5: P99 latency > 3 seconds)
    const p99Latency = new cloudwatch.Alarm(this, 'HighOperationsP99Latency', {
      metric: operationsFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'p99',
      }),
      threshold: 3000, // 3 seconds in milliseconds
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Operations P99 latency exceeds 3 seconds',
      alarmName: 'RDS-Operations-HighP99Latency',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    p99Latency.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Concurrent Executions Alarm (REQ-5.5: > 80% of reserved concurrent executions)
    const concurrentExecutions = new cloudwatch.Alarm(this, 'HighConcurrentExecutions', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'ConcurrentExecutions',
        dimensionsMap: {
          FunctionName: operationsFunction.functionName,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 800, // 80% of 1000 (default account limit)
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Lambda concurrent executions exceed 80% of limit',
      alarmName: 'RDS-Operations-HighConcurrency',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    concurrentExecutions.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));

    // Operation Success Rate (Custom Metric)
    const successRate = new cloudwatch.Metric({
      namespace: 'RDS/Operations',
      metricName: 'OperationSuccessRate',
      statistic: 'Average',
      period: cdk.Duration.hours(1),
    });

    const lowSuccessRate = new cloudwatch.Alarm(this, 'LowOperationSuccessRate', {
      metric: successRate,
      threshold: 90,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      alarmDescription: 'Operation success rate below 90%',
      alarmName: 'RDS-LowOperationSuccessRate',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    lowSuccessRate.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }


  private createDashboardWidgets(props: MonitoringStackProps): void {
    // Row 1: System Overview
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({
        markdown: '# RDS Operations Dashboard\n## System Health and Performance Metrics',
        width: 24,
        height: 2,
      })
    );

    // Row 2: Lambda Function Metrics
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Invocations',
        left: [
          props.discoveryFunction.metricInvocations({ label: 'Discovery', statistic: 'Sum' }),
          props.healthMonitorFunction.metricInvocations({ label: 'Health Monitor', statistic: 'Sum' }),
          props.costAnalyzerFunction.metricInvocations({ label: 'Cost Analyzer', statistic: 'Sum' }),
          props.complianceCheckerFunction.metricInvocations({ label: 'Compliance', statistic: 'Sum' }),
          props.operationsFunction.metricInvocations({ label: 'Operations', statistic: 'Sum' }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Errors',
        left: [
          props.discoveryFunction.metricErrors({ label: 'Discovery', statistic: 'Sum', color: '#d62728' }),
          props.healthMonitorFunction.metricErrors({ label: 'Health Monitor', statistic: 'Sum', color: '#ff7f0e' }),
          props.costAnalyzerFunction.metricErrors({ label: 'Cost Analyzer', statistic: 'Sum', color: '#2ca02c' }),
          props.complianceCheckerFunction.metricErrors({ label: 'Compliance', statistic: 'Sum', color: '#9467bd' }),
          props.operationsFunction.metricErrors({ label: 'Operations', statistic: 'Sum', color: '#8c564b' }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Row 3: Lambda Duration and Throttles
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Duration (ms)',
        left: [
          props.discoveryFunction.metricDuration({ label: 'Discovery', statistic: 'Average' }),
          props.healthMonitorFunction.metricDuration({ label: 'Health Monitor', statistic: 'Average' }),
          props.costAnalyzerFunction.metricDuration({ label: 'Cost Analyzer', statistic: 'Average' }),
          props.complianceCheckerFunction.metricDuration({ label: 'Compliance', statistic: 'Average' }),
          props.operationsFunction.metricDuration({ label: 'Operations', statistic: 'Average' }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Throttles',
        left: [
          props.discoveryFunction.metricThrottles({ label: 'Discovery', statistic: 'Sum' }),
          props.healthMonitorFunction.metricThrottles({ label: 'Health Monitor', statistic: 'Sum' }),
          props.costAnalyzerFunction.metricThrottles({ label: 'Cost Analyzer', statistic: 'Sum' }),
          props.complianceCheckerFunction.metricThrottles({ label: 'Compliance', statistic: 'Sum' }),
          props.operationsFunction.metricThrottles({ label: 'Operations', statistic: 'Sum' }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Row 4: Custom Business Metrics
    this.dashboard.addWidgets(
      new cloudwatch.SingleValueWidget({
        title: 'Total RDS Instances',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'TotalInstances',
            statistic: 'Maximum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 6,
        height: 4,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Critical Alerts',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'CriticalAlerts',
            statistic: 'Maximum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 6,
        height: 4,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Cache Hit Rate (%)',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'CacheHitRate',
            statistic: 'Average',
            period: cdk.Duration.minutes(15),
          }),
        ],
        width: 6,
        height: 4,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Monthly Cost ($)',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'TotalMonthlyCost',
            statistic: 'Maximum',
            period: cdk.Duration.days(1),
          }),
        ],
        width: 6,
        height: 4,
      })
    );

    // Row 5: Operations Metrics
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Operations Executed',
        left: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'OperationsExecuted',
            statistic: 'Sum',
            period: cdk.Duration.hours(1),
            label: 'Total Operations',
          }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Operation Success Rate (%)',
        left: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'OperationSuccessRate',
            statistic: 'Average',
            period: cdk.Duration.hours(1),
          }),
        ],
        leftYAxis: {
          min: 0,
          max: 100,
        },
        width: 12,
        height: 6,
      })
    );

    // Row 6: Compliance Metrics
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Compliance Score (%)',
        left: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'ComplianceScore',
            statistic: 'Average',
            period: cdk.Duration.hours(1),
          }),
        ],
        leftYAxis: {
          min: 0,
          max: 100,
        },
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Compliance Violations by Severity',
        left: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'CriticalViolations',
            statistic: 'Maximum',
            period: cdk.Duration.hours(1),
            label: 'Critical',
            color: '#d62728',
          }),
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'HighViolations',
            statistic: 'Maximum',
            period: cdk.Duration.hours(1),
            label: 'High',
            color: '#ff7f0e',
          }),
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'MediumViolations',
            statistic: 'Maximum',
            period: cdk.Duration.hours(1),
            label: 'Medium',
            color: '#ffbb78',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Row 7: Cost Trends
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Daily Cost Trend',
        left: [
          new cloudwatch.Metric({
            namespace: 'RDS/Operations',
            metricName: 'TotalMonthlyCost',
            statistic: 'Maximum',
            period: cdk.Duration.days(1),
          }),
        ],
        width: 24,
        height: 6,
      })
    );

    // Row 8: API Gateway Metrics (if provided)
    if (props.apiGatewayName) {
      this.dashboard.addWidgets(
        new cloudwatch.TextWidget({
          markdown: '## API Gateway Metrics',
          width: 24,
          height: 1,
        })
      );

      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'API Gateway Requests',
          left: [
            new cloudwatch.Metric({
              namespace: 'AWS/ApiGateway',
              metricName: 'Count',
              dimensionsMap: {
                ApiName: props.apiGatewayName,
              },
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
              label: 'Total Requests',
            }),
          ],
          width: 12,
          height: 6,
        }),
        new cloudwatch.GraphWidget({
          title: 'API Gateway Latency',
          left: [
            new cloudwatch.Metric({
              namespace: 'AWS/ApiGateway',
              metricName: 'Latency',
              dimensionsMap: {
                ApiName: props.apiGatewayName,
              },
              statistic: 'Average',
              period: cdk.Duration.minutes(5),
              label: 'Average Latency',
              color: '#1f77b4',
            }),
            new cloudwatch.Metric({
              namespace: 'AWS/ApiGateway',
              metricName: 'Latency',
              dimensionsMap: {
                ApiName: props.apiGatewayName,
              },
              statistic: 'p99',
              period: cdk.Duration.minutes(5),
              label: 'P99 Latency',
              color: '#ff7f0e',
            }),
          ],
          width: 12,
          height: 6,
        })
      );

      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'API Gateway 4XX Errors',
          left: [
            new cloudwatch.Metric({
              namespace: 'AWS/ApiGateway',
              metricName: '4XXError',
              dimensionsMap: {
                ApiName: props.apiGatewayName,
              },
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
              color: '#ff7f0e',
            }),
          ],
          width: 12,
          height: 6,
        }),
        new cloudwatch.GraphWidget({
          title: 'API Gateway 5XX Errors',
          left: [
            new cloudwatch.Metric({
              namespace: 'AWS/ApiGateway',
              metricName: '5XXError',
              dimensionsMap: {
                ApiName: props.apiGatewayName,
              },
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
              color: '#d62728',
            }),
          ],
          width: 12,
          height: 6,
        })
      );
    }

    // Row 9: DynamoDB Metrics (if provided)
    if (props.dynamoDbTableNames && props.dynamoDbTableNames.length > 0) {
      this.dashboard.addWidgets(
        new cloudwatch.TextWidget({
          markdown: '## DynamoDB Metrics',
          width: 24,
          height: 1,
        })
      );

      // Create metrics for each table
      const readCapacityMetrics = props.dynamoDbTableNames.map(tableName =>
        new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'ConsumedReadCapacityUnits',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: tableName,
        })
      );

      const writeCapacityMetrics = props.dynamoDbTableNames.map(tableName =>
        new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'ConsumedWriteCapacityUnits',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: tableName,
        })
      );

      const throttleMetrics = props.dynamoDbTableNames.map(tableName =>
        new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'UserErrors',
          dimensionsMap: {
            TableName: tableName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: tableName,
        })
      );

      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'DynamoDB Read Capacity',
          left: readCapacityMetrics,
          width: 12,
          height: 6,
        }),
        new cloudwatch.GraphWidget({
          title: 'DynamoDB Write Capacity',
          left: writeCapacityMetrics,
          width: 12,
          height: 6,
        })
      );

      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'DynamoDB Throttles',
          left: throttleMetrics,
          width: 24,
          height: 6,
        })
      );
    }
  }
}
