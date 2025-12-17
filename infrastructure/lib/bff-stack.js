"use strict";
/**
 * BFF Stack - Backend-for-Frontend with Express Container
 *
 * This stack deploys the Express BFF application as a Lambda container.
 * The Express application handles JWT validation, RBAC, and audit logging.
 *
 * Architecture Decision:
 * - Uses DockerImageFunction to deploy Express application
 * - Authentication handled by Express middleware (not API Gateway authorizer)
 * - Provides flexibility for custom authorization logic and RBAC
 * - Supports sophisticated audit logging and request tracking
 *
 * Metadata:
 * {
 *   "generated_by": "claude-3.5-sonnet",
 *   "timestamp": "2025-12-01T10:00:00Z",
 *   "version": "2.0.0",
 *   "policy_version": "v1.0.0",
 *   "traceability": "REQ-1.1, REQ-1.4 → DESIGN-BFF-Container → TASK-1.2",
 *   "review_status": "Pending",
 *   "risk_level": "Level 2",
 *   "reviewed_by": null,
 *   "approved_by": null
 * }
 */
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
exports.BffStack = void 0;
const cdk = __importStar(require("aws-cdk-lib"));
const lambda = __importStar(require("aws-cdk-lib/aws-lambda"));
const apigateway = __importStar(require("aws-cdk-lib/aws-apigateway"));
const secretsmanager = __importStar(require("aws-cdk-lib/aws-secretsmanager"));
const iam = __importStar(require("aws-cdk-lib/aws-iam"));
const logs = __importStar(require("aws-cdk-lib/aws-logs"));
const path = __importStar(require("path"));
class BffStack extends cdk.Stack {
    constructor(scope, id, props) {
        super(scope, id, props);
        // ========================================
        // Secrets Manager - Store API Key
        // ========================================
        this.apiSecret = new secretsmanager.Secret(this, 'ApiSecret', {
            secretName: 'rds-dashboard-api-key',
            description: 'API Gateway key for RDS Dashboard internal API',
            generateSecretString: {
                secretStringTemplate: JSON.stringify({
                    apiUrl: props.internalApiUrl,
                    description: 'RDS Dashboard API credentials'
                }),
                generateStringKey: 'apiKey',
                excludeCharacters: '"@/\\\'',
            },
        });
        // ========================================
        // IAM Role for BFF Lambda
        // ========================================
        const bffRole = new iam.Role(this, 'BffLambdaRole', {
            assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
            description: 'IAM role for RDS Dashboard BFF Lambda function',
            managedPolicies: [
                iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
            ],
        });
        // Grant permission to read the API secret
        this.apiSecret.grantRead(bffRole);
        // Grant permission to read Cognito User Pool (for JWT validation)
        if (props.userPoolId) {
            bffRole.addToPolicy(new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                    'cognito-idp:GetUser',
                    'cognito-idp:ListUsers',
                    'cognito-idp:AdminGetUser',
                    'cognito-idp:AdminListGroupsForUser',
                ],
                resources: [
                    `arn:aws:cognito-idp:${this.region}:${this.account}:userpool/${props.userPoolId}`,
                ],
            }));
        }
        // ========================================
        // CloudWatch Log Group for BFF
        // ========================================
        const logGroup = new logs.LogGroup(this, 'BffLogGroup', {
            logGroupName: '/aws/lambda/rds-dashboard-bff',
            retention: logs.RetentionDays.ONE_WEEK,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });
        // ========================================
        // BFF Lambda Function (Docker Container)
        // ========================================
        this.bffFunction = new lambda.DockerImageFunction(this, 'BffFunction', {
            functionName: 'rds-dashboard-bff',
            code: lambda.DockerImageCode.fromImageAsset(path.join(__dirname, '../../bff'), {
                file: 'Dockerfile',
            }),
            timeout: cdk.Duration.seconds(30),
            memorySize: 1024,
            role: bffRole,
            logGroup: logGroup,
            environment: {
                // Cognito Configuration
                COGNITO_USER_POOL_ID: props.userPoolId || '',
                COGNITO_REGION: this.region,
                COGNITO_CLIENT_ID: props.userPoolClientId || '',
                // Internal API Configuration
                INTERNAL_API_URL: props.internalApiUrl,
                INTERNAL_API_KEY: '', // Will be populated from Secrets Manager at runtime
                API_SECRET_ARN: this.apiSecret.secretArn,
                // Frontend Configuration
                FRONTEND_URL: props.frontendUrl || '*',
                // Server Configuration
                PORT: '8080', // Lambda uses port 8080 for container images
                NODE_ENV: 'production',
                LOG_LEVEL: 'info',
                // Audit Logging
                AUDIT_LOG_GROUP: '/aws/rds-dashboard/audit',
                ENABLE_AUDIT_LOGGING: 'true',
                // AWS Configuration
                AWS_NODEJS_CONNECTION_REUSE_ENABLED: '1',
                // Force rebuild
                BUILD_VERSION: '1.0.1',
            },
            description: 'Backend-for-Frontend Express service for RDS Dashboard with JWT validation and RBAC',
        });
        // Note: The old inline Lambda code has been replaced with DockerImageFunction
        // The Express BFF application will handle all routing, authentication, and authorization
        // See bff/src/index.ts for the Express application implementation
        // ========================================
        // BFF API Gateway (Public)
        // ========================================
        this.bffApi = new apigateway.RestApi(this, 'BffApi', {
            restApiName: 'rds-dashboard-bff',
            description: 'Backend-for-Frontend API for RDS Dashboard with Express BFF',
            defaultCorsPreflightOptions: {
                allowOrigins: props.frontendUrl ? [props.frontendUrl] : apigateway.Cors.ALL_ORIGINS,
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
            deployOptions: {
                stageName: 'prod',
                throttlingRateLimit: 1000,
                throttlingBurstLimit: 2000,
                loggingLevel: apigateway.MethodLoggingLevel.INFO,
                dataTraceEnabled: true,
                metricsEnabled: true,
            },
        });
        // ========================================
        // Lambda Integration (No API Gateway Authorizer)
        // ========================================
        // Note: Authentication and authorization are handled by the Express BFF
        // The Express application validates JWT tokens and enforces RBAC
        // API Gateway simply proxies all requests to the Express container
        const lambdaIntegration = new apigateway.LambdaIntegration(this.bffFunction, {
            proxy: true,
            allowTestInvoke: true,
            timeout: cdk.Duration.seconds(29), // Slightly less than Lambda timeout
        });
        // Add proxy resource for all sub-paths: /{proxy+}
        // This will handle /api/instances, /health, /api/costs, etc.
        this.bffApi.root.addProxy({
            defaultIntegration: lambdaIntegration,
            anyMethod: true, // Allow all HTTP methods
        });
        // Note: No Cognito authorizer at API Gateway level
        // The Express BFF handles JWT validation using jwks-rsa and jsonwebtoken
        // This provides more flexibility for custom authorization logic and RBAC
        // ========================================
        // CloudFormation Outputs
        // ========================================
        new cdk.CfnOutput(this, 'BffApiUrl', {
            value: this.bffApi.url,
            description: 'BFF API Gateway URL',
            exportName: 'BffApiUrl'
        });
        new cdk.CfnOutput(this, 'BffApiId', {
            value: this.bffApi.restApiId,
            description: 'BFF API Gateway ID',
            exportName: 'BffApiId'
        });
        new cdk.CfnOutput(this, 'ApiSecretArn', {
            value: this.apiSecret.secretArn,
            description: 'API Secret ARN in Secrets Manager',
            exportName: 'ApiSecretArn'
        });
    }
}
exports.BffStack = BffStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYmZmLXN0YWNrLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiYmZmLXN0YWNrLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7QUFBQTs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0dBd0JHOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7QUFFSCxpREFBbUM7QUFDbkMsK0RBQWlEO0FBQ2pELHVFQUF5RDtBQUN6RCwrRUFBaUU7QUFDakUseURBQTJDO0FBQzNDLDJEQUE2QztBQUU3QywyQ0FBNkI7QUFVN0IsTUFBYSxRQUFTLFNBQVEsR0FBRyxDQUFDLEtBQUs7SUFLckMsWUFBWSxLQUFnQixFQUFFLEVBQVUsRUFBRSxLQUFvQjtRQUM1RCxLQUFLLENBQUMsS0FBSyxFQUFFLEVBQUUsRUFBRSxLQUFLLENBQUMsQ0FBQztRQUV4QiwyQ0FBMkM7UUFDM0Msa0NBQWtDO1FBQ2xDLDJDQUEyQztRQUMzQyxJQUFJLENBQUMsU0FBUyxHQUFHLElBQUksY0FBYyxDQUFDLE1BQU0sQ0FBQyxJQUFJLEVBQUUsV0FBVyxFQUFFO1lBQzVELFVBQVUsRUFBRSx1QkFBdUI7WUFDbkMsV0FBVyxFQUFFLGdEQUFnRDtZQUM3RCxvQkFBb0IsRUFBRTtnQkFDcEIsb0JBQW9CLEVBQUUsSUFBSSxDQUFDLFNBQVMsQ0FBQztvQkFDbkMsTUFBTSxFQUFFLEtBQUssQ0FBQyxjQUFjO29CQUM1QixXQUFXLEVBQUUsK0JBQStCO2lCQUM3QyxDQUFDO2dCQUNGLGlCQUFpQixFQUFFLFFBQVE7Z0JBQzNCLGlCQUFpQixFQUFFLFNBQVM7YUFDN0I7U0FDRixDQUFDLENBQUM7UUFFSCwyQ0FBMkM7UUFDM0MsMEJBQTBCO1FBQzFCLDJDQUEyQztRQUMzQyxNQUFNLE9BQU8sR0FBRyxJQUFJLEdBQUcsQ0FBQyxJQUFJLENBQUMsSUFBSSxFQUFFLGVBQWUsRUFBRTtZQUNsRCxTQUFTLEVBQUUsSUFBSSxHQUFHLENBQUMsZ0JBQWdCLENBQUMsc0JBQXNCLENBQUM7WUFDM0Qs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QUMsTUFBTSxDQUFDLElBQUksQ0FBQyxRQUFRLENBQUM7WUFDeEIsa0JBQWtCLEVBQUUsaUJBQWlCO1lBQ3JDLFNBQVMsRUFBRSxJQUFJLEVBQUUseUJBQXlCO1NBQzNDLENBQUMsQ0FBQztRQUVILG1EQUFtRDtRQUNuRCx5RUFBeUU7UUFDekUseUVBQXlFO1FBRXpFLDJDQUEyQztRQUMzQyx5QkFBeUI7UUFDekIsMkNBQTJDO1FBQzNDLElBQUksR0FBRyxDQUFDLFNBQVMsQ0FBQyxJQUFJLEVBQUUsV0FBVyxFQUFFO1lBQ25DLEtBQUssRUFBRSxJQUFJLENBQUMsTUFBTSxDQUFDLEdBQUc7WUFDdEIsV0FBVyxFQUFFLHFCQUFxQjtZQUNsQyxVQUFVLEVBQUUsV0FBVztTQUN4QixDQUFDLENBQUM7UUFFSCxJQUFJLEdBQUcsQ0FBQyxTQUFTLENBQUMsSUFBSSxFQUFFLFVBQVUsRUFBRTtZQUNsQyxLQUFLLEVBQUUsSUFBSSxDQUFDLE1BQU0sQ0FBQyxTQUFTO1lBQzVCLFdBQVcsRUFBRSxvQkFBb0I7WUFDakMsVUFBVSxFQUFFLFVBQVU7U0FDdkIsQ0FBQyxDQUFDO1FBRUgsSUFBSSxHQUFHLENBQUMsU0FBUyxDQUFDLElBQUksRUFBRSxjQUFjLEVBQUU7WUFDdEMsS0FBSyxFQUFFLElBQUksQ0FBQyxTQUFTLENBQUMsU0FBUztZQUMvQixXQUFXLEVBQUUsbUNBQW1DO1lBQ2hELFVBQVUsRUFBRSxjQUFjO1NBQzNCLENBQUMsQ0FBQztJQUNMLENBQUM7Q0FDRjtBQXpMRCw0QkF5TEMiLCJzb3VyY2VzQ29udGVudCI6WyIvKipcclxuICogQkZGIFN0YWNrIC0gQmFja2VuZC1mb3ItRnJvbnRlbmQgd2l0aCBFeHByZXNzIENvbnRhaW5lclxyXG4gKiBcclxuICogVGhpcyBzdGFjayBkZXBsb3lzIHRoZSBFeHByZXNzIEJGRiBhcHBsaWNhdGlvbiBhcyBhIExhbWJkYSBjb250YWluZXIuXHJcbiAqIFRoZSBFeHByZXNzIGFwcGxpY2F0aW9uIGhhbmRsZXMgSldUIHZhbGlkYXRpb24sIFJCQUMsIGFuZCBhdWRpdCBsb2dnaW5nLlxyXG4gKiBcclxuICogQXJjaGl0ZWN0dXJlIERlY2lzaW9uOlxyXG4gKiAtIFVzZXMgRG9ja2VySW1hZ2VGdW5jdGlvbiB0byBkZXBsb3kgRXhwcmVzcyBhcHBsaWNhdGlvblxyXG4gKiAtIEF1dGhlbnRpY2F0aW9uIGhhbmRsZWQgYnkgRXhwcmVzcyBtaWRkbGV3YXJlIChub3QgQVBJIEdhdGV3YXkgYXV0aG9yaXplcilcclxuICogLSBQcm92aWRlcyBmbGV4aWJpbGl0eSBmb3IgY3VzdG9tIGF1dGhvcml6YXRpb24gbG9naWMgYW5kIFJCQUNcclxuICogLSBTdXBwb3J0cyBzb3BoaXN0aWNhdGVkIGF1ZGl0IGxvZ2dpbmcgYW5kIHJlcXVlc3QgdHJhY2tpbmdcclxuICogXHJcbiAqIE1ldGFkYXRhOlxyXG4gKiB7XHJcbiAqICAgXCJnZW5lcmF0ZWRfYnlcIjogXCJjbGF1ZGUtMy41LXNvbm5ldFwiLFxyXG4gKiAgIFwidGltZXN0YW1wXCI6IFwiMjAyNS0xMi0wMVQxMDowMDowMFpcIixcclxuICogICBcInZlcnNpb25cIjogXCIyLjAuMFwiLFxyXG4gKiAgIFwicG9saWN5X3ZlcnNpb25cIjogXCJ2MS4wLjBcIixcclxuICogICBcInRyYWNlYWJpbGl0eVwiOiBcIlJFUS0xLjEsIFJFUS0xLjQg4oaSIERFU0lHTi1CRkYtQ29udGFpbmVyIOKGkiBUQVNLLTEuMlwiLFxyXG4gKiAgIFwicmV2aWV3X3N0YXR1c1wiOiBcIlBlbmRpbmdcIixcclxuICogICBcInJpc2tfbGV2ZWxcIjogXCJMZXZlbCAyXCIsXHJcbiAqICAgXCJyZXZpZXdlZF9ieVwiOiBudWxsLFxyXG4gKiAgIFwiYXBwcm92ZWRfYnlcIjogbnVsbFxyXG4gKiB9XHJcbiAqL1xyXG5cclxuaW1wb3J0ICogYXMgY2RrIGZyb20gJ2F3cy1jZGstbGliJztcclxuaW1wb3J0ICogYXMgbGFtYmRhIGZyb20gJ2F3cy1jZGstbGliL2F3cy1sYW1iZGEnO1xyXG5pbXBvcnQgKiBhcyBhcGlnYXRld2F5IGZyb20gJ2F3cy1jZGstbGliL2F3cy1hcGlnYXRld2F5JztcclxuaW1wb3J0ICogYXMgc2VjcmV0c21hbmFnZXIgZnJvbSAnYXdzLWNkay1saWIvYXdzLXNlY3JldHNtYW5hZ2VyJztcclxuaW1wb3J0ICogYXMgaWFtIGZyb20gJ2F3cy1jZGstbGliL2F3cy1pYW0nO1xyXG5pbXBvcnQgKiBhcyBsb2dzIGZyb20gJ2F3cy1jZGstbGliL2F3cy1sb2dzJztcclxuaW1wb3J0IHsgQ29uc3RydWN0IH0gZnJvbSAnY29uc3RydWN0cyc7XHJcbmltcG9ydCAqIGFzIHBhdGggZnJvbSAncGF0aCc7XHJcblxyXG5leHBvcnQgaW50ZXJmYWNlIEJmZlN0YWNrUHJvcHMgZXh0ZW5kcyBjZGsuU3RhY2tQcm9wcyB7XHJcbiAgaW50ZXJuYWxBcGlVcmw6IHN0cmluZztcclxuICBhcGlLZXlJZDogc3RyaW5nO1xyXG4gIHVzZXJQb29sSWQ/OiBzdHJpbmc7XHJcbiAgdXNlclBvb2xDbGllbnRJZD86IHN0cmluZztcclxuICBmcm9udGVuZFVybD86IHN0cmluZztcclxufVxyXG5cclxuZXhwb3J0IGNsYXNzIEJmZlN0YWNrIGV4dGVuZHMgY2RrLlN0YWNrIHtcclxuICBwdWJsaWMgcmVhZG9ubHkgYmZmQXBpOiBhcGlnYXRld2F5LlJlc3RBcGk7XHJcbiAgcHVibGljIHJlYWRvbmx5IGJmZkZ1bmN0aW9uOiBsYW1iZGEuRG9ja2VySW1hZ2VGdW5jdGlvbjtcclxuICBwdWJsaWMgcmVhZG9ubHkgYXBpU2VjcmV0OiBzZWNyZXRzbWFuYWdlci5TZWNyZXQ7XHJcblxyXG4gIGNvbnN0cnVjdG9yKHNjb3BlOiBDb25zdHJ1Y3QsIGlkOiBzdHJpbmcsIHByb3BzOiBCZmZTdGFja1Byb3BzKSB7XHJcbiAgICBzdXBlcihzY29wZSwgaWQsIHByb3BzKTtcclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBTZWNyZXRzIE1hbmFnZXIgLSBTdG9yZSBBUEkgS2V5XHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICB0aGlzLmFwaVNlY3JldCA9IG5ldyBzZWNyZXRzbWFuYWdlci5TZWNyZXQodGhpcywgJ0FwaVNlY3JldCcsIHtcclxuICAgICAgc2VjcmV0TmFtZTogJ3Jkcy1kYXNoYm9hcmQtYXBpLWtleScsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQVBJIEdhdGV3YXkga2V5IGZvciBSRFMgRGFzaGJvYXJkIGludGVybmFsIEFQSScsXHJcbiAgICAgIGdlbmVyYXRlU2VjcmV0U3RyaW5nOiB7XHJcbiAgICAgICAgc2VjcmV0U3RyaW5nVGVtcGxhdGU6IEpTT04uc3RyaW5naWZ5KHsgXHJcbiAgICAgICAgICBhcGlVcmw6IHByb3BzLmludGVybmFsQXBpVXJsLFxyXG4gICAgICAgICAgZGVzY3JpcHRpb246ICdSRFMgRGFzaGJvYXJkIEFQSSBjcmVkZW50aWFscydcclxuICAgICAgICB9KSxcclxuICAgICAgICBnZW5lcmF0ZVN0cmluZ0tleTogJ2FwaUtleScsXHJcbiAgICAgICAgZXhjbHVkZUNoYXJhY3RlcnM6ICdcIkAvXFxcXFxcJycsXHJcbiAgICAgIH0sXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBJQU0gUm9sZSBmb3IgQkZGIExhbWJkYVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgY29uc3QgYmZmUm9sZSA9IG5ldyBpYW0uUm9sZSh0aGlzLCAnQmZmTGFtYmRhUm9sZScsIHtcclxuICAgICAgYXNzdW1lZEJ5OiBuZXcgaWFtLlNlcnZpY2VQcmluY2lwYWwoJ2xhbWJkYS5hbWF6b25hd3MuY29tJyksXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnSUFNIHJvbGUgZm9yIFJEUyBEYXNoYm9hcmQgQkZGIExhbWJkYSBmdW5jdGlvbicsXHJcbiAgICAgIG1hbmFnZWRQb2xpY2llczogW1xyXG4gICAgICAgIGlhbS5NYW5hZ2VkUG9saWN5LmZyb21Bd3NNYW5hZ2VkUG9saWN5TmFtZSgnc2VydmljZS1yb2xlL0FXU0xhbWJkYUJhc2ljRXhlY3V0aW9uUm9sZScpLFxyXG4gICAgICBdLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gR3JhbnQgcGVybWlzc2lvbiB0byByZWFkIHRoZSBBUEkgc2VjcmV0XHJcbiAgICB0aGlzLmFwaVNlY3JldC5ncmFudFJlYWQoYmZmUm9sZSk7XHJcblxyXG4gICAgLy8gR3JhbnQgcGVybWlzc2lvbiB0byByZWFkIENvZ25pdG8gVXNlciBQb29sIChmb3IgSldUIHZhbGlkYXRpb24pXHJcbiAgICBpZiAocHJvcHMudXNlclBvb2xJZCkge1xyXG4gICAgICBiZmZSb2xlLmFkZFRvUG9saWN5KG5ldyBpYW0uUG9saWN5U3RhdGVtZW50KHtcclxuICAgICAgICBlZmZlY3Q6IGlhbS5FZmZlY3QuQUxMT1csXHJcbiAgICAgICAgYWN0aW9uczogW1xyXG4gICAgICAgICAgJ2NvZ25pdG8taWRwOkdldFVzZXInLFxyXG4gICAgICAgICAgJ2NvZ25pdG8taWRwOkxpc3RVc2VycycsXHJcbiAgICAgICAgICAnY29nbml0by1pZHA6QWRtaW5HZXRVc2VyJyxcclxuICAgICAgICAgICdjb2duaXRvLWlkcDpBZG1pbkxpc3RHcm91cHNGb3JVc2VyJyxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHJlc291cmNlczogW1xyXG4gICAgICAgICAgYGFybjphd3M6Y29nbml0by1pZHA6JHt0aGlzLnJlZ2lvbn06JHt0aGlzLmFjY291bnR9OnVzZXJwb29sLyR7cHJvcHMudXNlclBvb2xJZH1gLFxyXG4gICAgICAgIF0sXHJcbiAgICAgIH0pKTtcclxuICAgIH1cclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBDbG91ZFdhdGNoIExvZyBHcm91cCBmb3IgQkZGXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICBjb25zdCBsb2dHcm91cCA9IG5ldyBsb2dzLkxvZ0dyb3VwKHRoaXMsICdCZmZMb2dHcm91cCcsIHtcclxuICAgICAgbG9nR3JvdXBOYW1lOiAnL2F3cy9sYW1iZGEvcmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICByZXRlbnRpb246IGxvZ3MuUmV0ZW50aW9uRGF5cy5PTkVfV0VFSyxcclxuICAgICAgcmVtb3ZhbFBvbGljeTogY2RrLlJlbW92YWxQb2xpY3kuREVTVFJPWSxcclxuICAgIH0pO1xyXG5cclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIEJGRiBMYW1iZGEgRnVuY3Rpb24gKERvY2tlciBDb250YWluZXIpXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICB0aGlzLmJmZkZ1bmN0aW9uID0gbmV3IGxhbWJkYS5Eb2NrZXJJbWFnZUZ1bmN0aW9uKHRoaXMsICdCZmZGdW5jdGlvbicsIHtcclxuICAgICAgZnVuY3Rpb25OYW1lOiAncmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICBjb2RlOiBsYW1iZGEuRG9ja2VySW1hZ2VDb2RlLmZyb21JbWFnZUFzc2V0KHBhdGguam9pbihfX2Rpcm5hbWUsICcuLi8uLi9iZmYnKSwge1xyXG4gICAgICAgIGZpbGU6ICdEb2NrZXJmaWxlJyxcclxuICAgICAgfSksXHJcbiAgICAgIHRpbWVvdXQ6IGNkay5EdXJhdGlvbi5zZWNvbmRzKDMwKSxcclxuICAgICAgbWVtb3J5U2l6ZTogMTAyNCxcclxuICAgICAgcm9sZTogYmZmUm9sZSxcclxuICAgICAgbG9nR3JvdXA6IGxvZ0dyb3VwLFxyXG4gICAgICBlbnZpcm9ubWVudDoge1xyXG4gICAgICAgIC8vIENvZ25pdG8gQ29uZmlndXJhdGlvblxyXG4gICAgICAgIENPR05JVE9fVVNFUl9QT09MX0lEOiBwcm9wcy51c2VyUG9vbElkIHx8ICcnLFxyXG4gICAgICAgIENPR05JVE9fUkVHSU9OOiB0aGlzLnJlZ2lvbixcclxuICAgICAgICBDT0dOSVRPX0NMSUVOVF9JRDogcHJvcHMudXNlclBvb2xDbGllbnRJZCB8fCAnJyxcclxuICAgICAgICBcclxuICAgICAgICAvLyBJbnRlcm5hbCBBUEkgQ29uZmlndXJhdGlvblxyXG4gICAgICAgIElOVEVSTkFMX0FQSV9VUkw6IHByb3BzLmludGVybmFsQXBpVXJsLFxyXG4gICAgICAgIElOVEVSTkFMX0FQSV9LRVk6ICcnLCAvLyBXaWxsIGJlIHBvcHVsYXRlZCBmcm9tIFNlY3JldHMgTWFuYWdlciBhdCBydW50aW1lXHJcbiAgICAgICAgQVBJX1NFQ1JFVF9BUk46IHRoaXMuYXBpU2VjcmV0LnNlY3JldEFybixcclxuICAgICAgICBcclxuICAgICAgICAvLyBGcm9udGVuZCBDb25maWd1cmF0aW9uXHJcbiAgICAgICAgRlJPTlRFTkRfVVJMOiBwcm9wcy5mcm9udGVuZFVybCB8fCAnKicsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gU2VydmVyIENvbmZpZ3VyYXRpb25cclxuICAgICAgICBQT1JUOiAnODA4MCcsIC8vIExhbWJkYSB1c2VzIHBvcnQgODA4MCBmb3IgY29udGFpbmVyIGltYWdlc1xyXG4gICAgICAgIE5PREVfRU5WOiAncHJvZHVjdGlvbicsXHJcbiAgICAgICAgTE9HX0xFVkVMOiAnaW5mbycsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gQXVkaXQgTG9nZ2luZ1xyXG4gICAgICAgIEFVRElUX0xPR19HUk9VUDogJy9hd3MvcmRzLWRhc2hib2FyZC9hdWRpdCcsXHJcbiAgICAgICAgRU5BQkxFX0FVRElUX0xPR0dJTkc6ICd0cnVlJyxcclxuICAgICAgICBcclxuICAgICAgICAvLyBBV1MgQ29uZmlndXJhdGlvblxyXG4gICAgICAgIEFXU19OT0RFSlNfQ09OTkVDVElPTl9SRVVTRV9FTkFCTEVEOiAnMScsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gRm9yY2UgcmVidWlsZFxyXG4gICAgICAgIEJVSUxEX1ZFUlNJT046ICcxLjAuMScsXHJcbiAgICAgIH0sXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQmFja2VuZC1mb3ItRnJvbnRlbmQgRXhwcmVzcyBzZXJ2aWNlIGZvciBSRFMgRGFzaGJvYXJkIHdpdGggSldUIHZhbGlkYXRpb24gYW5kIFJCQUMnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gTm90ZTogVGhlIG9sZCBpbmxpbmUgTGFtYmRhIGNvZGUgaGFzIGJlZW4gcmVwbGFjZWQgd2l0aCBEb2NrZXJJbWFnZUZ1bmN0aW9uXHJcbiAgICAvLyBUaGUgRXhwcmVzcyBCRkYgYXBwbGljYXRpb24gd2lsbCBoYW5kbGUgYWxsIHJvdXRpbmcsIGF1dGhlbnRpY2F0aW9uLCBhbmQgYXV0aG9yaXphdGlvblxyXG4gICAgLy8gU2VlIGJmZi9zcmMvaW5kZXgudHMgZm9yIHRoZSBFeHByZXNzIGFwcGxpY2F0aW9uIGltcGxlbWVudGF0aW9uXHJcblxyXG5cclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIEJGRiBBUEkgR2F0ZXdheSAoUHVibGljKVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgdGhpcy5iZmZBcGkgPSBuZXcgYXBpZ2F0ZXdheS5SZXN0QXBpKHRoaXMsICdCZmZBcGknLCB7XHJcbiAgICAgIHJlc3RBcGlOYW1lOiAncmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0JhY2tlbmQtZm9yLUZyb250ZW5kIEFQSSBmb3IgUkRTIERhc2hib2FyZCB3aXRoIEV4cHJlc3MgQkZGJyxcclxuICAgICAgZGVmYXVsdENvcnNQcmVmbGlnaHRPcHRpb25zOiB7XHJcbiAgICAgICAgYWxsb3dPcmlnaW5zOiBwcm9wcy5mcm9udGVuZFVybCA/IFtwcm9wcy5mcm9udGVuZFVybF0gOiBhcGlnYXRld2F5LkNvcnMuQUxMX09SSUdJTlMsXHJcbiAgICAgICAgYWxsb3dNZXRob2RzOiBhcGlnYXRld2F5LkNvcnMuQUxMX01FVEhPRFMsXHJcbiAgICAgICAgYWxsb3dIZWFkZXJzOiBbXHJcbiAgICAgICAgICAnQ29udGVudC1UeXBlJyxcclxuICAgICAgICAgICdYLUFtei1EYXRlJyxcclxuICAgICAgICAgICdBdXRob3JpemF0aW9uJyxcclxuICAgICAgICAgICdYLUFwaS1LZXknLFxyXG4gICAgICAgICAgJ1gtQW16LVNlY3VyaXR5LVRva2VuJyxcclxuICAgICAgICBdLFxyXG4gICAgICAgIGFsbG93Q3JlZGVudGlhbHM6IHRydWUsXHJcbiAgICAgIH0sXHJcbiAgICAgIGRlcGxveU9wdGlvbnM6IHtcclxuICAgICAgICBzdGFnZU5hbWU6ICdwcm9kJyxcclxuICAgICAgICB0aHJvdHRsaW5nUmF0ZUxpbWl0OiAxMDAwLFxyXG4gICAgICAgIHRocm90dGxpbmdCdXJzdExpbWl0OiAyMDAwLFxyXG4gICAgICAgIGxvZ2dpbmdMZXZlbDogYXBpZ2F0ZXdheS5NZXRob2RMb2dnaW5nTGV2ZWwuSU5GTyxcclxuICAgICAgICBkYXRhVHJhY2VFbmFibGVkOiB0cnVlLFxyXG4gICAgICAgIG1ldHJpY3NFbmFibGVkOiB0cnVlLFxyXG4gICAgICB9LFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgLy8gTGFtYmRhIEludGVncmF0aW9uIChObyBBUEkgR2F0ZXdheSBBdXRob3JpemVyKVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgLy8gTm90ZTogQXV0aGVudGljYXRpb24gYW5kIGF1dGhvcml6YXRpb24gYXJlIGhhbmRsZWQgYnkgdGhlIEV4cHJlc3MgQkZGXHJcbiAgICAvLyBUaGUgRXhwcmVzcyBhcHBsaWNhdGlvbiB2YWxpZGF0ZXMgSldUIHRva2VucyBhbmQgZW5mb3JjZXMgUkJBQ1xyXG4gICAgLy8gQVBJIEdhdGV3YXkgc2ltcGx5IHByb3hpZXMgYWxsIHJlcXVlc3RzIHRvIHRoZSBFeHByZXNzIGNvbnRhaW5lclxyXG4gICAgXHJcbiAgICBjb25zdCBsYW1iZGFJbnRlZ3JhdGlvbiA9IG5ldyBhcGlnYXRld2F5LkxhbWJkYUludGVncmF0aW9uKHRoaXMuYmZmRnVuY3Rpb24sIHtcclxuICAgICAgcHJveHk6IHRydWUsXHJcbiAgICAgIGFsbG93VGVzdEludm9rZTogdHJ1ZSxcclxuICAgICAgdGltZW91dDogY2RrLkR1cmF0aW9uLnNlY29uZHMoMjkpLCAvLyBTbGlnaHRseSBsZXNzIHRoYW4gTGFtYmRhIHRpbWVvdXRcclxuICAgIH0pO1xyXG5cclxuICAgIC8vIEFkZCBwcm94eSByZXNvdXJjZSBmb3IgYWxsIHN1Yi1wYXRoczogL3twcm94eSt9XHJcbiAgICAvLyBUaGlzIHdpbGwgaGFuZGxlIC9hcGkvaW5zdGFuY2VzLCAvaGVhbHRoLCAvYXBpL2Nvc3RzLCBldGMuXHJcbiAgICB0aGlzLmJmZkFwaS5yb290LmFkZFByb3h5KHtcclxuICAgICAgZGVmYXVsdEludGVncmF0aW9uOiBsYW1iZGFJbnRlZ3JhdGlvbixcclxuICAgICAgYW55TWV0aG9kOiB0cnVlLCAvLyBBbGxvdyBhbGwgSFRUUCBtZXRob2RzXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBOb3RlOiBObyBDb2duaXRvIGF1dGhvcml6ZXIgYXQgQVBJIEdhdGV3YXkgbGV2ZWxcclxuICAgIC8vIFRoZSBFeHByZXNzIEJGRiBoYW5kbGVzIEpXVCB2YWxpZGF0aW9uIHVzaW5nIGp3a3MtcnNhIGFuZCBqc29ud2VidG9rZW5cclxuICAgIC8vIFRoaXMgcHJvdmlkZXMgbW9yZSBmbGV4aWJpbGl0eSBmb3IgY3VzdG9tIGF1dGhvcml6YXRpb24gbG9naWMgYW5kIFJCQUNcclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBDbG91ZEZvcm1hdGlvbiBPdXRwdXRzXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQmZmQXBpVXJsJywge1xyXG4gICAgICB2YWx1ZTogdGhpcy5iZmZBcGkudXJsLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0JGRiBBUEkgR2F0ZXdheSBVUkwnLFxyXG4gICAgICBleHBvcnROYW1lOiAnQmZmQXBpVXJsJ1xyXG4gICAgfSk7XHJcblxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0JmZkFwaUlkJywge1xyXG4gICAgICB2YWx1ZTogdGhpcy5iZmZBcGkucmVzdEFwaUlkLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0JGRiBBUEkgR2F0ZXdheSBJRCcsXHJcbiAgICAgIGV4cG9ydE5hbWU6ICdCZmZBcGlJZCdcclxuICAgIH0pO1xyXG5cclxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdBcGlTZWNyZXRBcm4nLCB7XHJcbiAgICAgIHZhbHVlOiB0aGlzLmFwaVNlY3JldC5zZWNyZXRBcm4sXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQVBJIFNlY3JldCBBUk4gaW4gU2VjcmV0cyBNYW5hZ2VyJyxcclxuICAgICAgZXhwb3J0TmFtZTogJ0FwaVNlY3JldEFybidcclxuICAgIH0pO1xyXG4gIH1cclxufVxyXG4iXX0=