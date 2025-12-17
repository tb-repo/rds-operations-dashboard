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
}
exports.ApiStack = ApiStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYXBpLXN0YWNrLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiYXBpLXN0YWNrLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7OztBQUFBLGlEQUFtQztBQUNuQyx1RUFBeUQ7QUFZekQsTUFBYSxRQUFTLFNBQVEsR0FBRyxDQUFDLEtBQUs7SUFJckMsWUFBWSxLQUFnQixFQUFFLEVBQVUsRUFBRSxLQUFvQjtRQUM1RCxLQUFLLENBQUMsS0FBSyxFQUFFLEVBQUUsRUFBRSxLQUFLLENBQUMsQ0FBQztRQUV4QixrQkFBa0I7UUFDbEIsSUFBSSxDQUFDLEdBQUcsR0FBRyxJQUFJLFVBQVUsQ0FBQyxPQUFPLENBQUMsSUFBSSxFQUFFLFdBQVcsRUFBRTtZQUNuRCxXQUFXLEVBQUUsOEJBQThCO1lBQzNDLFdBQVcsRUFBRSxrQ0FBa0M7WUFDL0MsYUFBYSxFQUFFLENBQUMsVUFBVSxDQUFDLFlBQVksQ0FBQyxRQUFRLENBQUM7WUFDakQsYUFBYSxFQUFFO2dCQUNiLFNBQVMsRUFBRSxNQUFNO2dCQUNqQixtQkFBbUIsRUFBRSxHQUFHO2dCQUN4QixvQkFBb0IsRUFBRSxHQUFHO2dCQUN6QixjQUFjLEVBQUUsSUFBSTtnQkFDcEIsWUFBWSxFQUFFLFVBQVUsQ0FBQyxrQkFBa0IsQ0FBQyxJQUFJO2dCQUNoRCxnQkFBZ0IsRUFBRSxJQUFJO2FBQ3ZCO1lBQ0QsMkJBQTJCLEVBQUU7Z0JBQzNCLFlBQVksRUFBRSxVQUFVLENBQUMsSUFBSSxDQUFDLFdBQVc7Z0JBQ3pDLFlBQVksRUFBRSxVQUFVLENBQUMsSUFBSSxDQUFDLFdBQVc7Z0JBQ3pDLFlBQVksRUFBRTtvQkFDWixjQUFjO29CQUNkLFlBQVk7b0JBQ1osZUFBZTtvQkFDZixXQUFXO29CQUNYLHNCQUFzQjtpQkFDdkI7Z0JBQ0QsZ0JBQWdCLEVBQUUsSUFBSTthQUN2QjtTQUNGLENBQUMsQ0FBQztRQUVILG9DQUFvQztRQUNwQyxJQUFJLENB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QUFFO2dDQUNWLElBQUksRUFBRSxVQUFVLENBQUMsY0FBYyxDQUFDLE1BQU07NkJBQ3ZDOzRCQUNELE1BQU0sRUFBRTtnQ0FDTixJQUFJLEVBQUUsVUFBVSxDQUFDLGNBQWMsQ0FBQyxNQUFNOzZCQUN2Qzt5QkFDRjtxQkFDRjtpQkFDRixDQUFDO2FBQ0g7U0FDRixDQUNGLENBQUM7UUFFRix1REFBdUQ7UUFDdkQsU0FBUyxDQUFDLFNBQVMsQ0FDakIsS0FBSyxFQUNMLElBQUksVUFBVSxDQUFDLGlCQUFpQixDQUFDLHdCQUF3QixFQUFFO1lBQ3pELEtBQUssRUFBRSxJQUFJO1lBQ1gsZ0JBQWdCLEVBQUU7Z0JBQ2hCLGtCQUFrQixFQUFFLElBQUksQ0FBQyxTQUFTLENBQUM7b0JBQ2pDLFNBQVMsRUFBRSx1QkFBdUI7aUJBQ25DLENBQUM7YUFDSDtTQUNGLENBQUMsRUFDRjtZQUNFLGNBQWMsRUFBRSxJQUFJO1NBQ3JCLENBQ0YsQ0FBQztJQUNKLENBQUM7Q0FDRjtBQWpuQkQsNEJBaW5CQyIsInNvdXJjZXNDb250ZW50IjpbImltcG9ydCAqIGFzIGNkayBmcm9tICdhd3MtY2RrLWxpYic7XHJcbmltcG9ydCAqIGFzIGFwaWdhdGV3YXkgZnJvbSAnYXdzLWNkay1saWIvYXdzLWFwaWdhdGV3YXknO1xyXG5pbXBvcnQgKiBhcyBsYW1iZGEgZnJvbSAnYXdzLWNkay1saWIvYXdzLWxhbWJkYSc7XHJcbmltcG9ydCB7IENvbnN0cnVjdCB9IGZyb20gJ2NvbnN0cnVjdHMnO1xyXG5cclxuZXhwb3J0IGludGVyZmFjZSBBcGlTdGFja1Byb3BzIGV4dGVuZHMgY2RrLlN0YWNrUHJvcHMge1xyXG4gIHF1ZXJ5SGFuZGxlckZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uO1xyXG4gIG9wZXJhdGlvbnNGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBjbG91ZE9wc0dlbmVyYXRvckZ1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uO1xyXG4gIG1vbml0b3JpbmdGdW5jdGlvbjogbGFtYmRhLklGdW5jdGlvbjtcclxuICBhcHByb3ZhbFdvcmtmbG93RnVuY3Rpb246IGxhbWJkYS5JRnVuY3Rpb247XHJcbn1cclxuXHJcbmV4cG9ydCBjbGFzcyBBcGlTdGFjayBleHRlbmRzIGNkay5TdGFjayB7XHJcbiAgcHVibGljIHJlYWRvbmx5IGFwaTogYXBpZ2F0ZXdheS5SZXN0QXBpO1xyXG4gIHB1YmxpYyByZWFkb25seSBhcGlLZXk6IGFwaWdhdGV3YXkuSUFwaUtleTtcclxuXHJcbiAgY29uc3RydWN0b3Ioc2NvcGU6IENvbnN0cnVjdCwgaWQ6IHN0cmluZywgcHJvcHM6IEFwaVN0YWNrUHJvcHMpIHtcclxuICAgIHN1cGVyKHNjb3BlLCBpZCwgcHJvcHMpO1xyXG5cclxuICAgIC8vIENyZWF0ZSBSRVNUIEFQSVxyXG4gICAgdGhpcy5hcGkgPSBuZXcgYXBpZ2F0ZXdheS5SZXN0QXBpKHRoaXMsICdSZHNPcHNBcGknLCB7XHJcbiAgICAgIHJlc3RBcGlOYW1lOiAnUkRTIE9wZXJhdGlvbnMgRGFzaGJvYXJkIEFQSScsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQVBJIGZvciBSRFMgT3BlcmF0aW9ucyBEYXNoYm9hcmQnLFxyXG4gICAgICBlbmRwb2ludFR5cGVzOiBbYXBpZ2F0ZXdheS5FbmRwb2ludFR5cGUuUkVHSU9OQUxdLFxyXG4gICAgICBkZXBsb3lPcHRpb25zOiB7XHJcbiAgICAgICAgc3RhZ2VOYW1lOiAncHJvZCcsXHJcbiAgICAgICAgdGhyb3R0bGluZ1JhdGVMaW1pdDogMTAwLFxyXG4gICAgICAgIHRocm90dGxpbmdCdXJzdExpbWl0OiAyMDAsXHJcbiAgICAgICAgbWV0cmljc0VuYWJsZWQ6IHRydWUsXHJcbiAgICAgICAgbG9nZ2luZ0xldmVsOiBhcGlnYXRld2F5Lk1ldGhvZExvZ2dpbmdMZXZlbC5JTkZPLFxyXG4gICAgICAgIGRhdGFUcmFjZUVuYWJsZWQ6IHRydWUsXHJcbiAgICAgIH0sXHJcbiAgICAgIGRlZmF1bHRDb3JzUHJlZmxpZ2h0T3B0aW9uczoge1xyXG4gICAgICAgIGFsbG93T3JpZ2luczogYXBpZ2F0ZXdheS5Db3JzLkFMTF9PUklHSU5TLFxyXG4gICAgICAgIGFsbG93TWV0aG9kczogYXBpZ2F0ZXdheS5Db3JzLkFMTF9NRVRIT0RTLFxyXG4gICAgICAgIGFsbG93SGVhZGVyczogW1xyXG4gICAgICAgICAgJ0NvbnRlbnQtVHlwZScsXHJcbiAgICAgICAgICAnWC1BbXotRGF0ZScsXHJcbiAgICAgICAgICAnQXV0aG9yaXphdGlvbicsXHJcbiAgICAgICAgICAnWC1BcGktS2V5JyxcclxuICAgICAgICAgICdYLUFtei1TZWN1cml0eS1Ub2tlbicsXHJcbiAgICAgICAgXSxcclxuICAgICAgICBhbGxvd0NyZWRlbnRpYWxzOiB0cnVlLFxyXG4gICAgICB9LFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gQ3JlYXRlIEFQSSBLZXkgZm9yIGF1dGhlbnRpY2F0aW9uXHJcbiAgICB0aGlzLmFwaUtleSA9IHRoaXMuYXBpLmFkZEFwaUtleSgnQXBpS2V5Jywge1xyXG4gICAgICBhcGlLZXlOYW1lOiAncmRzLW9wcy1kYXNoYm9hcmQta2V5JyxcclxuICAgICAgZGVzY3JpcHRpb246ICdBUEkgS2V5IGZvciBSRFMgT3BlcmF0aW9ucyBEYXNoYm9hcmQnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gQ3JlYXRlIFVzYWdlIFBsYW5cclxuICAgIGNvbnN0IHVzYWdlUGxhbiA9IHRoaXMuYXBpLmFkZFVzYWdlUGxhbignVXNhZ2VQbGFuJywge1xyXG4gICAgICBuYW1lOiAnUkRTLU9wcy1EYXNoYm9hcmQtUGxhbicsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnVXNhZ2UgcGxhbiBmb3IgUkRTIE9wZXJhdGlvbnMgRGFzaGJvYXJkJyxcclxuICAgICAgdGhyb3R0bGU6IHtcclxuICAgICAgICByYXRlTGltaXQ6IDEwMCxcclxuICAgICAgICBidXJzdExpbWl0OiAyMDAsXHJcbiAgICAgIH0sXHJcbiAgICAgIHF1b3RhOiB7XHJcbiAgICAgICAgbGltaXQ6IDEwMDAwLFxyXG4gICAgICAgIHBlcmlvZDogYXBpZ2F0ZXdheS5QZXJpb2QuREFZLFxyXG4gICAgICB9LFxyXG4gICAgfSk7XHJcblxyXG4gICAgdXNhZ2VQbGFuLmFkZEFwaUtleSh0aGlzLmFwaUtleSk7XHJcbiAgICB1c2FnZVBsYW4uYWRkQXBpU3RhZ2Uoe1xyXG4gICAgICBzdGFnZTogdGhpcy5hcGkuZGVwbG95bWVudFN0YWdlLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gQ3JlYXRlIHJlc291cmNlcyBhbmQgbWV0aG9kc1xyXG4gICAgdGhpcy5jcmVhdGVJbnN0YW5jZXNFbmRwb2ludHMocHJvcHMucXVlcnlIYW5kbGVyRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVIZWFsdGhFbmRwb2ludHMocHJvcHMucXVlcnlIYW5kbGVyRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVDb3N0c0VuZHBvaW50cyhwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZUNvbXBsaWFuY2VFbmRwb2ludHMocHJvcHMucXVlcnlIYW5kbGVyRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVPcGVyYXRpb25zRW5kcG9pbnRzKHByb3BzLm9wZXJhdGlvbnNGdW5jdGlvbiwgcHJvcHMucXVlcnlIYW5kbGVyRnVuY3Rpb24pO1xyXG4gICAgdGhpcy5jcmVhdGVDbG91ZE9wc0VuZHBvaW50cyhwcm9wcy5jbG91ZE9wc0dlbmVyYXRvckZ1bmN0aW9uLCBwcm9wcy5xdWVyeUhhbmRsZXJGdW5jdGlvbik7XHJcbiAgICB0aGlzLmNyZWF0ZU1vbml0b3JpbmdFbmRwb2ludHMocHJvcHMubW9uaXRvcmluZ0Z1bmN0aW9uKTtcclxuICAgIHRoaXMuY3JlYXRlQXBwcm92YWxFbmRwb2ludHMocHJvcHMuYXBwcm92YWxXb3JrZmxvd0Z1bmN0aW9uKTtcclxuXHJcbiAgICAvLyBPdXRwdXRzXHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQXBpVXJsJywge1xyXG4gICAgICB2YWx1ZTogdGhpcy5hcGkudXJsLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0FQSSBHYXRld2F5IFVSTCcsXHJcbiAgICB9KTtcclxuXHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQXBpS2V5SWQnLCB7XHJcbiAgICAgIHZhbHVlOiB0aGlzLmFwaUtleS5rZXlJZCxcclxuICAgICAgZGVzY3JpcHRpb246ICdBUEkgS2V5IElEJyxcclxuICAgIH0pO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVJbnN0YW5jZXNFbmRwb2ludHMocXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvaW5zdGFuY2VzIHJlc291cmNlXHJcbiAgICBjb25zdCBpbnN0YW5jZXMgPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdpbnN0YW5jZXMnKTtcclxuXHJcbiAgICAvLyBHRVQgL2luc3RhbmNlcyAtIExpc3QgYWxsIGluc3RhbmNlc1xyXG4gICAgaW5zdGFuY2VzLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdsaXN0X2luc3RhbmNlcycsXHJcbiAgICAgICAgICAgIHF1ZXJ5U3RyaW5nUGFyYW1ldGVyczogJyRpbnB1dC5wYXJhbXMoKS5xdWVyeXN0cmluZycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuYWNjb3VudCc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnJlZ2lvbic6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmVuZ2luZSc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnN0YXR1cyc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmVudmlyb25tZW50JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5vZmZzZXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvaW5zdGFuY2VzL3tpbnN0YW5jZUlkfSAtIEdldCBpbnN0YW5jZSBkZXRhaWxzXHJcbiAgICBjb25zdCBpbnN0YW5jZURldGFpbCA9IGluc3RhbmNlcy5hZGRSZXNvdXJjZSgne2luc3RhbmNlSWR9Jyk7XHJcbiAgICBpbnN0YW5jZURldGFpbC5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X2luc3RhbmNlJyxcclxuICAgICAgICAgICAgaW5zdGFuY2VJZDogJyRpbnB1dC5wYXJhbXMoXFwnaW5zdGFuY2VJZFxcJyknLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnBhdGguaW5zdGFuY2VJZCc6IHRydWUsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2luc3RhbmNlcy97aW5zdGFuY2VJZH0vbWV0cmljcyAtIEdldCBpbnN0YW5jZSBtZXRyaWNzXHJcbiAgICBjb25zdCBtZXRyaWNzID0gaW5zdGFuY2VEZXRhaWwuYWRkUmVzb3VyY2UoJ21ldHJpY3MnKTtcclxuICAgIG1ldHJpY3MuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9tZXRyaWNzJyxcclxuICAgICAgICAgICAgaW5zdGFuY2VJZDogJyRpbnB1dC5wYXJhbXMoXFwnaW5zdGFuY2VJZFxcJyknLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnBhdGguaW5zdGFuY2VJZCc6IHRydWUsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcucGVyaW9kJzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuc3RhcnQnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5lbmQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVIZWFsdGhFbmRwb2ludHMocXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvaGVhbHRoIHJlc291cmNlXHJcbiAgICBjb25zdCBoZWFsdGggPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdoZWFsdGgnKTtcclxuXHJcbiAgICAvLyBHRVQgL2hlYWx0aCAtIEdldCBoZWFsdGggc3RhdHVzIGZvciBhbGwgaW5zdGFuY2VzXHJcbiAgICBoZWFsdGguYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9oZWFsdGgnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnNldmVyaXR5JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvaGVhbHRoL3tpbnN0YW5jZUlkfSAtIEdldCBoZWFsdGggZm9yIHNwZWNpZmljIGluc3RhbmNlXHJcbiAgICBjb25zdCBpbnN0YW5jZUhlYWx0aCA9IGhlYWx0aC5hZGRSZXNvdXJjZSgne2luc3RhbmNlSWR9Jyk7XHJcbiAgICBpbnN0YW5jZUhlYWx0aC5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X2luc3RhbmNlX2hlYWx0aCcsXHJcbiAgICAgICAgICAgIGluc3RhbmNlSWQ6ICckaW5wdXQucGFyYW1zKFxcJ2luc3RhbmNlSWRcXCcpJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5wYXRoLmluc3RhbmNlSWQnOiB0cnVlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9oZWFsdGgvYWxlcnRzIC0gR2V0IGFjdGl2ZSBhbGVydHNcclxuICAgIGNvbnN0IGFsZXJ0cyA9IGhlYWx0aC5hZGRSZXNvdXJjZSgnYWxlcnRzJyk7XHJcbiAgICBhbGVydHMuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9hbGVydHMnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnNldmVyaXR5JzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuc3RhdHVzJzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVDb3N0c0VuZHBvaW50cyhxdWVyeUhhbmRsZXI6IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIC9jb3N0cyByZXNvdXJjZVxyXG4gICAgY29uc3QgY29zdHMgPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdjb3N0cycpO1xyXG5cclxuICAgIC8vIEdFVCAvY29zdHMgLSBHZXQgY29zdCBhbmFseXNpc1xyXG4gICAgY29zdHMuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9jb3N0cycsXHJcbiAgICAgICAgICAgIHF1ZXJ5U3RyaW5nUGFyYW1ldGVyczogJyRpbnB1dC5wYXJhbXMoKS5xdWVyeXN0cmluZycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuZ3JvdXBCeSc6IGZhbHNlLFxyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnBlcmlvZCc6IGZhbHNlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9jb3N0cy90cmVuZHMgLSBHZXQgY29zdCB0cmVuZHNcclxuICAgIGNvbnN0IHRyZW5kcyA9IGNvc3RzLmFkZFJlc291cmNlKCd0cmVuZHMnKTtcclxuICAgIHRyZW5kcy5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X2Nvc3RfdHJlbmRzJyxcclxuICAgICAgICAgICAgcXVlcnlTdHJpbmdQYXJhbWV0ZXJzOiAnJGlucHV0LnBhcmFtcygpLnF1ZXJ5c3RyaW5nJyxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5kYXlzJzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2Nvc3RzL3JlY29tbWVuZGF0aW9ucyAtIEdldCBvcHRpbWl6YXRpb24gcmVjb21tZW5kYXRpb25zXHJcbiAgICBjb25zdCByZWNvbW1lbmRhdGlvbnMgPSBjb3N0cy5hZGRSZXNvdXJjZSgncmVjb21tZW5kYXRpb25zJyk7XHJcbiAgICByZWNvbW1lbmRhdGlvbnMuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9yZWNvbW1lbmRhdGlvbnMnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQ29tcGxpYW5jZUVuZHBvaW50cyhxdWVyeUhhbmRsZXI6IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIC9jb21wbGlhbmNlIHJlc291cmNlXHJcbiAgICBjb25zdCBjb21wbGlhbmNlID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnY29tcGxpYW5jZScpO1xyXG5cclxuICAgIC8vIEdFVCAvY29tcGxpYW5jZSAtIEdldCBjb21wbGlhbmNlIHN0YXR1c1xyXG4gICAgY29tcGxpYW5jZS5hZGRNZXRob2QoXHJcbiAgICAgICdHRVQnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihxdWVyeUhhbmRsZXIsIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VGVtcGxhdGVzOiB7XHJcbiAgICAgICAgICAnYXBwbGljYXRpb24vanNvbic6IEpTT04uc3RyaW5naWZ5KHtcclxuICAgICAgICAgICAgYWN0aW9uOiAnZ2V0X2NvbXBsaWFuY2UnLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLnNldmVyaXR5JzogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2NvbXBsaWFuY2UvdmlvbGF0aW9ucyAtIEdldCBjb21wbGlhbmNlIHZpb2xhdGlvbnNcclxuICAgIGNvbnN0IHZpb2xhdGlvbnMgPSBjb21wbGlhbmNlLmFkZFJlc291cmNlKCd2aW9sYXRpb25zJyk7XHJcbiAgICB2aW9sYXRpb25zLmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfdmlvbGF0aW9ucycsXHJcbiAgICAgICAgICAgIHF1ZXJ5U3RyaW5nUGFyYW1ldGVyczogJyRpbnB1dC5wYXJhbXMoKS5xdWVyeXN0cmluZycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuc2V2ZXJpdHknOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5saW1pdCc6IGZhbHNlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcbiAgfVxyXG5cclxuICBwcml2YXRlIGNyZWF0ZU9wZXJhdGlvbnNFbmRwb2ludHMob3BlcmF0aW9uc0Z1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uLCBxdWVyeUhhbmRsZXI6IGxhbWJkYS5JRnVuY3Rpb24pOiB2b2lkIHtcclxuICAgIC8vIC9vcGVyYXRpb25zIHJlc291cmNlXHJcbiAgICBjb25zdCBvcGVyYXRpb25zID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnb3BlcmF0aW9ucycpO1xyXG5cclxuICAgIC8vIFBPU1QgL29wZXJhdGlvbnMgLSBFeGVjdXRlIG9wZXJhdGlvblxyXG4gICAgb3BlcmF0aW9ucy5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ob3BlcmF0aW9uc0Z1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFZhbGlkYXRvcjogbmV3IGFwaWdhdGV3YXkuUmVxdWVzdFZhbGlkYXRvcih0aGlzLCAnT3BlcmF0aW9uc1ZhbGlkYXRvcicsIHtcclxuICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0Qm9keTogdHJ1ZSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdFBhcmFtZXRlcnM6IGZhbHNlLFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIHJlcXVlc3RNb2RlbHM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogbmV3IGFwaWdhdGV3YXkuTW9kZWwodGhpcywgJ09wZXJhdGlvbnNNb2RlbCcsIHtcclxuICAgICAgICAgICAgcmVzdEFwaTogdGhpcy5hcGksXHJcbiAgICAgICAgICAgIGNvbnRlbnRUeXBlOiAnYXBwbGljYXRpb24vanNvbicsXHJcbiAgICAgICAgICAgIHNjaGVtYToge1xyXG4gICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuT0JKRUNULFxyXG4gICAgICAgICAgICAgIHJlcXVpcmVkOiBbJ29wZXJhdGlvbl90eXBlJywgJ2luc3RhbmNlX2lkJ10sXHJcbiAgICAgICAgICAgICAgcHJvcGVydGllczoge1xyXG4gICAgICAgICAgICAgICAgb3BlcmF0aW9uX3R5cGU6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICAgIGVudW06IFsnY3JlYXRlX3NuYXBzaG90JywgJ3JlYm9vdCcsICdtb2RpZnlfYmFja3VwX3dpbmRvdyddLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGluc3RhbmNlX2lkOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5PQkpFQ1QsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG5cclxuICAgIC8vIEdFVCAvb3BlcmF0aW9ucy9oaXN0b3J5IC0gR2V0IG9wZXJhdGlvbnMgaGlzdG9yeVxyXG4gICAgY29uc3QgaGlzdG9yeSA9IG9wZXJhdGlvbnMuYWRkUmVzb3VyY2UoJ2hpc3RvcnknKTtcclxuICAgIGhpc3RvcnkuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24ocXVlcnlIYW5kbGVyLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIGFjdGlvbjogJ2dldF9vcGVyYXRpb25zX2hpc3RvcnknLFxyXG4gICAgICAgICAgICBxdWVyeVN0cmluZ1BhcmFtZXRlcnM6ICckaW5wdXQucGFyYW1zKCkucXVlcnlzdHJpbmcnLFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0UGFyYW1ldGVyczoge1xyXG4gICAgICAgICAgJ21ldGhvZC5yZXF1ZXN0LnF1ZXJ5c3RyaW5nLmluc3RhbmNlX2lkJzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcub3BlcmF0aW9uJzogZmFsc2UsXHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcubGltaXQnOiBmYWxzZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxuXHJcbiAgcHJpdmF0ZSBjcmVhdGVDbG91ZE9wc0VuZHBvaW50cyhjbG91ZE9wc0dlbmVyYXRvcjogbGFtYmRhLklGdW5jdGlvbiwgcXVlcnlIYW5kbGVyOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvY2xvdWRvcHMgcmVzb3VyY2VcclxuICAgIGNvbnN0IGNsb3Vkb3BzID0gdGhpcy5hcGkucm9vdC5hZGRSZXNvdXJjZSgnY2xvdWRvcHMnKTtcclxuXHJcbiAgICAvLyBQT1NUIC9jbG91ZG9wcyAtIEdlbmVyYXRlIENsb3VkT3BzIHJlcXVlc3RcclxuICAgIGNsb3Vkb3BzLmFkZE1ldGhvZChcclxuICAgICAgJ1BPU1QnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihjbG91ZE9wc0dlbmVyYXRvciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RWYWxpZGF0b3I6IG5ldyBhcGlnYXRld2F5LlJlcXVlc3RWYWxpZGF0b3IodGhpcywgJ0Nsb3VkT3BzVmFsaWRhdG9yJywge1xyXG4gICAgICAgICAgcmVzdEFwaTogdGhpcy5hcGksXHJcbiAgICAgICAgICB2YWxpZGF0ZVJlcXVlc3RCb2R5OiB0cnVlLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0UGFyYW1ldGVyczogZmFsc2UsXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgcmVxdWVzdE1vZGVsczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBuZXcgYXBpZ2F0ZXdheS5Nb2RlbCh0aGlzLCAnQ2xvdWRPcHNNb2RlbCcsIHtcclxuICAgICAgICAgICAgcmVzdEFwaTogdGhpcy5hcGksXHJcbiAgICAgICAgICAgIGNvbnRlbnRUeXBlOiAnYXBwbGljYXRpb24vanNvbicsXHJcbiAgICAgICAgICAgIHNjaGVtYToge1xyXG4gICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuT0JKRUNULFxyXG4gICAgICAgICAgICAgIHJlcXVpcmVkOiBbJ2luc3RhbmNlX2lkJywgJ3JlcXVlc3RfdHlwZSddLFxyXG4gICAgICAgICAgICAgIHByb3BlcnRpZXM6IHtcclxuICAgICAgICAgICAgICAgIGluc3RhbmNlX2lkOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHJlcXVlc3RfdHlwZToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgICAgZW51bTogWydzY2FsaW5nJywgJ3BhcmFtZXRlcl9jaGFuZ2UnLCAnbWFpbnRlbmFuY2UnXSxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICBjaGFuZ2VzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuT0JKRUNULFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHJlcXVlc3RlZF9ieToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgfSxcclxuICAgICAgICAgIH0pLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcblxyXG4gICAgLy8gR0VUIC9jbG91ZG9wcy9oaXN0b3J5IC0gR2V0IENsb3VkT3BzIHJlcXVlc3QgaGlzdG9yeVxyXG4gICAgY29uc3QgaGlzdG9yeSA9IGNsb3Vkb3BzLmFkZFJlc291cmNlKCdoaXN0b3J5Jyk7XHJcbiAgICBoaXN0b3J5LmFkZE1ldGhvZChcclxuICAgICAgJ0dFVCcsXHJcbiAgICAgIG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHF1ZXJ5SGFuZGxlciwge1xyXG4gICAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RUZW1wbGF0ZXM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogSlNPTi5zdHJpbmdpZnkoe1xyXG4gICAgICAgICAgICBhY3Rpb246ICdnZXRfY2xvdWRvcHNfaGlzdG9yeScsXHJcbiAgICAgICAgICAgIHF1ZXJ5U3RyaW5nUGFyYW1ldGVyczogJyRpbnB1dC5wYXJhbXMoKS5xdWVyeXN0cmluZycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICAgIHJlcXVlc3RQYXJhbWV0ZXJzOiB7XHJcbiAgICAgICAgICAnbWV0aG9kLnJlcXVlc3QucXVlcnlzdHJpbmcuaW5zdGFuY2VfaWQnOiBmYWxzZSxcclxuICAgICAgICAgICdtZXRob2QucmVxdWVzdC5xdWVyeXN0cmluZy5saW1pdCc6IGZhbHNlLFxyXG4gICAgICAgIH0sXHJcbiAgICAgIH1cclxuICAgICk7XHJcbiAgfVxyXG5cclxuICBwcml2YXRlIGNyZWF0ZU1vbml0b3JpbmdFbmRwb2ludHMobW9uaXRvcmluZ0Z1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvbW9uaXRvcmluZyByZXNvdXJjZVxyXG4gICAgY29uc3QgbW9uaXRvcmluZyA9IHRoaXMuYXBpLnJvb3QuYWRkUmVzb3VyY2UoJ21vbml0b3JpbmcnKTtcclxuXHJcbiAgICAvLyBQT1NUIC9tb25pdG9yaW5nIC0gRmV0Y2ggQ2xvdWRXYXRjaCBtZXRyaWNzXHJcbiAgICBtb25pdG9yaW5nLmFkZE1ldGhvZChcclxuICAgICAgJ1BPU1QnLFxyXG4gICAgICBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbihtb25pdG9yaW5nRnVuY3Rpb24sIHtcclxuICAgICAgICBwcm94eTogdHJ1ZSxcclxuICAgICAgfSksXHJcbiAgICAgIHtcclxuICAgICAgICBhcGlLZXlSZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICByZXF1ZXN0VmFsaWRhdG9yOiBuZXcgYXBpZ2F0ZXdheS5SZXF1ZXN0VmFsaWRhdG9yKHRoaXMsICdNb25pdG9yaW5nUmVxdWVzdFZhbGlkYXRvcicsIHtcclxuICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0Qm9keTogdHJ1ZSxcclxuICAgICAgICAgIHZhbGlkYXRlUmVxdWVzdFBhcmFtZXRlcnM6IGZhbHNlLFxyXG4gICAgICAgIH0pLFxyXG4gICAgICAgIHJlcXVlc3RNb2RlbHM6IHtcclxuICAgICAgICAgICdhcHBsaWNhdGlvbi9qc29uJzogbmV3IGFwaWdhdGV3YXkuTW9kZWwodGhpcywgJ01vbml0b3JpbmdSZXF1ZXN0TW9kZWwnLCB7XHJcbiAgICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgICBjb250ZW50VHlwZTogJ2FwcGxpY2F0aW9uL2pzb24nLFxyXG4gICAgICAgICAgICBzY2hlbWE6IHtcclxuICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk9CSkVDVCxcclxuICAgICAgICAgICAgICByZXF1aXJlZDogWydvcGVyYXRpb24nLCAnaW5zdGFuY2VfaWQnXSxcclxuICAgICAgICAgICAgICBwcm9wZXJ0aWVzOiB7XHJcbiAgICAgICAgICAgICAgICBvcGVyYXRpb246IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICAgIGVudW06IFsnZ2V0X2NvbXB1dGVfbWV0cmljcycsICdnZXRfY29ubmVjdGlvbl9tZXRyaWNzJywgJ2dldF9yZWFsX3RpbWVfc3RhdHVzJ10sXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgaW5zdGFuY2VfaWQ6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgaG91cnM6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5OVU1CRVIsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgcGVyaW9kOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuTlVNQkVSLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICB9LFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuICB9XHJcblxyXG4gIHByaXZhdGUgY3JlYXRlQXBwcm92YWxFbmRwb2ludHMoYXBwcm92YWxXb3JrZmxvd0Z1bmN0aW9uOiBsYW1iZGEuSUZ1bmN0aW9uKTogdm9pZCB7XHJcbiAgICAvLyAvYXBwcm92YWxzIHJlc291cmNlXHJcbiAgICBjb25zdCBhcHByb3ZhbHMgPSB0aGlzLmFwaS5yb290LmFkZFJlc291cmNlKCdhcHByb3ZhbHMnKTtcclxuXHJcbiAgICAvLyBQT1NUIC9hcHByb3ZhbHMgLSBNYW5hZ2UgYXBwcm92YWwgd29ya2Zsb3dcclxuICAgIGFwcHJvdmFscy5hZGRNZXRob2QoXHJcbiAgICAgICdQT1NUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oYXBwcm92YWxXb3JrZmxvd0Z1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIH0pLFxyXG4gICAgICB7XHJcbiAgICAgICAgYXBpS2V5UmVxdWlyZWQ6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFZhbGlkYXRvcjogbmV3IGFwaWdhdGV3YXkuUmVxdWVzdFZhbGlkYXRvcih0aGlzLCAnQXBwcm92YWxSZXF1ZXN0VmFsaWRhdG9yJywge1xyXG4gICAgICAgICAgcmVzdEFwaTogdGhpcy5hcGksXHJcbiAgICAgICAgICB2YWxpZGF0ZVJlcXVlc3RCb2R5OiB0cnVlLFxyXG4gICAgICAgICAgdmFsaWRhdGVSZXF1ZXN0UGFyYW1ldGVyczogZmFsc2UsXHJcbiAgICAgICAgfSksXHJcbiAgICAgICAgcmVxdWVzdE1vZGVsczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBuZXcgYXBpZ2F0ZXdheS5Nb2RlbCh0aGlzLCAnQXBwcm92YWxSZXF1ZXN0TW9kZWwnLCB7XHJcbiAgICAgICAgICAgIHJlc3RBcGk6IHRoaXMuYXBpLFxyXG4gICAgICAgICAgICBjb250ZW50VHlwZTogJ2FwcGxpY2F0aW9uL2pzb24nLFxyXG4gICAgICAgICAgICBzY2hlbWE6IHtcclxuICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLk9CSkVDVCxcclxuICAgICAgICAgICAgICByZXF1aXJlZDogWydvcGVyYXRpb24nXSxcclxuICAgICAgICAgICAgICBwcm9wZXJ0aWVzOiB7XHJcbiAgICAgICAgICAgICAgICBvcGVyYXRpb246IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICAgIGVudW06IFtcclxuICAgICAgICAgICAgICAgICAgICAnY3JlYXRlX3JlcXVlc3QnLFxyXG4gICAgICAgICAgICAgICAgICAgICdhcHByb3ZlX3JlcXVlc3QnLFxyXG4gICAgICAgICAgICAgICAgICAgICdyZWplY3RfcmVxdWVzdCcsXHJcbiAgICAgICAgICAgICAgICAgICAgJ2NhbmNlbF9yZXF1ZXN0JyxcclxuICAgICAgICAgICAgICAgICAgICAnZ2V0X3BlbmRpbmdfYXBwcm92YWxzJyxcclxuICAgICAgICAgICAgICAgICAgICAnZ2V0X3VzZXJfcmVxdWVzdHMnLFxyXG4gICAgICAgICAgICAgICAgICAgICdnZXRfcmVxdWVzdCdcclxuICAgICAgICAgICAgICAgICAgXSxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICByZXF1ZXN0X2lkOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIG9wZXJhdGlvbl90eXBlOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGluc3RhbmNlX2lkOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHBhcmFtZXRlcnM6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5PQkpFQ1QsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgcmVxdWVzdGVkX2J5OiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGFwcHJvdmVkX2J5OiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHJlamVjdGVkX2J5OiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGNhbmNlbGxlZF9ieToge1xyXG4gICAgICAgICAgICAgICAgICB0eXBlOiBhcGlnYXRld2F5Lkpzb25TY2hlbWFUeXBlLlNUUklORyxcclxuICAgICAgICAgICAgICAgIH0sXHJcbiAgICAgICAgICAgICAgICByaXNrX2xldmVsOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgICBlbnVtOiBbJ2xvdycsICdtZWRpdW0nLCAnaGlnaCddLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGVudmlyb25tZW50OiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGp1c3RpZmljYXRpb246IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgcmVhc29uOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIGNvbW1lbnRzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICAgIHVzZXJfZW1haWw6IHtcclxuICAgICAgICAgICAgICAgICAgdHlwZTogYXBpZ2F0ZXdheS5Kc29uU2NoZW1hVHlwZS5TVFJJTkcsXHJcbiAgICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICAgICAgc3RhdHVzOiB7XHJcbiAgICAgICAgICAgICAgICAgIHR5cGU6IGFwaWdhdGV3YXkuSnNvblNjaGVtYVR5cGUuU1RSSU5HLFxyXG4gICAgICAgICAgICAgICAgfSxcclxuICAgICAgICAgICAgICB9LFxyXG4gICAgICAgICAgICB9LFxyXG4gICAgICAgICAgfSksXHJcbiAgICAgICAgfSxcclxuICAgICAgfVxyXG4gICAgKTtcclxuXHJcbiAgICAvLyBHRVQgL2FwcHJvdmFscyAtIEdldCBhbGwgYXBwcm92YWxzIChmb3IgY29udmVuaWVuY2UpXHJcbiAgICBhcHByb3ZhbHMuYWRkTWV0aG9kKFxyXG4gICAgICAnR0VUJyxcclxuICAgICAgbmV3IGFwaWdhdGV3YXkuTGFtYmRhSW50ZWdyYXRpb24oYXBwcm92YWxXb3JrZmxvd0Z1bmN0aW9uLCB7XHJcbiAgICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgICAgcmVxdWVzdFRlbXBsYXRlczoge1xyXG4gICAgICAgICAgJ2FwcGxpY2F0aW9uL2pzb24nOiBKU09OLnN0cmluZ2lmeSh7XHJcbiAgICAgICAgICAgIG9wZXJhdGlvbjogJ2dldF9wZW5kaW5nX2FwcHJvdmFscycsXHJcbiAgICAgICAgICB9KSxcclxuICAgICAgICB9LFxyXG4gICAgICB9KSxcclxuICAgICAge1xyXG4gICAgICAgIGFwaUtleVJlcXVpcmVkOiB0cnVlLFxyXG4gICAgICB9XHJcbiAgICApO1xyXG4gIH1cclxufVxyXG4iXX0=