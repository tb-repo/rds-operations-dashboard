"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.MonitoringStack = void 0;
const cdk = __importStar(require("aws-cdk-lib"));
const cloudwatch = __importStar(require("aws-cdk-lib/aws-cloudwatch"));
const cloudwatch_actions = __importStar(require("aws-cdk-lib/aws-cloudwatch-actions"));
const sns = __importStar(require("aws-cdk-lib/aws-sns"));
const subscriptions = __importStar(require("aws-cdk-lib/aws-sns-subscriptions"));
class MonitoringStack extends cdk.Stack {
    constructor(scope, id, props) {
        super(scope, id, props);
        // SNS Topic for Alerts
        this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
            displayName: 'RDS Operations Dashboard Alerts',
            topicName: 'rds-ops-dashboard-alerts',
        });
        // Email subscription for alerts
        this.alarmTopic.addSubscription(new subscriptions.EmailSubscription(props.alertEmail));
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
    createDynamoDbAlarms(tableNames) {
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
    createDiscoveryAlarms(discoveryFunction) {
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
    createHealthMonitorAlarms(healthMonitorFunction) {
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
    createCostAnalyzerAlarms(costAnalyzerFunction) {
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
    createComplianceAlarms(complianceFunction) {
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
    createOperationsAlarms(operationsFunction) {
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
    createDashboardWidgets(props) {
        // Row 1: System Overview
        this.dashboard.addWidgets(new cloudwatch.TextWidget({
            markdown: '# RDS Operations Dashboard\n## System Health and Performance Metrics',
            width: 24,
            height: 2,
        }));
        // Row 2: Lambda Function Metrics
        this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
        }), new cloudwatch.GraphWidget({
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
        }));
        // Row 3: Lambda Duration and Throttles
        this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
        }), new cloudwatch.GraphWidget({
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
        }));
        // Row 4: Custom Business Metrics
        this.dashboard.addWidgets(new cloudwatch.SingleValueWidget({
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
        }), new cloudwatch.SingleValueWidget({
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
        }), new cloudwatch.SingleValueWidget({
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
        }), new cloudwatch.SingleValueWidget({
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
        }));
        // Row 5: Operations Metrics
        this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
        }), new cloudwatch.GraphWidget({
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
        }));
        // Row 6: Compliance Metrics
        this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
        }), new cloudwatch.GraphWidget({
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
        }));
        // Row 7: Cost Trends
        this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
        }));
        // Row 8: API Gateway Metrics (if provided)
        if (props.apiGatewayName) {
            this.dashboard.addWidgets(new cloudwatch.TextWidget({
                markdown: '## API Gateway Metrics',
                width: 24,
                height: 1,
            }));
            this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
            }), new cloudwatch.GraphWidget({
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
            }));
            this.dashboard.addWidgets(new cloudwatch.GraphWidget({
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
            }), new cloudwatch.GraphWidget({
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
            }));
        }
        // Row 9: DynamoDB Metrics (if provided)
        if (props.dynamoDbTableNames && props.dynamoDbTableNames.length > 0) {
            this.dashboard.addWidgets(new cloudwatch.TextWidget({
                markdown: '## DynamoDB Metrics',
                width: 24,
                height: 1,
            }));
            // Create metrics for each table
            const readCapacityMetrics = props.dynamoDbTableNames.map(tableName => new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedReadCapacityUnits',
                dimensionsMap: {
                    TableName: tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
                label: tableName,
            }));
            const writeCapacityMetrics = props.dynamoDbTableNames.map(tableName => new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedWriteCapacityUnits',
                dimensionsMap: {
                    TableName: tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
                label: tableName,
            }));
            const throttleMetrics = props.dynamoDbTableNames.map(tableName => new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'UserErrors',
                dimensionsMap: {
                    TableName: tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
                label: tableName,
            }));
            this.dashboard.addWidgets(new cloudwatch.GraphWidget({
                title: 'DynamoDB Read Capacity',
                left: readCapacityMetrics,
                width: 12,
                height: 6,
            }), new cloudwatch.GraphWidget({
                title: 'DynamoDB Write Capacity',
                left: writeCapacityMetrics,
                width: 12,
                height: 6,
            }));
            this.dashboard.addWidgets(new cloudwatch.GraphWidget({
                title: 'DynamoDB Throttles',
                left: throttleMetrics,
                width: 24,
                height: 6,
            }));
        }
    }
}
exports.MonitoringStack = MonitoringStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoibW9uaXRvcmluZy1zdGFjay5qcyIsInNvdXJjZVJvb3QiOiIiLCJzb3VyY2VzIjpbIm1vbml0b3Jpbmctc3RhY2sudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6Ijs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0FBQUEsaURBQW1DO0FBQ25DLHVFQUF5RDtBQUN6RCx1RkFBeUU7QUFDekUseURBQTJDO0FBQzNDLGlGQUFtRTtBQWVuRSxNQUFhLGVBQWdCLFNBQVEsR0FBRyxDQUFDLEtBQUs7SUFJNUMsWUFBWSxLQUFnQixFQUFFLEVBQVUsRUFBRSxLQUEyQjtRQUNuRSxLQUFLLENBQUMsS0FBSyxFQUFFLEVBQUUsRUFBRSxLQUFLLENBQUMsQ0FBQztRQUV4Qix1QkFBdUI7UUFDdkIsSUFBSSxDQUFDLFVBQVUsR0FBRyxJQUFJLEdBQUcsQ0FBQyxLQUFLLENBQUMsSUFBSSxFQUFFLFlBQVksRUFBRTtZQUNsRCxXQUFXLEVBQUUsaUNBQWlDO1lBQzlDLFNBQVMsRUFBRSwwQkFBMEI7U0FDdEMsQ0FBQyxDQUFDO1FBRUgsZ0NBQWdDO1FBQ2hDLElBQUksQ0FBQyxVQUFVLENBQUMsZUFBZSxDQUM3QixJQUFJLGFBQWEsQ0FBQyxpQkFBaUIsQ0FBQyxLQUFLLENBQUMsVUFBVSxDQUFDLENBQ3RELENBQUM7UUFFRix1QkFBdUI7UUFDdkIsSUFBSSxDQUFDLFNBQVMsR0FBRyxJQUFJLFVBQVUsQ0FBQyxTQUFTLENBQUMsSUFBSSxFQUFFLHFCQUFxQixFQUFFO1lBQ3JFLGFBQWEsRUFBRSwwQkFBMEI7U0FDMUMsQ0FBQyxDQUFDO1FBRUgsZ0NBQWdDO1FBQ2hDLElBQUksQ0FBQyxxQkFBcUIsQ0FBQyxLQUFLLENBQUMsaUJBQWlCLENBQUMsQ0FBQztRQUNwRCxJQUFJLENBQUMseUJBQXlCLENBQUMsS0FBSyxDQUFDLHFCQUFxQixDQUFDLENBQUM7UUFDNUQsSUFBSSxDQUFDLHdCQUF3QixDQUFDLEtBQUssQ0FBQyxvQkFBb0IsQ0FBQyxDQUFDO1FBQzFE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LHlCQUF5QjtnQkFDaEMsSUFBSSxFQUFFLG9CQUFvQjtnQkFDMUIsS0FBSyxFQUFFLEVBQUU7Z0JBQ1QsTUFBTSxFQUFFLENBQUM7YUFDVixDQUFDLENBQ0gsQ0FBQztZQUVGLElBQUksQ0FBQyxTQUFTLENBQUMsVUFBVSxDQUN2QixJQUFJLFVBQVUsQ0FBQyxXQUFXLENBQUM7Z0JBQ3pCLEtBQUssRUFBRSxvQkFBb0I7Z0JBQzNCLElBQUksRUFBRSxlQUFlO2dCQUNyQixLQUFLLEVBQUUsRUFBRTtnQkFDVCxNQUFNLEVBQUUsQ0FBQzthQUNWLENBQUMsQ0FDSCxDQUFDO1FBQ0osQ0FBQztJQUNILENBQUM7Q0FDRjtBQXZ2QkQsMENBdXZCQyIsInNvdXJjZXNDb250ZW50IjpbImltcG9ydCAqIGFzIGNkayBmcm9tICdhd3MtY2RrLWxpYic7XHJcbmltcG9ydCAqIGFzIGNsb3Vkd2F0Y2ggZnJvbSAnYXdzLWNkay1saWIvYXdzLWNsb3Vkd2F0Y2gnO1xyXG5pbXBvcnQgKiBhcyBjbG91ZHdhdGNoX2FjdGlvbnMgZnJvbSAnYXdzLWNkay1saWIvYXdzLWNsb3Vkd2F0Y2gtYWN0aW9ucyc7XHJcbmltcG9ydCAqIGFzIHNucyBmcm9tICdhd3MtY2RrLWxpYi9hd3Mtc25zJztcclxuaW1wb3J0ICogYXMgc3Vic2NyaXB0aW9ucyBmcm9tICdhd3MtY2RrLWxpYi9hd3Mtc25zLXN1YnNjcmlwdGlvbnMnO1xyXG5pbXBvcnQgKiBhcyBsYW1iZGEgZnJvbSAnYXdzLWNkay1saWIvYXdzLWxhbWJkYSc7XHJcbmltcG9ydCB7IENvbnN0cnVjdCB9IGZyb20gJ2NvbnN0cnVjdHMnO1xyXG5cclxuZXhwb3J0IGludGVyZmFjZSBNb25pdG9yaW5nU3RhY2tQcm9wcyBleHRlbmRzIGNkay5TdGFja1Byb3BzIHtcclxuICBkaXNjb3ZlcnlGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBoZWFsdGhNb25pdG9yRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgY29zdEFuYWx5emVyRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgY29tcGxpYW5jZUNoZWNrZXJGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBvcGVyYXRpb25zRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgYWxlcnRFbWFpbDogc3RyaW5nO1xyXG4gIGFwaUdhdGV3YXlOYW1lPzogc3RyaW5nO1xyXG4gIGR5bmFtb0RiVGFibGVOYW1lcz86IHN0cmluZ1tdO1xyXG59XHJcblxyXG5leHBvcnQgY2xhc3MgTW9uaXRvcmluZ1N0YWNrIGV4dGVuZHMgY2RrLlN0YWNrIHtcclxuICBwdWJsaWMgcmVhZG9ubHkgYWxhcm1Ub3BpYzogc25zLlRvcGljO1xyXG4gIHB1YmxpYyByZWFkb25seSBkYXNoYm9hcmQ6IGNsb3Vkd2F0Y2guRGFzaGJvYXJkO1xyXG5cclxuICBjb25zdHJ1Y3RvcihzY29wZTogQ29uc3RydWN0LCBpZDogc3RyaW5nLCBwcm9wczogTW9uaXRvcmluZ1N0YWNrUHJvcHMpIHtcclxuICAgIHN1cGVyKHNjb3BlLCBpZCwgcHJvcHMpO1xyXG5cclxuICAgIC8vIFNOUyBUb3BpYyBmb3IgQWxlcnRzXHJcbiAgICB0aGlzLmFsYXJtVG9waWMgPSBuZXcgc25zLlRvcGljKHRoaXMsICdBbGFybVRvcGljJywge1xyXG4gICAgICBkaXNwbGF5TmFtZTogJ1JEUyBPcGVyYXRpb25zIERhc2hib2FyZCBBbGVydHMnLFxyXG4gICAgICB0b3BpY05hbWU6ICdyZHMtb3BzLWRhc2hib2FyZC1hbGVydHMnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gRW1haWwgc3Vic2NyaXB0aW9uIGZvciBhbGVydHNcclxuICAgIHRoaXMuYWxhcm1Ub3BpYy5hZGRTdWJzY3JpcHRpb24oXHJcbiAgICAgIG5ldyBzdWJzY3JpcHRpb25zLkVtYWlsU3Vic2NyaXB0aW9uKHByb3BzLmFsZXJ0RW1haWwpXHJcbiAgICApO1xyXG5cclxuICAgIC8vIENsb3VkV2F0Y2ggRGFzaGJvYXJkXHJcbiAgICB0aGlzLmRhc2hib2FyZCA9IG5ldyBjbG91ZHdhdGNoLkRhc2hib2FyZCh0aGlzLCAnT3BlcmF0aW9uc0Rhc2hib2FyZCcsIHtcclxuICAgICAgZGFzaGJvYXJkTmFtZTogJ1JEUy1PcGVyYXRpb25zLURhc2hib2FyZCcsXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBDcmVhdGUgYWxhcm1zIGFuZCBhZGQgd2lkZ2V0c1xyXG4gICAgdGhpcy5jcmVhdGVEaXNjb3ZlcnlBbGFybXMocHJvcHMuZGlzY292ZXJ5RnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVIZWFsdGhNb25pdG9yQWxhcm1zKHByb3BzLmhlYWx0aE1vbml0b3JGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUNvc3RBbmFseXplckFsYXJtcyhwcm9wcy5jb3N0QW5hbHl6ZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUNvbXBsaWFuY2VBbGFybXMocHJvcHMuY29tcGxpYW5jZUNoZWNrZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZU9wZXJhdGlvbnNBbGFybXMocHJvcHMub3BlcmF0aW9uc0Z1bmN0aW9uKTtcclxuICAgIFxyXG4gICAgdGhpcy5jcmVhdGVEYXNoYm9hcmRXaWRnZXRzKHByb3BzKTtcclxuXHJcbiAgICAvLyBDcmVhdGUgRHluYW1vREIgYWxhcm1zIGlmIHRhYmxlIG5hbWVzIHByb3ZpZGVkXHJcbiAgICBpZiAocHJvcHMuZHluYW1vRGJUYWJsZU5hbWVzICYmIHByb3BzLmR5bmFtb0RiVGFibGVOYW1lcy5sZW5ndGggPiAwKSB7XHJcbiAgICAgIHRoaXMuY3JlYXRlRHluYW1vRGJBbGFybXMocHJvcHMuZHluYW1vRGJUYWJsZU5hbWVzKTtcclxuICAgIH1cclxuXHJcbiAgICAvLyBPdXRwdXRzXHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQWxhcm1Ub3BpY0FybicsIHtcclxuICAgICAgdmFsdWU6IHRoaXMuYWxhcm1Ub3BpYy50b3BpY0FybixcclxuICAgICAgZGVzY3JpcHRpb246ICdTTlMgVG9waWMgQVJOIGZvciBhbGFybXMnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0Rhc2hib2FyZFVybCcsIHtcclxuICAgICAgdmFsdWU6IGBodHRwczovL2NvbnNvbGUuYXdzLmFtYXpvbi5jb20vY2xvdWR3YXRjaC9ob21lP3JlZ2lvbj0ke3RoaXMucmVnaW9ufSNkYXNoYm9hcmRzOm5hbWU9JHt0aGlzLmRhc2hib2FyZC5kYXNoYm9hcmROYW1lfWAsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ2xvdWRXYXRjaCBEYXNoYm9hcmQgVVJMJyxcclxuICAgIH0pO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVEeW5hbW9EYkFsYXJtcyh0YWJsZU5hbWVzOiBzdHJpbmdbXSk6IHZvaWQge1xyXG4gICAgLy8gQ3JlYXRlIHRocm90dGxpbmcgYWxhcm0gZm9yIGVhY2ggdGFibGUgKFJFUS01LjU6IER5bmFtb0RCIHRocm90dGxpbmcpXHJcbiAgICB0YWJsZU5hbWVzLmZvckVhY2goKHRhYmxlTmFtZSwgaW5kZXgpID0+IHtcclxuICAgICAgY29uc3QgdGhyb3R0bGVBbGFybSA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsIGBEeW5hbW9EYlRocm90dGxlJHtpbmRleH1gLCB7XHJcbiAgICAgICAgbWV0cmljOiBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0R5bmFtb0RCJyxcclxuICAgICAgICAgIG1ldHJpY05hbWU6ICdVc2VyRXJyb3JzJyxcclxuICAgICAgICAgIGRpbWVuc2lvbnNNYXA6IHtcclxuICAgICAgICAgICAgVGFibGVOYW1lOiB0YWJsZU5hbWUsXHJcbiAgICAgICAgICB9LFxyXG4gICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgdGhyZXNob2xkOiAxLFxyXG4gICAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAxLFxyXG4gICAgICAgIGNvbXBhcmlzb25PcGVyYXRvcjogY2xvdWR3YXRjaC5Db21wYXJpc29uT3BlcmF0b3IuR1JFQVRFUl9USEFOX1RIUkVTSE9MRCxcclxuICAgICAgICBhbGFybURlc2NyaXB0aW9uOiBgRHluYW1vREIgdGFibGUgJHt0YWJsZU5hbWV9IGlzIGV4cGVyaWVuY2luZyB0aHJvdHRsaW5nYCxcclxuICAgICAgICBhbGFybU5hbWU6IGBSRFMtRHluYW1vREItVGhyb3R0bGUtJHt0YWJsZU5hbWV9YCxcclxuICAgICAgICB0cmVhdE1pc3NpbmdEYXRhOiBjbG91ZHdhdGNoLlRyZWF0TWlzc2luZ0RhdGEuTk9UX0JSRUFDSElORyxcclxuICAgICAgfSk7XHJcbiAgICAgIHRocm90dGxlQWxhcm0uYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgICAvLyBIaWdoIHJlYWQgY2FwYWNpdHkgYWxhcm1cclxuICAgICAgY29uc3QgaGlnaFJlYWRDYXBhY2l0eSA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsIGBEeW5hbW9EYkhpZ2hSZWFkJHtpbmRleH1gLCB7XHJcbiAgICAgICAgbWV0cmljOiBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0R5bmFtb0RCJyxcclxuICAgICAgICAgIG1ldHJpY05hbWU6ICdDb25zdW1lZFJlYWRDYXBhY2l0eVVuaXRzJyxcclxuICAgICAgICAgIGRpbWVuc2lvbnNNYXA6IHtcclxuICAgICAgICAgICAgVGFibGVOYW1lOiB0YWJsZU5hbWUsXHJcbiAgICAgICAgICB9LFxyXG4gICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgdGhyZXNob2xkOiA4MCwgLy8gODAlIG9mIHByb3Zpc2lvbmVkIGNhcGFjaXR5IChhZGp1c3QgYmFzZWQgb24gYWN0dWFsIHByb3Zpc2lvbmluZylcclxuICAgICAgICBldmFsdWF0aW9uUGVyaW9kczogMixcclxuICAgICAgICBjb21wYXJpc29uT3BlcmF0b3I6IGNsb3Vkd2F0Y2guQ29tcGFyaXNvbk9wZXJhdG9yLkdSRUFURVJfVEhBTl9USFJFU0hPTEQsXHJcbiAgICAgICAgYWxhcm1EZXNjcmlwdGlvbjogYER5bmFtb0RCIHRhYmxlICR7dGFibGVOYW1lfSByZWFkIGNhcGFjaXR5IGlzIGhpZ2hgLFxyXG4gICAgICAgIGFsYXJtTmFtZTogYFJEUy1EeW5hbW9EQi1IaWdoUmVhZC0ke3RhYmxlTmFtZX1gLFxyXG4gICAgICAgIHRyZWF0TWlzc2luZ0RhdGE6IGNsb3Vkd2F0Y2guVHJlYXRNaXNzaW5nRGF0YS5OT1RfQlJFQUNISU5HLFxyXG4gICAgICB9KTtcclxuICAgICAgaGlnaFJlYWRDYXBhY2l0eS5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuXHJcbiAgICAgIC8vIEhpZ2ggd3JpdGUgY2FwYWNpdHkgYWxhcm1cclxuICAgICAgY29uc3QgaGlnaFdyaXRlQ2FwYWNpdHkgPSBuZXcgY2xvdWR3YXRjaC5BbGFybSh0aGlzLCBgRHluYW1vRGJIaWdoV3JpdGUke2luZGV4fWAsIHtcclxuICAgICAgICBtZXRyaWM6IG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICBuYW1lc3BhY2U6ICdBV1MvRHluYW1vREInLFxyXG4gICAgICAgICAgbWV0cmljTmFtZTogJ0NvbnN1bWVkV3JpdGVDYXBhY2l0eVVuaXRzJyxcclxuICAgICAgICAgIGRpbWVuc2lvbnNNYXA6IHtcclxuICAgICAgICAgICAgVGFibGVOYW1lOiB0YWJsZU5hbWUsXHJcbiAgICAgICAgICB9LFxyXG4gICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgdGhyZXNob2xkOiA4MCwgLy8gODAlIG9mIHByb3Zpc2lvbmVkIGNhcGFjaXR5IChhZGp1c3QgYmFzZWQgb24gYWN0dWFsIHByb3Zpc2lvbmluZylcclxuICAgICAgICBldmFsdWF0aW9uUGVyaW9kczogMixcclxuICAgICAgICBjb21wYXJpc29uT3BlcmF0b3I6IGNsb3Vkd2F0Y2guQ29tcGFyaXNvbk9wZXJhdG9yLkdSRUFURVJfVEhBTl9USFJFU0hPTEQsXHJcbiAgICAgICAgYWxhcm1EZXNjcmlwdGlvbjogYER5bmFtb0RCIHRhYmxlICR7dGFibGVOYW1lfSB3cml0ZSBjYXBhY2l0eSBpcyBoaWdoYCxcclxuICAgICAgICBhbGFybU5hbWU6IGBSRFMtRHluYW1vREItSGlnaFdyaXRlLSR7dGFibGVOYW1lfWAsXHJcbiAgICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICAgIH0pO1xyXG4gICAgICBoaWdoV3JpdGVDYXBhY2l0eS5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuICAgIH0pO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVEaXNjb3ZlcnlBbGFybXMoZGlzY292ZXJ5RnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIERpc2NvdmVyeSBGdW5jdGlvbiBFcnJvcnNcclxuICAgIGNvbnN0IGRpc2NvdmVyeUVycm9ycyA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdEaXNjb3ZlcnlFcnJvcnMnLCB7XHJcbiAgICAgIG1ldHJpYzogZGlzY292ZXJ5RnVuY3Rpb24ubWV0cmljRXJyb3JzKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgIHN0YXRpc3RpYzogJ1N1bScsXHJcbiAgICAgIH0pLFxyXG4gICAgICB0aHJlc2hvbGQ6IDEsXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAxLFxyXG4gICAgICBhbGFybURlc2NyaXB0aW9uOiAnRGlzY292ZXJ5IGZ1bmN0aW9uIGhhcyBlcnJvcnMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtRGlzY292ZXJ5LUVycm9ycycsXHJcbiAgICAgIHRyZWF0TWlzc2luZ0RhdGE6IGNsb3Vkd2F0Y2guVHJlYXRNaXNzaW5nRGF0YS5OT1RfQlJFQUNISU5HLFxyXG4gICAgfSk7XHJcbiAgICBkaXNjb3ZlcnlFcnJvcnMuYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgLy8gRGlzY292ZXJ5IEZ1bmN0aW9uIER1cmF0aW9uXHJcbiAgICBjb25zdCBkaXNjb3ZlcnlEdXJhdGlvbiA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdEaXNjb3ZlcnlEdXJhdGlvbicsIHtcclxuICAgICAgbWV0cmljOiBkaXNjb3ZlcnlGdW5jdGlvbi5tZXRyaWNEdXJhdGlvbih7XHJcbiAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24ubWludXRlcyg1KSxcclxuICAgICAgICBzdGF0aXN0aWM6ICdBdmVyYWdlJyxcclxuICAgICAgfSksXHJcbiAgICAgIHRocmVzaG9sZDogMTgwMDAwLCAvLyAzIG1pbnV0ZXNcclxuICAgICAgZXZhbHVhdGlvblBlcmlvZHM6IDIsXHJcbiAgICAgIGNvbXBhcmlzb25PcGVyYXRvcjogY2xvdWR3YXRjaC5Db21wYXJpc29uT3BlcmF0b3IuR1JFQVRFUl9USEFOX1RIUkVTSE9MRCxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ0Rpc2NvdmVyeSBmdW5jdGlvbiB0YWtpbmcgdG9vIGxvbmcnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtRGlzY292ZXJ5LUR1cmF0aW9uJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGRpc2NvdmVyeUR1cmF0aW9uLmFkZEFsYXJtQWN0aW9uKG5ldyBjbG91ZHdhdGNoX2FjdGlvbnMuU25zQWN0aW9uKHRoaXMuYWxhcm1Ub3BpYykpO1xyXG5cclxuICAgIC8vIERpc2NvdmVyeSBGdW5jdGlvbiBUaHJvdHRsZXNcclxuICAgIGNvbnN0IGRpc2NvdmVyeVRocm90dGxlcyA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdEaXNjb3ZlcnlUaHJvdHRsZXMnLCB7XHJcbiAgICAgIG1ldHJpYzogZGlzY292ZXJ5RnVuY3Rpb24ubWV0cmljVGhyb3R0bGVzKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgIHN0YXRpc3RpYzogJ1N1bScsXHJcbiAgICAgIH0pLFxyXG4gICAgICB0aHJlc2hvbGQ6IDEsXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAxLFxyXG4gICAgICBhbGFybURlc2NyaXB0aW9uOiAnRGlzY292ZXJ5IGZ1bmN0aW9uIGlzIGJlaW5nIHRocm90dGxlZCcsXHJcbiAgICAgIGFsYXJtTmFtZTogJ1JEUy1EaXNjb3ZlcnktVGhyb3R0bGVzJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGRpc2NvdmVyeVRocm90dGxlcy5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlSGVhbHRoTW9uaXRvckFsYXJtcyhoZWFsdGhNb25pdG9yRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIEhlYWx0aCBNb25pdG9yIEVycm9yc1xyXG4gICAgY29uc3QgaGVhbHRoRXJyb3JzID0gbmV3IGNsb3Vkd2F0Y2guQWxhcm0odGhpcywgJ0hlYWx0aE1vbml0b3JFcnJvcnMnLCB7XHJcbiAgICAgIG1ldHJpYzogaGVhbHRoTW9uaXRvckZ1bmN0aW9uLm1ldHJpY0Vycm9ycyh7XHJcbiAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24ubWludXRlcyg1KSxcclxuICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICB9KSxcclxuICAgICAgdGhyZXNob2xkOiAzLFxyXG4gICAgICBldmFsdWF0aW9uUGVyaW9kczogMixcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ0hlYWx0aCBtb25pdG9yIGhhcyBtdWx0aXBsZSBlcnJvcnMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtSGVhbHRoTW9uaXRvci1FcnJvcnMnLFxyXG4gICAgICB0cmVhdE1pc3NpbmdEYXRhOiBjbG91ZHdhdGNoLlRyZWF0TWlzc2luZ0RhdGEuTk9UX0JSRUFDSElORyxcclxuICAgIH0pO1xyXG4gICAgaGVhbHRoRXJyb3JzLmFkZEFsYXJtQWN0aW9uKG5ldyBjbG91ZHdhdGNoX2FjdGlvbnMuU25zQWN0aW9uKHRoaXMuYWxhcm1Ub3BpYykpO1xyXG5cclxuICAgIC8vIENhY2hlIEhpdCBSYXRlIChDdXN0b20gTWV0cmljKVxyXG4gICAgY29uc3QgY2FjaGVIaXRSYXRlID0gbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICBtZXRyaWNOYW1lOiAnQ2FjaGVIaXRSYXRlJyxcclxuICAgICAgc3RhdGlzdGljOiAnQXZlcmFnZScsXHJcbiAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoMTUpLFxyXG4gICAgfSk7XHJcblxyXG4gICAgY29uc3QgbG93Q2FjaGVIaXRSYXRlID0gbmV3IGNsb3Vkd2F0Y2guQWxhcm0odGhpcywgJ0xvd0NhY2hlSGl0UmF0ZScsIHtcclxuICAgICAgbWV0cmljOiBjYWNoZUhpdFJhdGUsXHJcbiAgICAgIHRocmVzaG9sZDogNTAsXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAzLFxyXG4gICAgICBjb21wYXJpc29uT3BlcmF0b3I6IGNsb3Vkd2F0Y2guQ29tcGFyaXNvbk9wZXJhdG9yLkxFU1NfVEhBTl9USFJFU0hPTEQsXHJcbiAgICAgIGFsYXJtRGVzY3JpcHRpb246ICdDYWNoZSBoaXQgcmF0ZSBpcyBiZWxvdyA1MCUnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtTG93Q2FjaGVIaXRSYXRlJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGxvd0NhY2hlSGl0UmF0ZS5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQ29zdEFuYWx5emVyQWxhcm1zKGNvc3RBbmFseXplckZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyBDb3N0IEFuYWx5emVyIEVycm9yc1xyXG4gICAgY29uc3QgY29zdEVycm9ycyA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdDb3N0QW5hbHl6ZXJFcnJvcnMnLCB7XHJcbiAgICAgIG1ldHJpYzogY29zdEFuYWx5emVyRnVuY3Rpb24ubWV0cmljRXJyb3JzKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5ob3VycygxKSxcclxuICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICB9KSxcclxuICAgICAgdGhyZXNob2xkOiAxLFxyXG4gICAgICBldmFsdWF0aW9uUGVyaW9kczogMSxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ0Nvc3QgYW5hbHl6ZXIgaGFzIGVycm9ycycsXHJcbiAgICAgIGFsYXJtTmFtZTogJ1JEUy1Db3N0QW5hbHl6ZXItRXJyb3JzJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGNvc3RFcnJvcnMuYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgLy8gVG90YWwgTW9udGhseSBDb3N0IChDdXN0b20gTWV0cmljKVxyXG4gICAgY29uc3QgdG90YWxDb3N0ID0gbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICBtZXRyaWNOYW1lOiAnVG90YWxNb250aGx5Q29zdCcsXHJcbiAgICAgIHN0YXRpc3RpYzogJ01heGltdW0nLFxyXG4gICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5kYXlzKDEpLFxyXG4gICAgfSk7XHJcblxyXG4gICAgY29uc3QgaGlnaENvc3QgPSBuZXcgY2xvdWR3YXRjaC5BbGFybSh0aGlzLCAnSGlnaE1vbnRobHlDb3N0Jywge1xyXG4gICAgICBtZXRyaWM6IHRvdGFsQ29zdCxcclxuICAgICAgdGhyZXNob2xkOiA1MDAwLCAvLyAkNTAwMC9tb250aFxyXG4gICAgICBldmFsdWF0aW9uUGVyaW9kczogMSxcclxuICAgICAgY29tcGFyaXNvbk9wZXJhdG9yOiBjbG91ZHdhdGNoLkNvbXBhcmlzb25PcGVyYXRvci5HUkVBVEVSX1RIQU5fVEhSRVNIT0xELFxyXG4gICAgICBhbGFybURlc2NyaXB0aW9uOiAnTW9udGhseSBSRFMgY29zdCBleGNlZWRzICQ1MDAwJyxcclxuICAgICAgYWxhcm1OYW1lOiAnUkRTLUhpZ2hNb250aGx5Q29zdCcsXHJcbiAgICAgIHRyZWF0TWlzc2luZ0RhdGE6IGNsb3Vkd2F0Y2guVHJlYXRNaXNzaW5nRGF0YS5OT1RfQlJFQUNISU5HLFxyXG4gICAgfSk7XHJcbiAgICBoaWdoQ29zdC5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQ29tcGxpYW5jZUFsYXJtcyhjb21wbGlhbmNlRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIENvbXBsaWFuY2UgQ2hlY2tlciBFcnJvcnNcclxuICAgIGNvbnN0IGNvbXBsaWFuY2VFcnJvcnMgPSBuZXcgY2xvdWR3YXRjaC5BbGFybSh0aGlzLCAnQ29tcGxpYW5jZUVycm9ycycsIHtcclxuICAgICAgbWV0cmljOiBjb21wbGlhbmNlRnVuY3Rpb24ubWV0cmljRXJyb3JzKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5ob3VycygxKSxcclxuICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICB9KSxcclxuICAgICAgdGhyZXNob2xkOiAxLFxyXG4gICAgICBldmFsdWF0aW9uUGVyaW9kczogMSxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ0NvbXBsaWFuY2UgY2hlY2tlciBoYXMgZXJyb3JzJyxcclxuICAgICAgYWxhcm1OYW1lOiAnUkRTLUNvbXBsaWFuY2UtRXJyb3JzJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGNvbXBsaWFuY2VFcnJvcnMuYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgLy8gQ3JpdGljYWwgVmlvbGF0aW9ucyAoQ3VzdG9tIE1ldHJpYylcclxuICAgIGNvbnN0IGNyaXRpY2FsVmlvbGF0aW9ucyA9IG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgIG5hbWVzcGFjZTogJ1JEUy9PcGVyYXRpb25zJyxcclxuICAgICAgbWV0cmljTmFtZTogJ0NyaXRpY2FsVmlvbGF0aW9ucycsXHJcbiAgICAgIHN0YXRpc3RpYzogJ01heGltdW0nLFxyXG4gICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5ob3VycygxKSxcclxuICAgIH0pO1xyXG5cclxuICAgIGNvbnN0IGhpZ2hWaW9sYXRpb25zID0gbmV3IGNsb3Vkd2F0Y2guQWxhcm0odGhpcywgJ0hpZ2hDcml0aWNhbFZpb2xhdGlvbnMnLCB7XHJcbiAgICAgIG1ldHJpYzogY3JpdGljYWxWaW9sYXRpb25zLFxyXG4gICAgICB0aHJlc2hvbGQ6IDUsXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAxLFxyXG4gICAgICBjb21wYXJpc29uT3BlcmF0b3I6IGNsb3Vkd2F0Y2guQ29tcGFyaXNvbk9wZXJhdG9yLkdSRUFURVJfVEhBTl9USFJFU0hPTEQsXHJcbiAgICAgIGFsYXJtRGVzY3JpcHRpb246ICdNb3JlIHRoYW4gNSBjcml0aWNhbCBjb21wbGlhbmNlIHZpb2xhdGlvbnMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtSGlnaENyaXRpY2FsVmlvbGF0aW9ucycsXHJcbiAgICAgIHRyZWF0TWlzc2luZ0RhdGE6IGNsb3Vkd2F0Y2guVHJlYXRNaXNzaW5nRGF0YS5OT1RfQlJFQUNISU5HLFxyXG4gICAgfSk7XHJcbiAgICBoaWdoVmlvbGF0aW9ucy5hZGRBbGFybUFjdGlvbihuZXcgY2xvdWR3YXRjaF9hY3Rpb25zLlNuc0FjdGlvbih0aGlzLmFsYXJtVG9waWMpKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlT3BlcmF0aW9uc0FsYXJtcyhvcGVyYXRpb25zRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIE9wZXJhdGlvbnMgRnVuY3Rpb24gRXJyb3JzXHJcbiAgICBjb25zdCBvcHNFcnJvcnMgPSBuZXcgY2xvdWR3YXRjaC5BbGFybSh0aGlzLCAnT3BlcmF0aW9uc0Vycm9ycycsIHtcclxuICAgICAgbWV0cmljOiBvcGVyYXRpb25zRnVuY3Rpb24ubWV0cmljRXJyb3JzKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgIHN0YXRpc3RpYzogJ1N1bScsXHJcbiAgICAgIH0pLFxyXG4gICAgICB0aHJlc2hvbGQ6IDMsXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAxLFxyXG4gICAgICBhbGFybURlc2NyaXB0aW9uOiAnT3BlcmF0aW9ucyBzZXJ2aWNlIGhhcyBtdWx0aXBsZSBlcnJvcnMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtT3BlcmF0aW9ucy1FcnJvcnMnLFxyXG4gICAgICB0cmVhdE1pc3NpbmdEYXRhOiBjbG91ZHdhdGNoLlRyZWF0TWlzc2luZ0RhdGEuTk9UX0JSRUFDSElORyxcclxuICAgIH0pO1xyXG4gICAgb3BzRXJyb3JzLmFkZEFsYXJtQWN0aW9uKG5ldyBjbG91ZHdhdGNoX2FjdGlvbnMuU25zQWN0aW9uKHRoaXMuYWxhcm1Ub3BpYykpO1xyXG5cclxuICAgIC8vIEVycm9yIFJhdGUgQWxhcm0gKFJFUS01LjU6IGVycm9yIHJhdGUgPiA1JSBmb3IgNSBtaW51dGVzKVxyXG4gICAgY29uc3QgZXJyb3JSYXRlID0gbmV3IGNsb3Vkd2F0Y2guTWF0aEV4cHJlc3Npb24oe1xyXG4gICAgICBleHByZXNzaW9uOiAnKGVycm9ycyAvIGludm9jYXRpb25zKSAqIDEwMCcsXHJcbiAgICAgIHVzaW5nTWV0cmljczoge1xyXG4gICAgICAgIGVycm9yczogb3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0Vycm9ycyh7XHJcbiAgICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICB9KSxcclxuICAgICAgICBpbnZvY2F0aW9uczogb3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0ludm9jYXRpb25zKHtcclxuICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICAgIH0pLFxyXG4gICAgICB9LFxyXG4gICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgfSk7XHJcblxyXG4gICAgY29uc3QgaGlnaEVycm9yUmF0ZSA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdIaWdoT3BlcmF0aW9uc0Vycm9yUmF0ZScsIHtcclxuICAgICAgbWV0cmljOiBlcnJvclJhdGUsXHJcbiAgICAgIHRocmVzaG9sZDogNSxcclxuICAgICAgZXZhbHVhdGlvblBlcmlvZHM6IDEsXHJcbiAgICAgIGNvbXBhcmlzb25PcGVyYXRvcjogY2xvdWR3YXRjaC5Db21wYXJpc29uT3BlcmF0b3IuR1JFQVRFUl9USEFOX1RIUkVTSE9MRCxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ09wZXJhdGlvbnMgZXJyb3IgcmF0ZSBleGNlZWRzIDUlIGZvciA1IG1pbnV0ZXMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtT3BlcmF0aW9ucy1IaWdoRXJyb3JSYXRlJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGhpZ2hFcnJvclJhdGUuYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgLy8gUDk5IExhdGVuY3kgQWxhcm0gKFJFUS01LjU6IFA5OSBsYXRlbmN5ID4gMyBzZWNvbmRzKVxyXG4gICAgY29uc3QgcDk5TGF0ZW5jeSA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdIaWdoT3BlcmF0aW9uc1A5OUxhdGVuY3knLCB7XHJcbiAgICAgIG1ldHJpYzogb3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0R1cmF0aW9uKHtcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgIHN0YXRpc3RpYzogJ3A5OScsXHJcbiAgICAgIH0pLFxyXG4gICAgICB0aHJlc2hvbGQ6IDMwMDAsIC8vIDMgc2Vjb25kcyBpbiBtaWxsaXNlY29uZHNcclxuICAgICAgZXZhbHVhdGlvblBlcmlvZHM6IDIsXHJcbiAgICAgIGNvbXBhcmlzb25PcGVyYXRvcjogY2xvdWR3YXRjaC5Db21wYXJpc29uT3BlcmF0b3IuR1JFQVRFUl9USEFOX1RIUkVTSE9MRCxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ09wZXJhdGlvbnMgUDk5IGxhdGVuY3kgZXhjZWVkcyAzIHNlY29uZHMnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtT3BlcmF0aW9ucy1IaWdoUDk5TGF0ZW5jeScsXHJcbiAgICAgIHRyZWF0TWlzc2luZ0RhdGE6IGNsb3Vkd2F0Y2guVHJlYXRNaXNzaW5nRGF0YS5OT1RfQlJFQUNISU5HLFxyXG4gICAgfSk7XHJcbiAgICBwOTlMYXRlbmN5LmFkZEFsYXJtQWN0aW9uKG5ldyBjbG91ZHdhdGNoX2FjdGlvbnMuU25zQWN0aW9uKHRoaXMuYWxhcm1Ub3BpYykpO1xyXG5cclxuICAgIC8vIENvbmN1cnJlbnQgRXhlY3V0aW9ucyBBbGFybSAoUkVRLTUuNTogPiA4MCUgb2YgcmVzZXJ2ZWQgY29uY3VycmVudCBleGVjdXRpb25zKVxyXG4gICAgY29uc3QgY29uY3VycmVudEV4ZWN1dGlvbnMgPSBuZXcgY2xvdWR3YXRjaC5BbGFybSh0aGlzLCAnSGlnaENvbmN1cnJlbnRFeGVjdXRpb25zJywge1xyXG4gICAgICBtZXRyaWM6IG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0xhbWJkYScsXHJcbiAgICAgICAgbWV0cmljTmFtZTogJ0NvbmN1cnJlbnRFeGVjdXRpb25zJyxcclxuICAgICAgICBkaW1lbnNpb25zTWFwOiB7XHJcbiAgICAgICAgICBGdW5jdGlvbk5hbWU6IG9wZXJhdGlvbnNGdW5jdGlvbi5mdW5jdGlvbk5hbWUsXHJcbiAgICAgICAgfSxcclxuICAgICAgICBzdGF0aXN0aWM6ICdNYXhpbXVtJyxcclxuICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICB9KSxcclxuICAgICAgdGhyZXNob2xkOiA4MDAsIC8vIDgwJSBvZiAxMDAwIChkZWZhdWx0IGFjY291bnQgbGltaXQpXHJcbiAgICAgIGV2YWx1YXRpb25QZXJpb2RzOiAyLFxyXG4gICAgICBjb21wYXJpc29uT3BlcmF0b3I6IGNsb3Vkd2F0Y2guQ29tcGFyaXNvbk9wZXJhdG9yLkdSRUFURVJfVEhBTl9USFJFU0hPTEQsXHJcbiAgICAgIGFsYXJtRGVzY3JpcHRpb246ICdMYW1iZGEgY29uY3VycmVudCBleGVjdXRpb25zIGV4Y2VlZCA4MCUgb2YgbGltaXQnLFxyXG4gICAgICBhbGFybU5hbWU6ICdSRFMtT3BlcmF0aW9ucy1IaWdoQ29uY3VycmVuY3knLFxyXG4gICAgICB0cmVhdE1pc3NpbmdEYXRhOiBjbG91ZHdhdGNoLlRyZWF0TWlzc2luZ0RhdGEuTk9UX0JSRUFDSElORyxcclxuICAgIH0pO1xyXG4gICAgY29uY3VycmVudEV4ZWN1dGlvbnMuYWRkQWxhcm1BY3Rpb24obmV3IGNsb3Vkd2F0Y2hfYWN0aW9ucy5TbnNBY3Rpb24odGhpcy5hbGFybVRvcGljKSk7XHJcblxyXG4gICAgLy8gT3BlcmF0aW9uIFN1Y2Nlc3MgUmF0ZSAoQ3VzdG9tIE1ldHJpYylcclxuICAgIGNvbnN0IHN1Y2Nlc3NSYXRlID0gbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICBtZXRyaWNOYW1lOiAnT3BlcmF0aW9uU3VjY2Vzc1JhdGUnLFxyXG4gICAgICBzdGF0aXN0aWM6ICdBdmVyYWdlJyxcclxuICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24uaG91cnMoMSksXHJcbiAgICB9KTtcclxuXHJcbiAgICBjb25zdCBsb3dTdWNjZXNzUmF0ZSA9IG5ldyBjbG91ZHdhdGNoLkFsYXJtKHRoaXMsICdMb3dPcGVyYXRpb25TdWNjZXNzUmF0ZScsIHtcclxuICAgICAgbWV0cmljOiBzdWNjZXNzUmF0ZSxcclxuICAgICAgdGhyZXNob2xkOiA5MCxcclxuICAgICAgZXZhbHVhdGlvblBlcmlvZHM6IDIsXHJcbiAgICAgIGNvbXBhcmlzb25PcGVyYXRvcjogY2xvdWR3YXRjaC5Db21wYXJpc29uT3BlcmF0b3IuTEVTU19USEFOX1RIUkVTSE9MRCxcclxuICAgICAgYWxhcm1EZXNjcmlwdGlvbjogJ09wZXJhdGlvbiBzdWNjZXNzIHJhdGUgYmVsb3cgOTAlJyxcclxuICAgICAgYWxhcm1OYW1lOiAnUkRTLUxvd09wZXJhdGlvblN1Y2Nlc3NSYXRlJyxcclxuICAgICAgdHJlYXRNaXNzaW5nRGF0YTogY2xvdWR3YXRjaC5UcmVhdE1pc3NpbmdEYXRhLk5PVF9CUkVBQ0hJTkcsXHJcbiAgICB9KTtcclxuICAgIGxvd1N1Y2Nlc3NSYXRlLmFkZEFsYXJtQWN0aW9uKG5ldyBjbG91ZHdhdGNoX2FjdGlvbnMuU25zQWN0aW9uKHRoaXMuYWxhcm1Ub3BpYykpO1xyXG4gIH1cclxuXHJcblxyXG4gIHByaXZhdGUgY3JlYXRlRGFzaGJvYXJkV2lkZ2V0cyhwcm9wczogTW9uaXRvcmluZ1N0YWNrUHJvcHMpOiB2b2lkIHtcclxuICAgIC8vIFJvdyAxOiBTeXN0ZW0gT3ZlcnZpZXdcclxuICAgIHRoaXMuZGFzaGJvYXJkLmFkZFdpZGdldHMoXHJcbiAgICAgIG5ldyBjbG91ZHdhdGNoLlRleHRXaWRnZXQoe1xyXG4gICAgICAgIG1hcmtkb3duOiAnIyBSRFMgT3BlcmF0aW9ucyBEYXNoYm9hcmRcXG4jIyBTeXN0ZW0gSGVhbHRoIGFuZCBQZXJmb3JtYW5jZSBNZXRyaWNzJyxcclxuICAgICAgICB3aWR0aDogMjQsXHJcbiAgICAgICAgaGVpZ2h0OiAyLFxyXG4gICAgICB9KVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBSb3cgMjogTGFtYmRhIEZ1bmN0aW9uIE1ldHJpY3NcclxuICAgIHRoaXMuZGFzaGJvYXJkLmFkZFdpZGdldHMoXHJcbiAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICB0aXRsZTogJ0xhbWJkYSBJbnZvY2F0aW9ucycsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgcHJvcHMuZGlzY292ZXJ5RnVuY3Rpb24ubWV0cmljSW52b2NhdGlvbnMoeyBsYWJlbDogJ0Rpc2NvdmVyeScsIHN0YXRpc3RpYzogJ1N1bScgfSksXHJcbiAgICAgICAgICBwcm9wcy5oZWFsdGhNb25pdG9yRnVuY3Rpb24ubWV0cmljSW52b2NhdGlvbnMoeyBsYWJlbDogJ0hlYWx0aCBNb25pdG9yJywgc3RhdGlzdGljOiAnU3VtJyB9KSxcclxuICAgICAgICAgIHByb3BzLmNvc3RBbmFseXplckZ1bmN0aW9uLm1ldHJpY0ludm9jYXRpb25zKHsgbGFiZWw6ICdDb3N0IEFuYWx5emVyJywgc3RhdGlzdGljOiAnU3VtJyB9KSxcclxuICAgICAgICAgIHByb3BzLmNvbXBsaWFuY2VDaGVja2VyRnVuY3Rpb24ubWV0cmljSW52b2NhdGlvbnMoeyBsYWJlbDogJ0NvbXBsaWFuY2UnLCBzdGF0aXN0aWM6ICdTdW0nIH0pLFxyXG4gICAgICAgICAgcHJvcHMub3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0ludm9jYXRpb25zKHsgbGFiZWw6ICdPcGVyYXRpb25zJywgc3RhdGlzdGljOiAnU3VtJyB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHdpZHRoOiAxMixcclxuICAgICAgICBoZWlnaHQ6IDYsXHJcbiAgICAgIH0pLFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdMYW1iZGEgRXJyb3JzJyxcclxuICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICBwcm9wcy5kaXNjb3ZlcnlGdW5jdGlvbi5tZXRyaWNFcnJvcnMoeyBsYWJlbDogJ0Rpc2NvdmVyeScsIHN0YXRpc3RpYzogJ1N1bScsIGNvbG9yOiAnI2Q2MjcyOCcgfSksXHJcbiAgICAgICAgICBwcm9wcy5oZWFsdGhNb25pdG9yRnVuY3Rpb24ubWV0cmljRXJyb3JzKHsgbGFiZWw6ICdIZWFsdGggTW9uaXRvcicsIHN0YXRpc3RpYzogJ1N1bScsIGNvbG9yOiAnI2ZmN2YwZScgfSksXHJcbiAgICAgICAgICBwcm9wcy5jb3N0QW5hbHl6ZXJGdW5jdGlvbi5tZXRyaWNFcnJvcnMoeyBsYWJlbDogJ0Nvc3QgQW5hbHl6ZXInLCBzdGF0aXN0aWM6ICdTdW0nLCBjb2xvcjogJyMyY2EwMmMnIH0pLFxyXG4gICAgICAgICAgcHJvcHMuY29tcGxpYW5jZUNoZWNrZXJGdW5jdGlvbi5tZXRyaWNFcnJvcnMoeyBsYWJlbDogJ0NvbXBsaWFuY2UnLCBzdGF0aXN0aWM6ICdTdW0nLCBjb2xvcjogJyM5NDY3YmQnIH0pLFxyXG4gICAgICAgICAgcHJvcHMub3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0Vycm9ycyh7IGxhYmVsOiAnT3BlcmF0aW9ucycsIHN0YXRpc3RpYzogJ1N1bScsIGNvbG9yOiAnIzhjNTY0YicgfSksXHJcbiAgICAgICAgXSxcclxuICAgICAgICB3aWR0aDogMTIsXHJcbiAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICB9KVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBSb3cgMzogTGFtYmRhIER1cmF0aW9uIGFuZCBUaHJvdHRsZXNcclxuICAgIHRoaXMuZGFzaGJvYXJkLmFkZFdpZGdldHMoXHJcbiAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICB0aXRsZTogJ0xhbWJkYSBEdXJhdGlvbiAobXMpJyxcclxuICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICBwcm9wcy5kaXNjb3ZlcnlGdW5jdGlvbi5tZXRyaWNEdXJhdGlvbih7IGxhYmVsOiAnRGlzY292ZXJ5Jywgc3RhdGlzdGljOiAnQXZlcmFnZScgfSksXHJcbiAgICAgICAgICBwcm9wcy5oZWFsdGhNb25pdG9yRnVuY3Rpb24ubWV0cmljRHVyYXRpb24oeyBsYWJlbDogJ0hlYWx0aCBNb25pdG9yJywgc3RhdGlzdGljOiAnQXZlcmFnZScgfSksXHJcbiAgICAgICAgICBwcm9wcy5jb3N0QW5hbHl6ZXJGdW5jdGlvbi5tZXRyaWNEdXJhdGlvbih7IGxhYmVsOiAnQ29zdCBBbmFseXplcicsIHN0YXRpc3RpYzogJ0F2ZXJhZ2UnIH0pLFxyXG4gICAgICAgICAgcHJvcHMuY29tcGxpYW5jZUNoZWNrZXJGdW5jdGlvbi5tZXRyaWNEdXJhdGlvbih7IGxhYmVsOiAnQ29tcGxpYW5jZScsIHN0YXRpc3RpYzogJ0F2ZXJhZ2UnIH0pLFxyXG4gICAgICAgICAgcHJvcHMub3BlcmF0aW9uc0Z1bmN0aW9uLm1ldHJpY0R1cmF0aW9uKHsgbGFiZWw6ICdPcGVyYXRpb25zJywgc3RhdGlzdGljOiAnQXZlcmFnZScgfSksXHJcbiAgICAgICAgXSxcclxuICAgICAgICB3aWR0aDogMTIsXHJcbiAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICB9KSxcclxuICAgICAgbmV3IGNsb3Vkd2F0Y2guR3JhcGhXaWRnZXQoe1xyXG4gICAgICAgIHRpdGxlOiAnTGFtYmRhIFRocm90dGxlcycsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgcHJvcHMuZGlzY292ZXJ5RnVuY3Rpb24ubWV0cmljVGhyb3R0bGVzKHsgbGFiZWw6ICdEaXNjb3ZlcnknLCBzdGF0aXN0aWM6ICdTdW0nIH0pLFxyXG4gICAgICAgICAgcHJvcHMuaGVhbHRoTW9uaXRvckZ1bmN0aW9uLm1ldHJpY1Rocm90dGxlcyh7IGxhYmVsOiAnSGVhbHRoIE1vbml0b3InLCBzdGF0aXN0aWM6ICdTdW0nIH0pLFxyXG4gICAgICAgICAgcHJvcHMuY29zdEFuYWx5emVyRnVuY3Rpb24ubWV0cmljVGhyb3R0bGVzKHsgbGFiZWw6ICdDb3N0IEFuYWx5emVyJywgc3RhdGlzdGljOiAnU3VtJyB9KSxcclxuICAgICAgICAgIHByb3BzLmNvbXBsaWFuY2VDaGVja2VyRnVuY3Rpb24ubWV0cmljVGhyb3R0bGVzKHsgbGFiZWw6ICdDb21wbGlhbmNlJywgc3RhdGlzdGljOiAnU3VtJyB9KSxcclxuICAgICAgICAgIHByb3BzLm9wZXJhdGlvbnNGdW5jdGlvbi5tZXRyaWNUaHJvdHRsZXMoeyBsYWJlbDogJ09wZXJhdGlvbnMnLCBzdGF0aXN0aWM6ICdTdW0nIH0pLFxyXG4gICAgICAgIF0sXHJcbiAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgIGhlaWdodDogNixcclxuICAgICAgfSlcclxuICAgICk7XHJcblxyXG4gICAgLy8gUm93IDQ6IEN1c3RvbSBCdXNpbmVzcyBNZXRyaWNzXHJcbiAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5TaW5nbGVWYWx1ZVdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdUb3RhbCBSRFMgSW5zdGFuY2VzJyxcclxuICAgICAgICBtZXRyaWNzOiBbXHJcbiAgICAgICAgICBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgICBuYW1lc3BhY2U6ICdSRFMvT3BlcmF0aW9ucycsXHJcbiAgICAgICAgICAgIG1ldHJpY05hbWU6ICdUb3RhbEluc3RhbmNlcycsXHJcbiAgICAgICAgICAgIHN0YXRpc3RpYzogJ01heGltdW0nLFxyXG4gICAgICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgXSxcclxuICAgICAgICB3aWR0aDogNixcclxuICAgICAgICBoZWlnaHQ6IDQsXHJcbiAgICAgIH0pLFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5TaW5nbGVWYWx1ZVdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdDcml0aWNhbCBBbGVydHMnLFxyXG4gICAgICAgIG1ldHJpY3M6IFtcclxuICAgICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICAgIG5hbWVzcGFjZTogJ1JEUy9PcGVyYXRpb25zJyxcclxuICAgICAgICAgICAgbWV0cmljTmFtZTogJ0NyaXRpY2FsQWxlcnRzJyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnTWF4aW11bScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHdpZHRoOiA2LFxyXG4gICAgICAgIGhlaWdodDogNCxcclxuICAgICAgfSksXHJcbiAgICAgIG5ldyBjbG91ZHdhdGNoLlNpbmdsZVZhbHVlV2lkZ2V0KHtcclxuICAgICAgICB0aXRsZTogJ0NhY2hlIEhpdCBSYXRlICglKScsXHJcbiAgICAgICAgbWV0cmljczogW1xyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnQ2FjaGVIaXRSYXRlJyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnQXZlcmFnZScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoMTUpLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgXSxcclxuICAgICAgICB3aWR0aDogNixcclxuICAgICAgICBoZWlnaHQ6IDQsXHJcbiAgICAgIH0pLFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5TaW5nbGVWYWx1ZVdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdNb250aGx5IENvc3QgKCQpJyxcclxuICAgICAgICBtZXRyaWNzOiBbXHJcbiAgICAgICAgICBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgICBuYW1lc3BhY2U6ICdSRFMvT3BlcmF0aW9ucycsXHJcbiAgICAgICAgICAgIG1ldHJpY05hbWU6ICdUb3RhbE1vbnRobHlDb3N0JyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnTWF4aW11bScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLmRheXMoMSksXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHdpZHRoOiA2LFxyXG4gICAgICAgIGhlaWdodDogNCxcclxuICAgICAgfSlcclxuICAgICk7XHJcblxyXG4gICAgLy8gUm93IDU6IE9wZXJhdGlvbnMgTWV0cmljc1xyXG4gICAgdGhpcy5kYXNoYm9hcmQuYWRkV2lkZ2V0cyhcclxuICAgICAgbmV3IGNsb3Vkd2F0Y2guR3JhcGhXaWRnZXQoe1xyXG4gICAgICAgIHRpdGxlOiAnT3BlcmF0aW9ucyBFeGVjdXRlZCcsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnT3BlcmF0aW9uc0V4ZWN1dGVkJyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24uaG91cnMoMSksXHJcbiAgICAgICAgICAgIGxhYmVsOiAnVG90YWwgT3BlcmF0aW9ucycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHdpZHRoOiAxMixcclxuICAgICAgICBoZWlnaHQ6IDYsXHJcbiAgICAgIH0pLFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdPcGVyYXRpb24gU3VjY2VzcyBSYXRlICglKScsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnT3BlcmF0aW9uU3VjY2Vzc1JhdGUnLFxyXG4gICAgICAgICAgICBzdGF0aXN0aWM6ICdBdmVyYWdlJyxcclxuICAgICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24uaG91cnMoMSksXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIGxlZnRZQXhpczoge1xyXG4gICAgICAgICAgbWluOiAwLFxyXG4gICAgICAgICAgbWF4OiAxMDAsXHJcbiAgICAgICAgfSxcclxuICAgICAgICB3aWR0aDogMTIsXHJcbiAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICB9KVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBSb3cgNjogQ29tcGxpYW5jZSBNZXRyaWNzXHJcbiAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdDb21wbGlhbmNlIFNjb3JlICglKScsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnQ29tcGxpYW5jZVNjb3JlJyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnQXZlcmFnZScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLmhvdXJzKDEpLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgXSxcclxuICAgICAgICBsZWZ0WUF4aXM6IHtcclxuICAgICAgICAgIG1pbjogMCxcclxuICAgICAgICAgIG1heDogMTAwLFxyXG4gICAgICAgIH0sXHJcbiAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgIGhlaWdodDogNixcclxuICAgICAgfSksXHJcbiAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICB0aXRsZTogJ0NvbXBsaWFuY2UgVmlvbGF0aW9ucyBieSBTZXZlcml0eScsXHJcbiAgICAgICAgbGVmdDogW1xyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnQ3JpdGljYWxWaW9sYXRpb25zJyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnTWF4aW11bScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLmhvdXJzKDEpLFxyXG4gICAgICAgICAgICBsYWJlbDogJ0NyaXRpY2FsJyxcclxuICAgICAgICAgICAgY29sb3I6ICcjZDYyNzI4JyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgbmFtZXNwYWNlOiAnUkRTL09wZXJhdGlvbnMnLFxyXG4gICAgICAgICAgICBtZXRyaWNOYW1lOiAnSGlnaFZpb2xhdGlvbnMnLFxyXG4gICAgICAgICAgICBzdGF0aXN0aWM6ICdNYXhpbXVtJyxcclxuICAgICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24uaG91cnMoMSksXHJcbiAgICAgICAgICAgIGxhYmVsOiAnSGlnaCcsXHJcbiAgICAgICAgICAgIGNvbG9yOiAnI2ZmN2YwZScsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICAgIG5hbWVzcGFjZTogJ1JEUy9PcGVyYXRpb25zJyxcclxuICAgICAgICAgICAgbWV0cmljTmFtZTogJ01lZGl1bVZpb2xhdGlvbnMnLFxyXG4gICAgICAgICAgICBzdGF0aXN0aWM6ICdNYXhpbXVtJyxcclxuICAgICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24uaG91cnMoMSksXHJcbiAgICAgICAgICAgIGxhYmVsOiAnTWVkaXVtJyxcclxuICAgICAgICAgICAgY29sb3I6ICcjZmZiYjc4JyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIF0sXHJcbiAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgIGhlaWdodDogNixcclxuICAgICAgfSlcclxuICAgICk7XHJcblxyXG4gICAgLy8gUm93IDc6IENvc3QgVHJlbmRzXHJcbiAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgdGl0bGU6ICdEYWlseSBDb3N0IFRyZW5kJyxcclxuICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgICBuYW1lc3BhY2U6ICdSRFMvT3BlcmF0aW9ucycsXHJcbiAgICAgICAgICAgIG1ldHJpY05hbWU6ICdUb3RhbE1vbnRobHlDb3N0JyxcclxuICAgICAgICAgICAgc3RhdGlzdGljOiAnTWF4aW11bScsXHJcbiAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLmRheXMoMSksXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHdpZHRoOiAyNCxcclxuICAgICAgICBoZWlnaHQ6IDYsXHJcbiAgICAgIH0pXHJcbiAgICApO1xyXG5cclxuICAgIC8vIFJvdyA4OiBBUEkgR2F0ZXdheSBNZXRyaWNzIChpZiBwcm92aWRlZClcclxuICAgIGlmIChwcm9wcy5hcGlHYXRld2F5TmFtZSkge1xyXG4gICAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLlRleHRXaWRnZXQoe1xyXG4gICAgICAgICAgbWFya2Rvd246ICcjIyBBUEkgR2F0ZXdheSBNZXRyaWNzJyxcclxuICAgICAgICAgIHdpZHRoOiAyNCxcclxuICAgICAgICAgIGhlaWdodDogMSxcclxuICAgICAgICB9KVxyXG4gICAgICApO1xyXG5cclxuICAgICAgdGhpcy5kYXNoYm9hcmQuYWRkV2lkZ2V0cyhcclxuICAgICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgICB0aXRsZTogJ0FQSSBHYXRld2F5IFJlcXVlc3RzJyxcclxuICAgICAgICAgIGxlZnQ6IFtcclxuICAgICAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgICAgICBuYW1lc3BhY2U6ICdBV1MvQXBpR2F0ZXdheScsXHJcbiAgICAgICAgICAgICAgbWV0cmljTmFtZTogJ0NvdW50JyxcclxuICAgICAgICAgICAgICBkaW1lbnNpb25zTWFwOiB7XHJcbiAgICAgICAgICAgICAgICBBcGlOYW1lOiBwcm9wcy5hcGlHYXRld2F5TmFtZSxcclxuICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgIHN0YXRpc3RpYzogJ1N1bScsXHJcbiAgICAgICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24ubWludXRlcyg1KSxcclxuICAgICAgICAgICAgICBsYWJlbDogJ1RvdGFsIFJlcXVlc3RzJyxcclxuICAgICAgICAgICAgfSksXHJcbiAgICAgICAgICBdLFxyXG4gICAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICAgIHRpdGxlOiAnQVBJIEdhdGV3YXkgTGF0ZW5jeScsXHJcbiAgICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0FwaUdhdGV3YXknLFxyXG4gICAgICAgICAgICAgIG1ldHJpY05hbWU6ICdMYXRlbmN5JyxcclxuICAgICAgICAgICAgICBkaW1lbnNpb25zTWFwOiB7XHJcbiAgICAgICAgICAgICAgICBBcGlOYW1lOiBwcm9wcy5hcGlHYXRld2F5TmFtZSxcclxuICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgIHN0YXRpc3RpYzogJ0F2ZXJhZ2UnLFxyXG4gICAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICAgICAgbGFiZWw6ICdBdmVyYWdlIExhdGVuY3knLFxyXG4gICAgICAgICAgICAgIGNvbG9yOiAnIzFmNzdiNCcsXHJcbiAgICAgICAgICAgIH0pLFxyXG4gICAgICAgICAgICBuZXcgY2xvdWR3YXRjaC5NZXRyaWMoe1xyXG4gICAgICAgICAgICAgIG5hbWVzcGFjZTogJ0FXUy9BcGlHYXRld2F5JyxcclxuICAgICAgICAgICAgICBtZXRyaWNOYW1lOiAnTGF0ZW5jeScsXHJcbiAgICAgICAgICAgICAgZGltZW5zaW9uc01hcDoge1xyXG4gICAgICAgICAgICAgICAgQXBpTmFtZTogcHJvcHMuYXBpR2F0ZXdheU5hbWUsXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICBzdGF0aXN0aWM6ICdwOTknLFxyXG4gICAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICAgICAgbGFiZWw6ICdQOTkgTGF0ZW5jeScsXHJcbiAgICAgICAgICAgICAgY29sb3I6ICcjZmY3ZjBlJyxcclxuICAgICAgICAgICAgfSksXHJcbiAgICAgICAgICBdLFxyXG4gICAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICAgIH0pXHJcbiAgICAgICk7XHJcblxyXG4gICAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICAgIHRpdGxlOiAnQVBJIEdhdGV3YXkgNFhYIEVycm9ycycsXHJcbiAgICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0FwaUdhdGV3YXknLFxyXG4gICAgICAgICAgICAgIG1ldHJpY05hbWU6ICc0WFhFcnJvcicsXHJcbiAgICAgICAgICAgICAgZGltZW5zaW9uc01hcDoge1xyXG4gICAgICAgICAgICAgICAgQXBpTmFtZTogcHJvcHMuYXBpR2F0ZXdheU5hbWUsXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICAgICAgY29sb3I6ICcjZmY3ZjBlJyxcclxuICAgICAgICAgICAgfSksXHJcbiAgICAgICAgICBdLFxyXG4gICAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLkdyYXBoV2lkZ2V0KHtcclxuICAgICAgICAgIHRpdGxlOiAnQVBJIEdhdGV3YXkgNVhYIEVycm9ycycsXHJcbiAgICAgICAgICBsZWZ0OiBbXHJcbiAgICAgICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICAgICAgbmFtZXNwYWNlOiAnQVdTL0FwaUdhdGV3YXknLFxyXG4gICAgICAgICAgICAgIG1ldHJpY05hbWU6ICc1WFhFcnJvcicsXHJcbiAgICAgICAgICAgICAgZGltZW5zaW9uc01hcDoge1xyXG4gICAgICAgICAgICAgICAgQXBpTmFtZTogcHJvcHMuYXBpR2F0ZXdheU5hbWUsXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICAgICAgY29sb3I6ICcjZDYyNzI4JyxcclxuICAgICAgICAgICAgfSksXHJcbiAgICAgICAgICBdLFxyXG4gICAgICAgICAgd2lkdGg6IDEyLFxyXG4gICAgICAgICAgaGVpZ2h0OiA2LFxyXG4gICAgICAgIH0pXHJcbiAgICAgICk7XHJcbiAgICB9XHJcblxyXG4gICAgLy8gUm93IDk6IER5bmFtb0RCIE1ldHJpY3MgKGlmIHByb3ZpZGVkKVxyXG4gICAgaWYgKHByb3BzLmR5bmFtb0RiVGFibGVOYW1lcyAmJiBwcm9wcy5keW5hbW9EYlRhYmxlTmFtZXMubGVuZ3RoID4gMCkge1xyXG4gICAgICB0aGlzLmRhc2hib2FyZC5hZGRXaWRnZXRzKFxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLlRleHRXaWRnZXQoe1xyXG4gICAgICAgICAgbWFya2Rvd246ICcjIyBEeW5hbW9EQiBNZXRyaWNzJyxcclxuICAgICAgICAgIHdpZHRoOiAyNCxcclxuICAgICAgICAgIGhlaWdodDogMSxcclxuICAgICAgICB9KVxyXG4gICAgICApO1xyXG5cclxuICAgICAgLy8gQ3JlYXRlIG1ldHJpY3MgZm9yIGVhY2ggdGFibGVcclxuICAgICAgY29uc3QgcmVhZENhcGFjaXR5TWV0cmljcyA9IHByb3BzLmR5bmFtb0RiVGFibGVOYW1lcy5tYXAodGFibGVOYW1lID0+XHJcbiAgICAgICAgbmV3IGNsb3Vkd2F0Y2guTWV0cmljKHtcclxuICAgICAgICAgIG5hbWVzcGFjZTogJ0FXUy9EeW5hbW9EQicsXHJcbiAgICAgICAgICBtZXRyaWNOYW1lOiAnQ29uc3VtZWRSZWFkQ2FwYWNpdHlVbml0cycsXHJcbiAgICAgICAgICBkaW1lbnNpb25zTWFwOiB7XHJcbiAgICAgICAgICAgIFRhYmxlTmFtZTogdGFibGVOYW1lLFxyXG4gICAgICAgICAgfSxcclxuICAgICAgICAgIHN0YXRpc3RpYzogJ1N1bScsXHJcbiAgICAgICAgICBwZXJpb2Q6IGNkay5EdXJhdGlvbi5taW51dGVzKDUpLFxyXG4gICAgICAgICAgbGFiZWw6IHRhYmxlTmFtZSxcclxuICAgICAgICB9KVxyXG4gICAgICApO1xyXG5cclxuICAgICAgY29uc3Qgd3JpdGVDYXBhY2l0eU1ldHJpY3MgPSBwcm9wcy5keW5hbW9EYlRhYmxlTmFtZXMubWFwKHRhYmxlTmFtZSA9PlxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICBuYW1lc3BhY2U6ICdBV1MvRHluYW1vREInLFxyXG4gICAgICAgICAgbWV0cmljTmFtZTogJ0NvbnN1bWVkV3JpdGVDYXBhY2l0eVVuaXRzJyxcclxuICAgICAgICAgIGRpbWVuc2lvbnNNYXA6IHtcclxuICAgICAgICAgICAgVGFibGVOYW1lOiB0YWJsZU5hbWUsXHJcbiAgICAgICAgICB9LFxyXG4gICAgICAgICAgc3RhdGlzdGljOiAnU3VtJyxcclxuICAgICAgICAgIHBlcmlvZDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgICAgICBsYWJlbDogdGFibGVOYW1lLFxyXG4gICAgICAgIH0pXHJcbiAgICAgICk7XHJcblxyXG4gICAgICBjb25zdCB0aHJvdHRsZU1ldHJpY3MgPSBwcm9wcy5keW5hbW9EYlRhYmxlTmFtZXMubWFwKHRhYmxlTmFtZSA9PlxyXG4gICAgICAgIG5ldyBjbG91ZHdhdGNoLk1ldHJpYyh7XHJcbiAgICAgICAgICBuYW1lc3BhY2U6ICdBV1MvRHluYW1vREInLFxyXG4gICAgICAgICAgbWV0cmljTmFtZTogJ1VzZXJFcnJvcnMnLFxyXG4gICAgICAgICAgZGltZW5zaW9uc01hcDoge1xyXG4gICAgICAgICAgICBUYWJsZU5hbWU6IHRhYmxlTmFtZSxcclxuICAgICAgICAgIH0sXHJcbiAgICAgICAgICBzdGF0aXN0aWM6ICdTdW0nLFxyXG4gICAgICAgICAgcGVyaW9kOiBjZGsuRHVyYXRpb24ubWludXRlcyg1KSxcclxuICAgICAgICAgIGxhYmVsOiB0YWJsZU5hbWUsXHJcbiAgICAgICAgfSlcclxuICAgICAgKTtcclxuXHJcbiAgICAgIHRoaXMuZGFzaGJvYXJkLmFkZFdpZGdldHMoXHJcbiAgICAgICAgbmV3IGNsb3Vkd2F0Y2guR3JhcGhXaWRnZXQoe1xyXG4gICAgICAgICAgdGl0bGU6ICdEeW5hbW9EQiBSZWFkIENhcGFjaXR5JyxcclxuICAgICAgICAgIGxlZnQ6IHJlYWRDYXBhY2l0eU1ldHJpY3MsXHJcbiAgICAgICAgICB3aWR0aDogMTIsXHJcbiAgICAgICAgICBoZWlnaHQ6IDYsXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgbmV3IGNsb3Vkd2F0Y2guR3JhcGhXaWRnZXQoe1xyXG4gICAgICAgICAgdGl0bGU6ICdEeW5hbW9EQiBXcml0ZSBDYXBhY2l0eScsXHJcbiAgICAgICAgICBsZWZ0OiB3cml0ZUNhcGFjaXR5TWV0cmljcyxcclxuICAgICAgICAgIHdpZHRoOiAxMixcclxuICAgICAgICAgIGhlaWdodDogNixcclxuICAgICAgICB9KVxyXG4gICAgICApO1xyXG5cclxuICAgICAgdGhpcy5kYXNoYm9hcmQuYWRkV2lkZ2V0cyhcclxuICAgICAgICBuZXcgY2xvdWR3YXRjaC5HcmFwaFdpZGdldCh7XHJcbiAgICAgICAgICB0aXRsZTogJ0R5bmFtb0RCIFRocm90dGxlcycsXHJcbiAgICAgICAgICBsZWZ0OiB0aHJvdHRsZU1ldHJpY3MsXHJcbiAgICAgICAgICB3aWR0aDogMjQsXHJcbiAgICAgICAgICBoZWlnaHQ6IDYsXHJcbiAgICAgICAgfSlcclxuICAgICAgKTtcclxuICAgIH1cclxuICB9XHJcbn1cclxuIl19