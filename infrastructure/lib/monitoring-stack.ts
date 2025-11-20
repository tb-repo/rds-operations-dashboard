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
  }
}
