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
exports.ApiStack = void 0;
const cdk = __importStar(require("aws-cdk-lib"));
const apigateway = __importStar(require("aws-cdk-lib/aws-apigateway"));
class ApiStack extends cdk.Stack {
    constructor(scope, id, props) {
        super(scope, id, props);
        // Create REST API
        this.api = new apigateway.RestApi(this, 'RdsOpsApi', {
            restApiName: 'RDS Operations Dashboard API',
            description: 'API for RDS Operations Dashboard',
            endpointTypes: [apigateway.EndpointType.REGIONAL],
            deployOptions: {
                stageName: '$default',
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
        this.createErrorResolutionEndpoints(props.errorResolutionFunction);
        this.createMonitoringDashboardEndpoints(props.monitoringDashboardFunction);
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
    createInstancesEndpoints(queryHandler) {
        // /instances resource
        const instances = this.api.root.addResource('instances');
        // GET /instances - List all instances
        instances.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'list_instances',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
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
        });
        // GET /instances/{instanceId} - Get instance details
        const instanceDetail = instances.addResource('{instanceId}');
        instanceDetail.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_instance',
                    instanceId: '$input.params(\'instanceId\')',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.path.instanceId': true,
            },
        });
        // GET /instances/{instanceId}/metrics - Get instance metrics
        const metrics = instanceDetail.addResource('metrics');
        metrics.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_metrics',
                    instanceId: '$input.params(\'instanceId\')',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.path.instanceId': true,
                'method.request.querystring.period': false,
                'method.request.querystring.start': false,
                'method.request.querystring.end': false,
            },
        });
    }
    createHealthEndpoints(queryHandler) {
        // /health resource
        const health = this.api.root.addResource('health');
        // GET /health - Get health status for all instances
        health.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_health',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.severity': false,
                'method.request.querystring.limit': false,
            },
        });
        // GET /health/{instanceId} - Get health for specific instance
        const instanceHealth = health.addResource('{instanceId}');
        instanceHealth.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_instance_health',
                    instanceId: '$input.params(\'instanceId\')',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.path.instanceId': true,
            },
        });
        // GET /health/alerts - Get active alerts
        const alerts = health.addResource('alerts');
        alerts.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_alerts',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.severity': false,
                'method.request.querystring.status': false,
                'method.request.querystring.limit': false,
            },
        });
    }
    createCostsEndpoints(queryHandler) {
        // /costs resource
        const costs = this.api.root.addResource('costs');
        // GET /costs - Get cost analysis
        costs.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_costs',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.groupBy': false,
                'method.request.querystring.period': false,
            },
        });
        // GET /costs/trends - Get cost trends
        const trends = costs.addResource('trends');
        trends.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_cost_trends',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.days': false,
            },
        });
        // GET /costs/recommendations - Get optimization recommendations
        const recommendations = costs.addResource('recommendations');
        recommendations.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_recommendations',
                }),
            },
        }), {
            apiKeyRequired: true,
        });
    }
    createComplianceEndpoints(queryHandler) {
        // /compliance resource
        const compliance = this.api.root.addResource('compliance');
        // GET /compliance - Get compliance status
        compliance.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_compliance',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.severity': false,
            },
        });
        // GET /compliance/violations - Get compliance violations
        const violations = compliance.addResource('violations');
        violations.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_violations',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.severity': false,
                'method.request.querystring.limit': false,
            },
        });
    }
    createOperationsEndpoints(operationsFunction, queryHandler) {
        // /operations resource
        const operations = this.api.root.addResource('operations');
        // POST /operations - Execute operation
        operations.addMethod('POST', new apigateway.LambdaIntegration(operationsFunction, {
            proxy: true,
        }), {
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
        });
        // GET /operations/history - Get operations history
        const history = operations.addResource('history');
        history.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_operations_history',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.instance_id': false,
                'method.request.querystring.operation': false,
                'method.request.querystring.limit': false,
            },
        });
    }
    createCloudOpsEndpoints(cloudOpsGenerator, queryHandler) {
        // /cloudops resource
        const cloudops = this.api.root.addResource('cloudops');
        // POST /cloudops - Generate CloudOps request
        cloudops.addMethod('POST', new apigateway.LambdaIntegration(cloudOpsGenerator, {
            proxy: true,
        }), {
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
        });
        // GET /cloudops/history - Get CloudOps request history
        const history = cloudops.addResource('history');
        history.addMethod('GET', new apigateway.LambdaIntegration(queryHandler, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    action: 'get_cloudops_history',
                    queryStringParameters: '$input.params().querystring',
                }),
            },
        }), {
            apiKeyRequired: true,
            requestParameters: {
                'method.request.querystring.instance_id': false,
                'method.request.querystring.limit': false,
            },
        });
    }
    createMonitoringEndpoints(monitoringFunction) {
        // /monitoring resource
        const monitoring = this.api.root.addResource('monitoring');
        // POST /monitoring - Fetch CloudWatch metrics
        monitoring.addMethod('POST', new apigateway.LambdaIntegration(monitoringFunction, {
            proxy: true,
        }), {
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
        });
    }
    createApprovalEndpoints(approvalWorkflowFunction) {
        // /approvals resource
        const approvals = this.api.root.addResource('approvals');
        // POST /approvals - Manage approval workflow
        approvals.addMethod('POST', new apigateway.LambdaIntegration(approvalWorkflowFunction, {
            proxy: true,
        }), {
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
        });
        // GET /approvals - Get all approvals (for convenience)
        approvals.addMethod('GET', new apigateway.LambdaIntegration(approvalWorkflowFunction, {
            proxy: true,
            requestTemplates: {
                'application/json': JSON.stringify({
                    operation: 'get_pending_approvals',
                }),
            },
        }), {
            apiKeyRequired: true,
        });
    }
    createDiscoveryEndpoints(discoveryFunction) {
        // /discovery resource
        const discovery = this.api.root.addResource('discovery');
        // POST /discovery/trigger - Trigger RDS discovery
        const trigger = discovery.addResource('trigger');
        trigger.addMethod('POST', new apigateway.LambdaIntegration(discoveryFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
    }
    createErrorResolutionEndpoints(errorResolutionFunction) {
        // /error-resolution resource
        const errorResolution = this.api.root.addResource('error-resolution');
        // POST /error-resolution/detect - Detect and classify errors
        const detect = errorResolution.addResource('detect');
        detect.addMethod('POST', new apigateway.LambdaIntegration(errorResolutionFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
        // POST /error-resolution/resolve - Resolve errors automatically
        const resolve = errorResolution.addResource('resolve');
        resolve.addMethod('POST', new apigateway.LambdaIntegration(errorResolutionFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
        // GET /error-resolution/statistics - Get error resolution statistics
        const statistics = errorResolution.addResource('statistics');
        statistics.addMethod('GET', new apigateway.LambdaIntegration(errorResolutionFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
    }
    createMonitoringDashboardEndpoints(monitoringDashboardFunction) {
        // /monitoring-dashboard resource
        const monitoringDashboard = this.api.root.addResource('monitoring-dashboard');
        // GET /monitoring-dashboard/metrics - Get real-time metrics
        const metrics = monitoringDashboard.addResource('metrics');
        metrics.addMethod('GET', new apigateway.LambdaIntegration(monitoringDashboardFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
        // GET /monitoring-dashboard/health - Get system health status
        const health = monitoringDashboard.addResource('health');
        health.addMethod('GET', new apigateway.LambdaIntegration(monitoringDashboardFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
        // GET /monitoring-dashboard/trends - Get error trends
        const trends = monitoringDashboard.addResource('trends');
        trends.addMethod('GET', new apigateway.LambdaIntegration(monitoringDashboardFunction, {
            proxy: true,
        }), {
            apiKeyRequired: true,
        });
    }
}
exports.ApiStack = ApiStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYXBpLXN0YWNrLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiYXBpLXN0YWNrLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7OztBQUFBLGlEQUFtQztBQUNuQyx1RUFBeUQ7QUFlekQsTUFBYSxRQUFTLFNBQVEsR0FBRyxDQUFDLEtBQUs7SUFJckMsWUFBWSxLQUFnQixFQUFFLEVBQVUsRUFBRSxLQUFvQjtRQUM1RCxLQUFLLENBQUMsS0FBSyxFQUFFLEVBQUUsRUFBRSxLQUFLLENBQUMsQ0FBQztRQUV4QixrQkFBa0I7UUFDbEIsSUFBSSxDQUFDLEdBQUcsR0FBRyxJQUFJLFVBQVUsQ0FBQyxPQUFPLENBQUMsSUFBSSxFQUFFLFdBQVcsRUFBRTtZQUNuRCxXQUFXLEVBQUUsOEJBQThCO1lBQzNDLFdBQVcsRUFBRSxrQ0FBa0M7WUFDL0MsYUFBYSxFQUFFLENBQUMsVUFBVSxDQUFDLFlBQVksQ0FBQyxRQUFRLENBQUM7WUFDakQsYUFBYSxFQUFFO2dCQUNiLFNBQVMsRUFBRSxVQUFVO2dCQUNyQixtQkFBbUIsRUFBRSxHQUFHO2dCQUN4QixvQkFBb0IsRUFBRSxHQUFHO2dCQUN6QixjQUFjLEVBQUUsSUFBSTtnQkFDcEIsWUFBWSxFQUFFLFVBQVUsQ0FBQyxrQkFBa0IsQ0FBQyxJQUFJO2dCQUNoRCxnQkFBZ0IsRUFBRSxJQUFJO2FBQ3ZCO1lBQ0QsMkJBQTJCLEVBQUU7Z0JBQzNCLFlBQVksRUFBRSxVQUFVLENBQUMsSUFBSSxDQUFDLFdBQVc7Z0JBQ3pDLFlBQVksRUFBRSxVQUFVLENBQUMsSUFBSSxDQUFDLFdBQVc7Z0JBQ3pDLFlBQVksRUFBRTtvQkFDWixjQUFjO29CQUNkLFlBQVk7b0JBQ1osZUFBZTtvQkFDZixXQUFXO29CQUNYLHNCQUFzQjtpQkFDdkI7Z0JBQ0QsZ0JBQWdCLEVBQUUsSUFBSTthQUN2QjtTQUNGLENBQUMsQ0FBQztRQUVILG9DQUFvQztRQUNwQyxJQUFJLENB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QyxzQkFBc0IsQ0FBQyxDQUFDO1FBRTlFLDREQUE0RDtRQUM1RCxNQUFNLE9BQU8sR0FBRyxtQkFBbUIsQ0FBQyxXQUFXLENBQUMsU0FBUyxDQUFDLENBQUM7UUFDM0QsT0FBTyxDQUFDLFNBQVMsQ0FDZixLQUFLLEVBQ0wsSUFBSSxVQUFVLENBQUMsaUJBQWlCLENBQUMsMkJBQTJCLEVBQUU7WUFDNUQsS0FBSyxFQUFFLElBQUk7U0FDWixDQUFDLEVBQ0Y7WUFDRSxjQUFjLEVBQUUsSUFBSTtTQUNyQixDQUNGLENBQUM7UUFFRiw4REFBOEQ7UUFDOUQsTUFBTSxNQUFNLEdBQUcsbUJBQW1CLENBQUMsV0FBVyxDQUFDLFFBQVEsQ0FBQyxDQUFDO1FBQ3pELE1BQU0sQ0FBQyxTQUFTLENBQ2QsS0FBSyxFQUNMLElBQUksVUFBVSxDQUFDLGlCQUFpQixDQUFDLDJCQUEyQixFQUFFO1lBQzVELEtBQUssRUFBRSxJQUFJO1NBQ1osQ0FBQyxFQUNGO1lBQ0UsY0FBYyxFQUFFLElBQUk7U0FDckIsQ0FDRixDQUFDO1FBRUYsc0RBQXNEO1FBQ3RELE1BQU0sTUFBTSxHQUFHLG1CQUFtQixDQUFDLFdBQVcsQ0FBQyxRQUFRLENBQUMsQ0FBQztRQUN6RCxNQUFNLENBQUMsU0FBUyxDQUNkLEtBQUssRUFDTCxJQUFJLFVBQVUsQ0FBQyxpQkFBaUIsQ0FBQywyQkFBMkIsRUFBRTtZQUM1RCxLQUFLLEVBQUUsSUFBSTtTQUNaLENBQUMsRUFDRjtZQUNFLGNBQWMsRUFBRSxJQUFJO1NBQ3JCLENBQ0YsQ0FBQztJQUNKLENBQUM7Q0FDRjtBQXZ0QkQsNEJBdXRCQyIsInNvdXJjZXNDb250ZW50IjpbImltcG9ydCAqIGFzIGNkayBmcm9tICdhd3MtY2RrLWxpYic7XHJcbmltcG9ydCAqIGFzIGFwaWdhdGV3YXkgZnJvbSAnYXdzLWNkay1saWIvYXdzLWFwaWdhdGV3YXknO1xyXG5pbXBvcnQgKiBhcyBsYW1iZGEgZnJvbSAnYXdzLWNkay1saWIvYXdzLWxhbWJkYSc7XHJcbmltcG9ydCB7IENvbnN0cnVjdCB9IGZyb20gJ2NvbnN0cnVjdHMnO1xyXG5cclxuZXhwb3J0IGludGVyZmFjZSBBcGlTdGFja1Byb3BzIGV4dGVuZHMgY2RrLlN0YWNrUHJvcHMge1xyXG4gIHF1ZXJ5SGFuZGxlckZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uO1xyXG4gIG9wZXJhdGlvbnNGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBjbG91ZE9wc0dlbmVyYXRvckZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uO1xyXG4gIG1vbml0b3JpbmdGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBhcHByb3ZhbFdvcmtmbG93RnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgZGlzY292ZXJ5RnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgZXJyb3JSZXNvbHV0aW9uRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbiAgbW9uaXRvcmluZ0Rhc2hib2FyZEZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uO1xyXG59XHJcblxyXG5leHBvcnQgY2xhc3MgQXBpU3RhY2sgZXh0ZW5kcyBjZGsuU3RhY2sge1xyXG4gIHB1YmxpYyByZWFkb25seSBhcGk6IGFwaWdhdGV3YXkuUmVzdEFwaTtcclxuICBwdWJsaWMgcmVhZG9ubHkgYXBpS2V5OiBhcGlnYXRld2F5LklBcGlLZXk7XHJcblxyXG4gIGNvbnN0cnVjdG9yKHNjb3BlOiBDb25zdHJ1Y3QsIGlkOiBzdHJpbmcsIHByb3BzOiBBcGlTdGFja1Byb3BzKSB7XHJcbiAgICBzdXBlcihzY29wZSwgaWQsIHByb3BzKTtcclxuXHJcbiAgICAvLyBDcmVhdGUgUkVTVCBBUElcclxuICAgIHRoaXMuYXBpID0gbmV3IGFwaWdhdGV3YXkuUmVzdEFwaSh0aGlzLCAnUmRzT3BzQXBpJywge1xyXG4gICAgICByZXN0QXBpTmFtZTogJ1JEUyBPcGVyYXRpb25zIERhc2hib2FyZCBBUEknLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0FQSSBmb3IgUkRTIE9wZXJhdGlvbnMgRGFzaGJvYXJkJyxcclxuICAgICAgZW5kcG9pbnRUeXBlczogW2FwaWdhdGV3YXkuRW5kcG9pbnRUeXBlLlJFR0lPTkFMXSxcclxuICAgICAgZGVwbG95T3B0aW9uczoge1xyXG4gICAgICAgIHN0YWdlTmFtZTogJyRkZWZhdWx0JyxcclxuICAgICAgICB0aHJvdHRsaW5nUmF0ZUxpbWl0OiAxMDAsXHJcbiAgICAgICAgdGhyb3R0bGluZ0J1cnN0TGltaXQ6IDIwMCxcclxuICAgICAgICBtZXRyaWNzRW5hYmxlZDogdHJ1ZSxcclxuICAgICAgICBsb2dnaW5nTGV2ZWw6IGFwaWdhdGV3YXkuTWV0aG9kTG9nZ2luZ0xldmVsLklORk8sXHJcbiAgICAgICAgZGF0YVRyYWNlRW5hYmxlZDogdHJ1ZSxcclxuICAgICAgfSxcclxuICAgICAgZGVmYXVsdENvcnNQcmVmbGlnaHRPcHRpb25zOiB7XHJcbiAgICAgICAgYWxsb3dPcmlnaW5zOiBhcGlnYXRld2F5LkNvcnMuQUxMX09SSUdJTlMsXHJcbiAgICAgICAgYWxsb3dNZXRob2RzOiBhcGlnYXRld2F5LkNvcnMuQUxMX01FVEhPRFMsXHJcbiAgICAgICAgYWxsb3dIZWFkZXJzOiBbXHJcbiAgICAgICAgICAnQ29udGVudC1UeXBlJyxcclxuICAgICAgICAgICdYLUFtei1EYXRlJyxcclxuICAgICAgICAgICdBdXRob3JpemF0aW9uJyxcclxuICAgICAgICAgICdYLUFwaS1LZXknLFxyXG4gICAgICAgICAgJ1gtQW16LVNlY3VyaXR5LVRva2VuJyxcclxuICAgICAgICBdLFxyXG4gICAgICAgIGFsbG93Q3JlZGVudGlhbHM6IHRydWUsXHJcbiAgICAgIH0sXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBDcmVhdGUgQVBJIEtleSBmb3IgYXV0aGVudGljYXRpb25cclxuICAgIHRoaXMuYXBpS2V5ID0gdGhpcy5hcGkuYWRkQXBpS2V5KCdBcGlLZXknLCB7XHJcbiAgICAgIGFwaUtleU5hbWU6ICdyZHMtb3BzLWRhc2hib2FyZC1rZXknLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0FQSSBLZXkgZm9yIFJEUyBPcGVyYXRpb25zIERhc2hib2FyZCcsXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBDcmVhdGUgVXNhZ2UgUGxhblxyXG4gICAgY29uc3QgdXNhZ2VQbGFuID0gdGhpcy5hcGkuYWRkVXNhZ2VQbGFuKCdVc2FnZVBsYW4nLCB7XHJcbiAgICAgIG5hbWU6ICdSRFMtT3BzLURhc2hib2FyZC1QbGFuJyxcclxuICAgICAgZGVzY3JpcHRpb246ICdVc2FnZSBwbGFuIGZvciBSRFMgT3BlcmF0aW9ucyBEYXNoYm9hcmQnLFxyXG4gICAgICB0aHJvdHRsZToge1xyXG4gICAgICAgIHJhdGVMaW1pdDogMTAwLFxyXG4gICAgICAgIGJ1cnN0TGltaXQ6IDIwMCxcclxuICAgICAgfSxcclxuICAgICAgcXVvdGE6IHtcclxuICAgICAgICBsaW1pdDogMTAwMDAsXHJcbiAgICAgICAgcGVyaW9kOiBhcGlnYXRld2F5LlBlcmlvZC5EQVksXHJcbiAgICAgIH0sXHJcbiAgICB9KTtcclxuXHJcbiAgICB1c2FnZVBsYW4uYWRkQXBpS2V5KHRoaXMuYXBpS2V5KTtcclxuICAgIHVzYWdlUGxhbi5hZGRBcGlTdGFnZSh7XHJcbiAgICAgIHN0YWdlOiB0aGlzLmFwaS5kZXBsb3ltZW50U3RhZ2UsXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBDcmVhdGUgcmVzb3VyY2VzIGFuZCBtZXRob2RzXHJcbiAgICB0aGlzLmNyZWF0ZUluc3RhbmNlc0VuZHBvaW50cyhwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUhlYWx0aEVuZHBvaW50cyhwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUNvc3RzRW5kcG9pbnRzKHByb3BzLnF1ZXJ5SGFuZGxlckZ1bmN0aW9uKTtcclxuICAgIHRoaXMuY3JlYXRlQ29tcGxpYW5jZUVuZHBvaW50cyhwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZU9wZXJhdGlvbnNFbmRwb2ludHMocHJvcHMub3BlcmF0aW9uc0Z1bmN0aW9uLCBwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUNsb3VkT3BzRW5kcG9pbnRzKHByb3BzLmNsb3VkT3BzR2VuZXJhdG9yRnVuY3Rpb24sIHByb3BzLnF1ZXJ5SGFuZGxlckZ1bmN0aW9uKTtcclxuICAgIHRoaXMuY3JlYXRlTW9uaXRvcmluZ0VuZHBvaW50cyhwcm9wcy5tb25pdG9yaW5nRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVBcHByb3ZhbEVuZHBvaW50cyhwcm9wcy5hcHByb3ZhbFdvcmtmbG93RnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVEaXNjb3ZlcnlFbmRwb2ludHMocHJvcHMuZGlzY292ZXJ5RnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVFcnJvclJlc29sdXRpb25FbmRwb2ludHMocHJvcHMuZXJyb3JSZXNvbHV0aW9uRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVNb25pdG9yaW5nRGFzaGJvYXJkRW5kcG9pbnRzKHByb3BzLm1vbml0b3JpbmdEYXNoYm9hcmRGdW5jdGlvbik7XHJcblxyXG4gICAgLy8gT3V0cHV0c1xyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0FwaVVybCcsIHtcclxuICAgICAgdmFsdWU6IHRoaXMuYXBpLnVybCxcclxuICAgICAgZGVzY3JpcHRpb246ICdBUEkgR2F0ZXdheSBVUkwnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0FwaUtleUlkJywge1xyXG4gICAgICB2YWx1ZTogdGhpcy5hcGlLZXkua2V5SWQsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQVBJIEtleSBJRCcsXHJcbiAgICB9KTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlSW5zdGFuY2VzRW5kcG9pbnRzKHF1ZXJ5SGFuZGxlcjogbGFtYmRhLklGdW5jdGlvbik6IHZvaWQge1xyXG4gICAgLy8gL2luc3RhbmNlcyByZXNvdXJjZVxyXG4gICAgY29uc3QgaW5zdGFuY2VzID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnaW5zdGFuY2VzJyk7XHJcblxyXG4gICAgLy8gR0VUIC9pbnN0YW5jZXMgLSBMaXN0IGFsbCBpbnN0YW5jZXNcclxuICAgIGluc3RhbmNlcy5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnbGlzdF9pbnN0YW5jZXMnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmFjY291bnQnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5yZWdpb24nOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5lbmdpbmUnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5zdGF0dXMnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5lbnZpcm9ubWVudCc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmxpbWl0JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcub2Zmc2V0JzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2luc3RhbmNlcy97aW5zdGFuY2VJZH0gLSBHZXQgaW5zdGFuY2UgZGV0YWlsc1xyXG4gICAgY29uc3QgaW5zdGFuY2VEZXRhaWwgPSBpbnN0YW5jZXMuYWRkUmVzb3VyY2UoJ3tpbnN0YW5jZUlkfScpO1xyXG4gICAgaW5zdGFuY2VEZXRhaWwuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9pbnN0YW5jZScsXHJcbiAgICAgICAgICAgIGluc3RhbmNlSWQ6ICckaW5wdXQucGFyYW1zKFxcJ2luc3RhbmNlSWRcXCcpJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5wYXRoLmluc3RhbmNlSWQnOiB0cnVlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9pbnN0YW5jZXMve2luc3RhbmNlSWR9L21ldHJpY3MgLSBHZXQgaW5zdGFuY2UgbWV0cmljc1xyXG4gICAgY29uc3QgbWV0cmljcyA9IGluc3RhbmNlRGV0YWlsLmFkZFJlc291cmNlKCdtZXRyaWNzJyk7XHJcbiAgICBtZXRyaWNzLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfbWV0cmljcycsXHJcbiAgICAgICAgICAgIGluc3RhbmNlSWQ6ICckaW5wdXQucGFyYW1zKFxcJ2luc3RhbmNlSWRcXCcpJyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5wYXRoLmluc3RhbmNlSWQnOiB0cnVlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnBlcmlvZCc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnN0YXJ0JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuZW5kJzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlSGVhbHRoRW5kcG9pbnRzKHF1ZXJ5SGFuZGxlcjogbGFtYmRhLklGdW5jdGlvbik6IHZvaWQge1xyXG4gICAgLy8gL2hlYWx0aCByZXNvdXJjZVxyXG4gICAgY29uc3QgaGVhbHRoID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnaGVhbHRoJyk7XHJcblxyXG4gICAgLy8gR0VUIC9oZWFsdGggLSBHZXQgaGVhbHRoIHN0YXR1cyBmb3IgYWxsIGluc3RhbmNlc1xyXG4gICAgaGVhbHRoLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfaGVhbHRoJyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5zZXZlcml0eSc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmxpbWl0JzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2hlYWx0aC97aW5zdGFuY2VJZH0gLSBHZXQgaGVhbHRoIGZvciBzcGVjaWZpYyBpbnN0YW5jZVxyXG4gICAgY29uc3QgaW5zdGFuY2VIZWFsdGggPSBoZWFsdGguYWRkUmVzb3VyY2UoJ3tpbnN0YW5jZUlkfScpO1xyXG4gICAgaW5zdGFuY2VIZWFsdGguYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9pbnN0YW5jZV9oZWFsdGgnLFxyXG4gICAgICAgICAgICBpbnN0YW5jZUlkOiAnJGlucHV0LnBhcmFtcyhcXCdpbnN0YW5jZUlkXFwnKScsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucGF0aC5pbnN0YW5jZUlkJzogdHJ1ZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvaGVhbHRoL2FsZXJ0cyAtIEdldCBhY3RpdmUgYWxlcnRzXHJcbiAgICBjb25zdCBhbGVydHMgPSBoZWFsdGguYWRkUmVzb3VyY2UoJ2FsZXJ0cycpO1xyXG4gICAgYWxlcnRzLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfYWxlcnRzJyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5zZXZlcml0eSc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnN0YXR1cyc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmxpbWl0JzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQ29zdHNFbmRwb2ludHMocXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvY29zdHMgcmVzb3VyY2VcclxuICAgIGNvbnN0IGNvc3RzID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnY29zdHMnKTtcclxuXHJcbiAgICAvLyBHRVQgL2Nvc3RzIC0gR2V0IGNvc3QgYW5hbHlzaXNcclxuICAgIGNvc3RzLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfY29zdHMnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmdyb3VwQnknOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5wZXJpb2QnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvY29zdHMvdHJlbmRzIC0gR2V0IGNvc3QgdHJlbmRzXHJcbiAgICBjb25zdCB0cmVuZHMgPSBjb3N0cy5hZGRSZXNvdXJjZSgndHJlbmRzJyk7XHJcbiAgICB0cmVuZHMuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9jb3N0X3RyZW5kcycsXHJcbiAgICAgICAgICAgIHF1ZXJ5U3RyaW5nUGFyYW1ldGVyczogJyRpbnB1dC5wYXJhbXMoKS5xdWVyeXN0cmluZycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuZGF5cyc6IGZhbHNlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9jb3N0cy9yZWNvbW1lbmRhdGlvbnMgLSBHZXQgb3B0aW1pemF0aW9uIHJlY29tbWVuZGF0aW9uc1xyXG4gICAgY29uc3QgcmVjb21tZW5kYXRpb25zID0gY29zdHMuYWRkUmVzb3VyY2UoJ3JlY29tbWVuZGF0aW9ucycpO1xyXG4gICAgcmVjb21tZW5kYXRpb25zLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfcmVjb21tZW5kYXRpb25zJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgIH1cclxuICAgICk7XHJcbiAgfVxyXG5cclxuICBwcml2YXRlIGNyZWF0ZUNvbXBsaWFuY2VFbmRwb2ludHMocXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvY29tcGxpYW5jZSByZXNvdXJjZVxyXG4gICAgY29uc3QgY29tcGxpYW5jZSA9IHRoaXMuYXBpLnJvb3QuYWRkUmVzb3VyY2UoJ2NvbXBsaWFuY2UnKTtcclxuXHJcbiAgICAvLyBHRVQgL2NvbXBsaWFuY2UgLSBHZXQgY29tcGxpYW5jZSBzdGF0dXNcclxuICAgIGNvbXBsaWFuY2UuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9jb21wbGlhbmNlJyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5zZXZlcml0eSc6IGZhbHNlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9jb21wbGlhbmNlL3Zpb2xhdGlvbnMgLSBHZXQgY29tcGxpYW5jZSB2aW9sYXRpb25zXHJcbiAgICBjb25zdCB2aW9sYXRpb25zID0gY29tcGxpYW5jZS5hZGRSZXNvdXJjZSgndmlvbGF0aW9ucycpO1xyXG4gICAgdmlvbGF0aW9ucy5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X3Zpb2xhdGlvbnMnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnNldmVyaXR5JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVPcGVyYXRpb25zRW5kcG9pbnRzKG9wZXJhdGlvbnNGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbiwgcXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvb3BlcmF0aW9ucyByZXNvdXJjZVxyXG4gICAgY29uc3Qgb3BlcmF0aW9ucyA9IHRoaXMuYXBpLnJvb3QuYWRkUmVzb3VyY2UoJ29wZXJhdGlvbnMnKTtcclxuXHJcbiAgICAvLyBQT1NUIC9vcGVyYXRpb25zIC0gRXhlY3V0ZSBvcGVyYXRpb25cclxuICAgIG9wZXJhdGlvbnMuYWRkTWV0aG9kKFxyXG4gICAgICAnUE9TVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKG9wZXJhdGlvbnNGdW5jdGlvbiwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RWYWxpZGF0b3I6IG5ldyBhcGlnYXRld2F5LlJlcXVlc3RWYWxpZGF0b3IodGhpcywgJ09wZXJhdGlvbnNWYWxpZGF0b3InLCB7XHJcbiAgICAgICAgICByZXN0QXBpOiB0aGlzLmFwaSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdEJvZHk6IHRydWUsXHJcbiAgICAgICAgICB2YWxpZGF0ZVJlcXVlc3RQYXJhbWV0ZXJzOiBmYWxzZSxcclxuICAgICAgICB9KSxcclxuICAgICAgICByZXF1ZXN0TW9kZWxzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IG5ldyBhcGlnYXRld2F5Lk1vZGVsKHRoaXMsICdPcGVyYXRpb25zTW9kZWwnLCB7XHJcbiAgICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgICBjb250ZW50VHlwZTogJ2FwcGxpY2F0aW9uL2pzb24nLFxyXG4gICAgICAgICAgICBzY2hlbWE6IHtcclxuICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk9CSkVDVCxcclxuICAgICAgICAgICAgICByZXF1aXJlZDogWydvcGVyYXRpb25fdHlwZScsICdpbnN0YW5jZV9pZCddLFxyXG4gICAgICAgICAgICAgIHByb3BlcnRpZXM6IHtcclxuICAgICAgICAgICAgICAgIG9wZXJhdGlvbl90eXBlOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgICBlbnVtOiBbJ2NyZWF0ZV9zbmFwc2hvdCcsICdyZWJvb3QnLCAnbW9kaWZ5X2JhY2t1cF93aW5kb3cnXSxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBpbnN0YW5jZV9pZDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBwYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuT0JKRUNULFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICB9LFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL29wZXJhdGlvbnMvaGlzdG9yeSAtIEdldCBvcGVyYXRpb25zIGhpc3RvcnlcclxuICAgIGNvbnN0IGhpc3RvcnkgPSBvcGVyYXRpb25zLmFkZFJlc291cmNlKCdoaXN0b3J5Jyk7XHJcbiAgICBoaXN0b3J5LmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfb3BlcmF0aW9uc19oaXN0b3J5JyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5pbnN0YW5jZV9pZCc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLm9wZXJhdGlvbic6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmxpbWl0JzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQ2xvdWRPcHNFbmRwb2ludHMoY2xvdWRPcHNHZW5lcmF0b3I6IGxhbWJkYS5JRnVuY3Rpb24sIHF1ZXJ5SGFuZGxlcjogbGFtYmRhLklGdW5jdGlvbik6IHZvaWQge1xyXG4gICAgLy8gL2Nsb3Vkb3BzIHJlc291cmNlXHJcbiAgICBjb25zdCBjbG91ZG9wcyA9IHRoaXMuYXBpLnJvb3QuYWRkUmVzb3VyY2UoJ2Nsb3Vkb3BzJyk7XHJcblxyXG4gICAgLy8gUE9TVCAvY2xvdWRvcHMgLSBHZW5lcmF0ZSBDbG91ZE9wcyByZXF1ZXN0XHJcbiAgICBjbG91ZG9wcy5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oY2xvdWRPcHNHZW5lcmF0b3IsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VmFsaWRhdG9yOiBuZXcgYXBpZ2F0ZXdheS5SZXF1ZXN0VmFsaWRhdG9yKHRoaXMsICdDbG91ZE9wc1ZhbGlkYXRvcicsIHtcclxuICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0Qm9keTogdHJ1ZSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdFBhcmFtZXRlcnM6IGZhbHNlLFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIHJlcXVlc3RNb2RlbHM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogbmV3IGFwaWdhdGV3YXkuTW9kZWwodGhpcywgJ0Nsb3VkT3BzTW9kZWwnLCB7XHJcbiAgICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgICBjb250ZW50VHlwZTogJ2FwcGxpY2F0aW9uL2pzb24nLFxyXG4gICAgICAgICAgICBzY2hlbWE6IHtcclxuICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk9CSkVDVCxcclxuICAgICAgICAgICAgICByZXF1aXJlZDogWydpbnN0YW5jZV9pZCcsICdyZXF1ZXN0X3R5cGUnXSxcclxuICAgICAgICAgICAgICBwcm9wZXJ0aWVzOiB7XHJcbiAgICAgICAgICAgICAgICBpbnN0YW5jZV9pZDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICByZXF1ZXN0X3R5cGU6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICAgIGVudW06IFsnc2NhbGluZycsICdwYXJhbWV0ZXJfY2hhbmdlJywgJ21haW50ZW5hbmNlJ10sXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgY2hhbmdlczoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk9CSkVDVCxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICByZXF1ZXN0ZWRfYnk6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvY2xvdWRvcHMvaGlzdG9yeSAtIEdldCBDbG91ZE9wcyByZXF1ZXN0IGhpc3RvcnlcclxuICAgIGNvbnN0IGhpc3RvcnkgPSBjbG91ZG9wcy5hZGRSZXNvdXJjZSgnaGlzdG9yeScpO1xyXG4gICAgaGlzdG9yeS5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X2Nsb3Vkb3BzX2hpc3RvcnknLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmluc3RhbmNlX2lkJzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVNb25pdG9yaW5nRW5kcG9pbnRzKG1vbml0b3JpbmdGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbik6IHZvaWQge1xyXG4gICAgLy8gL21vbml0b3JpbmcgcmVzb3VyY2VcclxuICAgIGNvbnN0IG1vbml0b3JpbmcgPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdtb25pdG9yaW5nJyk7XHJcblxyXG4gICAgLy8gUE9TVCAvbW9uaXRvcmluZyAtIEZldGNoIENsb3VkV2F0Y2ggbWV0cmljc1xyXG4gICAgbW9uaXRvcmluZy5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24obW9uaXRvcmluZ0Z1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFZhbGlkYXRvcjogbmV3IGFwaWdhdGV3YXkuUmVxdWVzdFZhbGlkYXRvcih0aGlzLCAnTW9uaXRvcmluZ1JlcXVlc3RWYWxpZGF0b3InLCB7XHJcbiAgICAgICAgICByZXN0QXBpOiB0aGlzLmFwaSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdEJvZHk6IHRydWUsXHJcbiAgICAgICAgICB2YWxpZGF0ZVJlcXVlc3RQYXJhbWV0ZXJzOiBmYWxzZSxcclxuICAgICAgICB9KSxcclxuICAgICAgICByZXF1ZXN0TW9kZWxzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IG5ldyBhcGlnYXRld2F5Lk1vZGVsKHRoaXMsICdNb25pdG9yaW5nUmVxdWVzdE1vZGVsJywge1xyXG4gICAgICAgICAgICByZXN0QXBpOiB0aGlzLmFwaSxcclxuICAgICAgICAgICAgY29udGVudFR5cGU6ICdhcHBsaWNhdGlvbi9qc29uJyxcclxuICAgICAgICAgICAgc2NoZW1hOiB7XHJcbiAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5PQkpFQ1QsXHJcbiAgICAgICAgICAgICAgcmVxdWlyZWQ6IFsnb3BlcmF0aW9uJywgJ2luc3RhbmNlX2lkJ10sXHJcbiAgICAgICAgICAgICAgcHJvcGVydGllczoge1xyXG4gICAgICAgICAgICAgICAgb3BlcmF0aW9uOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgICBlbnVtOiBbJ2dldF9jb21wdXRlX21ldHJpY3MnLCAnZ2V0X2Nvbm5lY3Rpb25fbWV0cmljcycsICdnZXRfcmVhbF90aW1lX3N0YXR1cyddLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGluc3RhbmNlX2lkOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGhvdXJzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuTlVNQkVSLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHBlcmlvZDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk5VTUJFUixcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgfSxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcbiAgfVxyXG5cclxuICBwcml2YXRlIGNyZWF0ZUFwcHJvdmFsRW5kcG9pbnRzKGFwcHJvdmFsV29ya2Zsb3dGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbik6IHZvaWQge1xyXG4gICAgLy8gL2FwcHJvdmFscyByZXNvdXJjZVxyXG4gICAgY29uc3QgYXBwcm92YWxzID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnYXBwcm92YWxzJyk7XHJcblxyXG4gICAgLy8gUE9TVCAvYXBwcm92YWxzIC0gTWFuYWdlIGFwcHJvdmFsIHdvcmtmbG93XHJcbiAgICBhcHByb3ZhbHMuYWRkTWV0aG9kKFxyXG4gICAgICAnUE9TVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKGFwcHJvdmFsV29ya2Zsb3dGdW5jdGlvbiwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RWYWxpZGF0b3I6IG5ldyBhcGlnYXRld2F5LlJlcXVlc3RWYWxpZGF0b3IodGhpcywgJ0FwcHJvdmFsUmVxdWVzdFZhbGlkYXRvcicsIHtcclxuICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0Qm9keTogdHJ1ZSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdFBhcmFtZXRlcnM6IGZhbHNlLFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIHJlcXVlc3RNb2RlbHM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogbmV3IGFwaWdhdGV3YXkuTW9kZWwodGhpcywgJ0FwcHJvdmFsUmVxdWVzdE1vZGVsJywge1xyXG4gICAgICAgICAgICByZXN0QXBpOiB0aGlzLmFwaSxcclxuICAgICAgICAgICAgY29udGVudFR5cGU6ICdhcHBsaWNhdGlvbi9qc29uJyxcclxuICAgICAgICAgICAgc2NoZW1hOiB7XHJcbiAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5PQkpFQ1QsXHJcbiAgICAgICAgICAgICAgcmVxdWlyZWQ6IFsnb3BlcmF0aW9uJ10sXHJcbiAgICAgICAgICAgICAgcHJvcGVydGllczoge1xyXG4gICAgICAgICAgICAgICAgb3BlcmF0aW9uOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgICBlbnVtOiBbXHJcbiAgICAgICAgICAgICAgICAgICAgJ2NyZWF0ZV9yZXF1ZXN0JyxcclxuICAgICAgICAgICAgICAgICAgICAnYXBwcm92ZV9yZXF1ZXN0JyxcclxuICAgICAgICAgICAgICAgICAgICAncmVqZWN0X3JlcXVlc3QnLFxyXG4gICAgICAgICAgICAgICAgICAgICdjYW5jZWxfcmVxdWVzdCcsXHJcbiAgICAgICAgICAgICAgICAgICAgJ2dldF9wZW5kaW5nX2FwcHJvdmFscycsXHJcbiAgICAgICAgICAgICAgICAgICAgJ2dldF91c2VyX3JlcXVlc3RzJyxcclxuICAgICAgICAgICAgICAgICAgICAnZ2V0X3JlcXVlc3QnXHJcbiAgICAgICAgICAgICAgICAgIF0sXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgcmVxdWVzdF9pZDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBvcGVyYXRpb25fdHlwZToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBpbnN0YW5jZV9pZDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBwYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuT0JKRUNULFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHJlcXVlc3RlZF9ieToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBhcHByb3ZlZF9ieToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICByZWplY3RlZF9ieToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBjYW5jZWxsZWRfYnk6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgcmlza19sZXZlbDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgICAgZW51bTogWydsb3cnLCAnbWVkaXVtJywgJ2hpZ2gnXSxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBlbnZpcm9ubWVudDoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBqdXN0aWZpY2F0aW9uOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHJlYXNvbjoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBjb21tZW50czoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICB1c2VyX2VtYWlsOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHN0YXR1czoge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgfSxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9hcHByb3ZhbHMgLSBHZXQgYWxsIGFwcHJvdmFscyAoZm9yIGNvbnZlbmllbmNlKVxyXG4gICAgYXBwcm92YWxzLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKGFwcHJvdmFsV29ya2Zsb3dGdW5jdGlvbiwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBvcGVyYXRpb246ICdnZXRfcGVuZGluZ19hcHByb3ZhbHMnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlRGlzY292ZXJ5RW5kcG9pbnRzKGRpc2NvdmVyeUZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvZGlzY292ZXJ5IHJlc291cmNlXHJcbiAgICBjb25zdCBkaXNjb3ZlcnkgPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdkaXNjb3ZlcnknKTtcclxuXHJcbiAgICAvLyBQT1NUIC9kaXNjb3ZlcnkvdHJpZ2dlciAtIFRyaWdnZXIgUkRTIGRpc2NvdmVyeVxyXG4gICAgY29uc3QgdHJpZ2dlciA9IGRpc2NvdmVyeS5hZGRSZXNvdXJjZSgndHJpZ2dlcicpO1xyXG4gICAgdHJpZ2dlci5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oZGlzY292ZXJ5RnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlRXJyb3JSZXNvbHV0aW9uRW5kcG9pbnRzKGVycm9yUmVzb2x1dGlvbkZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvZXJyb3ItcmVzb2x1dGlvbiByZXNvdXJjZVxyXG4gICAgY29uc3QgZXJyb3JSZXNvbHV0aW9uID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnZXJyb3ItcmVzb2x1dGlvbicpO1xyXG5cclxuICAgIC8vIFBPU1QgL2Vycm9yLXJlc29sdXRpb24vZGV0ZWN0IC0gRGV0ZWN0IGFuZCBjbGFzc2lmeSBlcnJvcnNcclxuICAgIGNvbnN0IGRldGVjdCA9IGVycm9yUmVzb2x1dGlvbi5hZGRSZXNvdXJjZSgnZGV0ZWN0Jyk7XHJcbiAgICBkZXRlY3QuYWRkTWV0aG9kKFxyXG4gICAgICAnUE9TVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKGVycm9yUmVzb2x1dGlvbkZ1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gUE9TVCAvZXJyb3ItcmVzb2x1dGlvbi9yZXNvbHZlIC0gUmVzb2x2ZSBlcnJvcnMgYXV0b21hdGljYWxseVxyXG4gICAgY29uc3QgcmVzb2x2ZSA9IGVycm9yUmVzb2x1dGlvbi5hZGRSZXNvdXJjZSgncmVzb2x2ZScpO1xyXG4gICAgcmVzb2x2ZS5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oZXJyb3JSZXNvbHV0aW9uRnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2Vycm9yLXJlc29sdXRpb24vc3RhdGlzdGljcyAtIEdldCBlcnJvciByZXNvbHV0aW9uIHN0YXRpc3RpY3NcclxuICAgIGNvbnN0IHN0YXRpc3RpY3MgPSBlcnJvclJlc29sdXRpb24uYWRkUmVzb3VyY2UoJ3N0YXRpc3RpY3MnKTtcclxuICAgIHN0YXRpc3RpY3MuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oZXJyb3JSZXNvbHV0aW9uRnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlTW9uaXRvcmluZ0Rhc2hib2FyZEVuZHBvaW50cyhtb25pdG9yaW5nRGFzaGJvYXJkRnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIC9tb25pdG9yaW5nLWRhc2hib2FyZCByZXNvdXJjZVxyXG4gICAgY29uc3QgbW9uaXRvcmluZ0Rhc2hib2FyZCA9IHRoaXMuYXBpLnJvb3QuYWRkUmVzb3VyY2UoJ21vbml0b3JpbmctZGFzaGJvYXJkJyk7XHJcblxyXG4gICAgLy8gR0VUIC9tb25pdG9yaW5nLWRhc2hib2FyZC9tZXRyaWNzIC0gR2V0IHJlYWwtdGltZSBtZXRyaWNzXHJcbiAgICBjb25zdCBtZXRyaWNzID0gbW9uaXRvcmluZ0Rhc2hib2FyZC5hZGRSZXNvdXJjZSgnbWV0cmljcycpO1xyXG4gICAgbWV0cmljcy5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihtb25pdG9yaW5nRGFzaGJvYXJkRnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL21vbml0b3JpbmctZGFzaGJvYXJkL2hlYWx0aCAtIEdldCBzeXN0ZW0gaGVhbHRoIHN0YXR1c1xyXG4gICAgY29uc3QgaGVhbHRoID0gbW9uaXRvcmluZ0Rhc2hib2FyZC5hZGRSZXNvdXJjZSgnaGVhbHRoJyk7XHJcbiAgICBoZWFsdGguYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24obW9uaXRvcmluZ0Rhc2hib2FyZEZ1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9tb25pdG9yaW5nLWRhc2hib2FyZC90cmVuZHMgLSBHZXQgZXJyb3IgdHJlbmRzXHJcbiAgICBjb25zdCB0cmVuZHMgPSBtb25pdG9yaW5nRGFzaGJvYXJkLmFkZFJlc291cmNlKCd0cmVuZHMnKTtcclxuICAgIHRyZW5kcy5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihtb25pdG9yaW5nRGFzaGJvYXJkRnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcbn1cclxuIl19