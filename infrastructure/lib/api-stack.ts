import * as cdk from 'aws-cdk-lib';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export interface ApiStackProps extends cdk.StackProps {
  queryHandlerFunction: lambda.IFunction;
  operationsFunction: lambda.IFunction;
  cloudOpsGeneratorFunction: lambda.IFunction;
  monitoringFunction: lambda.IFunction;
  approvalWorkflowFunction: lambda.IFunction;
  discoveryFunction: lambda.IFunction;
}

export class ApiStack extends cdk.Stack {
  public readonly api: apigateway.RestApi;
  public readonly apiKey: apigateway.IApiKey;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    // Create REST API
    this.api = new apigateway.RestApi(this, 'RdsOpsApi', {
      restApiName: 'RDS Operations Dashboard API',
      description: 'API for RDS Operations Dashboard',
      endpointTypes: [apigateway.EndpointType.REGIONAL],
      deployOptions: {
        stageName: 'prod',
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200,
        metricsEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
        ],
        allowCredentials: true,
      },
    });

    // Create API Key for authentication
    this.apiKey = this.api.addApiKey('ApiKey', {
      apiKeyName: 'rds-ops-dashboard-key',
      description: 'API Key for RDS Operations Dashboard',
    });

    // Create Usage Plan
    const usagePlan = this.api.addUsagePlan('UsagePlan', {
      name: 'RDS-Ops-Dashboard-Plan',
      description: 'Usage plan for RDS Operations Dashboard',
      throttle: {
        rateLimit: 100,
        burstLimit: 200,
      },
      quota: {
        limit: 10000,
        period: apigateway.Period.DAY,
      },
    });

    usagePlan.addApiKey(this.apiKey);
    usagePlan.addApiStage({
      stage: this.api.deploymentStage,
    });

    // Create resources and methods
    this.createInstancesEndpoints(props.queryHandlerFunction);
    this.createHealthEndpoints(props.queryHandlerFunction);
    this.createCostsEndpoints(props.queryHandlerFunction);
    this.createComplianceEndpoints(props.queryHandlerFunction);
    this.createOperationsEndpoints(props.operationsFunction, props.queryHandlerFunction);
    this.createCloudOpsEndpoints(props.cloudOpsGeneratorFunction, props.queryHandlerFunction);
    this.createMonitoringEndpoints(props.monitoringFunction);
    this.createApprovalEndpoints(props.approvalWorkflowFunction);
    this.createDiscoveryEndpoints(props.discoveryFunction);

    // Outputs
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: this.api.url,
      description: 'API Gateway URL',
    });

    new cdk.CfnOutput(this, 'ApiKeyId', {
      value: this.apiKey.keyId,
      description: 'API Key ID',
    });
  }

  private createInstancesEndpoints(queryHandler: lambda.IFunction): void {
    // /instances resource
    const instances = this.api.root.addResource('instances');

    // GET /instances - List all instances
    instances.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'list_instances',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.account': false,
          'method.request.querystring.region': false,
          'method.request.querystring.engine': false,
          'method.request.querystring.status': false,
          'method.request.querystring.environment': false,
          'method.request.querystring.limit': false,
          'method.request.querystring.offset': false,
        },
      }
    );

    // GET /instances/{instanceId} - Get instance details
    const instanceDetail = instances.addResource('{instanceId}');
    instanceDetail.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_instance',
            instanceId: '$input.params(\'instanceId\')',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.path.instanceId': true,
        },
      }
    );

    // GET /instances/{instanceId}/metrics - Get instance metrics
    const metrics = instanceDetail.addResource('metrics');
    metrics.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_metrics',
            instanceId: '$input.params(\'instanceId\')',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.path.instanceId': true,
          'method.request.querystring.period': false,
          'method.request.querystring.start': false,
          'method.request.querystring.end': false,
        },
      }
    );
  }

  private createHealthEndpoints(queryHandler: lambda.IFunction): void {
    // /health resource
    const health = this.api.root.addResource('health');

    // GET /health - Get health status for all instances
    health.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_health',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.severity': false,
          'method.request.querystring.limit': false,
        },
      }
    );

    // GET /health/{instanceId} - Get health for specific instance
    const instanceHealth = health.addResource('{instanceId}');
    instanceHealth.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_instance_health',
            instanceId: '$input.params(\'instanceId\')',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.path.instanceId': true,
        },
      }
    );

    // GET /health/alerts - Get active alerts
    const alerts = health.addResource('alerts');
    alerts.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_alerts',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.severity': false,
          'method.request.querystring.status': false,
          'method.request.querystring.limit': false,
        },
      }
    );
  }

  private createCostsEndpoints(queryHandler: lambda.IFunction): void {
    // /costs resource
    const costs = this.api.root.addResource('costs');

    // GET /costs - Get cost analysis
    costs.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_costs',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.groupBy': false,
          'method.request.querystring.period': false,
        },
      }
    );

    // GET /costs/trends - Get cost trends
    const trends = costs.addResource('trends');
    trends.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_cost_trends',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.days': false,
        },
      }
    );

    // GET /costs/recommendations - Get optimization recommendations
    const recommendations = costs.addResource('recommendations');
    recommendations.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_recommendations',
          }),
        },
      }),
      {
        apiKeyRequired: true,
      }
    );
  }

  private createComplianceEndpoints(queryHandler: lambda.IFunction): void {
    // /compliance resource
    const compliance = this.api.root.addResource('compliance');

    // GET /compliance - Get compliance status
    compliance.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_compliance',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.severity': false,
        },
      }
    );

    // GET /compliance/violations - Get compliance violations
    const violations = compliance.addResource('violations');
    violations.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_violations',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.severity': false,
          'method.request.querystring.limit': false,
        },
      }
    );
  }

  private createOperationsEndpoints(operationsFunction: lambda.IFunction, queryHandler: lambda.IFunction): void {
    // /operations resource
    const operations = this.api.root.addResource('operations');

    // POST /operations - Execute operation
    operations.addMethod(
      'POST',
      new apigateway.LambdaIntegration(operationsFunction, {
        proxy: true,
      }),
      {
        apiKeyRequired: true,
        requestValidator: new apigateway.RequestValidator(this, 'OperationsValidator', {
          restApi: this.api,
          validateRequestBody: true,
          validateRequestParameters: false,
        }),
        requestModels: {
          'application/json': new apigateway.Model(this, 'OperationsModel', {
            restApi: this.api,
            contentType: 'application/json',
            schema: {
              type: apigateway.JsonSchemaType.OBJECT,
              required: ['operation_type', 'instance_id'],
              properties: {
                operation_type: {
                  type: apigateway.JsonSchemaType.STRING,
                  enum: ['create_snapshot', 'reboot', 'modify_backup_window'],
                },
                instance_id: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                parameters: {
                  type: apigateway.JsonSchemaType.OBJECT,
                },
              },
            },
          }),
        },
      }
    );

    // GET /operations/history - Get operations history
    const history = operations.addResource('history');
    history.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_operations_history',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.instance_id': false,
          'method.request.querystring.operation': false,
          'method.request.querystring.limit': false,
        },
      }
    );
  }

  private createCloudOpsEndpoints(cloudOpsGenerator: lambda.IFunction, queryHandler: lambda.IFunction): void {
    // /cloudops resource
    const cloudops = this.api.root.addResource('cloudops');

    // POST /cloudops - Generate CloudOps request
    cloudops.addMethod(
      'POST',
      new apigateway.LambdaIntegration(cloudOpsGenerator, {
        proxy: true,
      }),
      {
        apiKeyRequired: true,
        requestValidator: new apigateway.RequestValidator(this, 'CloudOpsValidator', {
          restApi: this.api,
          validateRequestBody: true,
          validateRequestParameters: false,
        }),
        requestModels: {
          'application/json': new apigateway.Model(this, 'CloudOpsModel', {
            restApi: this.api,
            contentType: 'application/json',
            schema: {
              type: apigateway.JsonSchemaType.OBJECT,
              required: ['instance_id', 'request_type'],
              properties: {
                instance_id: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                request_type: {
                  type: apigateway.JsonSchemaType.STRING,
                  enum: ['scaling', 'parameter_change', 'maintenance'],
                },
                changes: {
                  type: apigateway.JsonSchemaType.OBJECT,
                },
                requested_by: {
                  type: apigateway.JsonSchemaType.STRING,
                },
              },
            },
          }),
        },
      }
    );

    // GET /cloudops/history - Get CloudOps request history
    const history = cloudops.addResource('history');
    history.addMethod(
      'GET',
      new apigateway.LambdaIntegration(queryHandler, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            action: 'get_cloudops_history',
            queryStringParameters: '$input.params().querystring',
          }),
        },
      }),
      {
        apiKeyRequired: true,
        requestParameters: {
          'method.request.querystring.instance_id': false,
          'method.request.querystring.limit': false,
        },
      }
    );
  }

  private createMonitoringEndpoints(monitoringFunction: lambda.IFunction): void {
    // /monitoring resource
    const monitoring = this.api.root.addResource('monitoring');

    // POST /monitoring - Fetch CloudWatch metrics
    monitoring.addMethod(
      'POST',
      new apigateway.LambdaIntegration(monitoringFunction, {
        proxy: true,
      }),
      {
        apiKeyRequired: true,
        requestValidator: new apigateway.RequestValidator(this, 'MonitoringRequestValidator', {
          restApi: this.api,
          validateRequestBody: true,
          validateRequestParameters: false,
        }),
        requestModels: {
          'application/json': new apigateway.Model(this, 'MonitoringRequestModel', {
            restApi: this.api,
            contentType: 'application/json',
            schema: {
              type: apigateway.JsonSchemaType.OBJECT,
              required: ['operation', 'instance_id'],
              properties: {
                operation: {
                  type: apigateway.JsonSchemaType.STRING,
                  enum: ['get_compute_metrics', 'get_connection_metrics', 'get_real_time_status'],
                },
                instance_id: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                hours: {
                  type: apigateway.JsonSchemaType.NUMBER,
                },
                period: {
                  type: apigateway.JsonSchemaType.NUMBER,
                },
              },
            },
          }),
        },
      }
    );
  }

  private createApprovalEndpoints(approvalWorkflowFunction: lambda.IFunction): void {
    // /approvals resource
    const approvals = this.api.root.addResource('approvals');

    // POST /approvals - Manage approval workflow
    approvals.addMethod(
      'POST',
      new apigateway.LambdaIntegration(approvalWorkflowFunction, {
        proxy: true,
      }),
      {
        apiKeyRequired: true,
        requestValidator: new apigateway.RequestValidator(this, 'ApprovalRequestValidator', {
          restApi: this.api,
          validateRequestBody: true,
          validateRequestParameters: false,
        }),
        requestModels: {
          'application/json': new apigateway.Model(this, 'ApprovalRequestModel', {
            restApi: this.api,
            contentType: 'application/json',
            schema: {
              type: apigateway.JsonSchemaType.OBJECT,
              required: ['operation'],
              properties: {
                operation: {
                  type: apigateway.JsonSchemaType.STRING,
                  enum: [
                    'create_request',
                    'approve_request',
                    'reject_request',
                    'cancel_request',
                    'get_pending_approvals',
                    'get_user_requests',
                    'get_request'
                  ],
                },
                request_id: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                operation_type: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                instance_id: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                parameters: {
                  type: apigateway.JsonSchemaType.OBJECT,
                },
                requested_by: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                approved_by: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                rejected_by: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                cancelled_by: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                risk_level: {
                  type: apigateway.JsonSchemaType.STRING,
                  enum: ['low', 'medium', 'high'],
                },
                environment: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                justification: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                reason: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                comments: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                user_email: {
                  type: apigateway.JsonSchemaType.STRING,
                },
                status: {
                  type: apigateway.JsonSchemaType.STRING,
                },
              },
            },
          }),
        },
      }
    );

    // GET /approvals - Get all approvals (for convenience)
    approvals.addMethod(
      'GET',
      new apigateway.LambdaIntegration(approvalWorkflowFunction, {
        proxy: true,
        requestTemplates: {
          'application/json': JSON.stringify({
            operation: 'get_pending_approvals',
          }),
        },
      }),
      {
        apiKeyRequired: true,
      }
    );
  }

  private createDiscoveryEndpoints(discoveryFunction: lambda.IFunction): void {
    // /discovery resource
    const discovery = this.api.root.addResource('discovery');

    // POST /discovery/trigger - Trigger RDS discovery
    const trigger = discovery.addResource('trigger');
    trigger.addMethod(
      'POST',
      new apigateway.LambdaIntegration(discoveryFunction, {
        proxy: true,
      }),
      {
        apiKeyRequired: true,
      }
    );
  }
}
