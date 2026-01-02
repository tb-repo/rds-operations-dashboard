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
        // Import the existing API key from the API stack
        const existingApiKey = apigateway.ApiKey.fromApiKeyId(this, 'ImportedApiKey', props.apiKeyId);
        // Create a custom resource to get the API key value and store it in Secrets Manager
        const apiKeyValueProvider = new cdk.CustomResource(this, 'ApiKeyValueProvider', {
            serviceToken: this.createApiKeyValueProviderFunction().functionArn,
            properties: {
                ApiKeyId: props.apiKeyId,
                SecretName: 'rds-dashboard-api-key',
                ApiUrl: props.internalApiUrl,
            },
        });
        // Reference the secret that will be created by the custom resource
        this.apiSecret = secretsmanager.Secret.fromSecretNameV2(this, 'ApiSecret', 'rds-dashboard-api-key');
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
                stageName: '$default',
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
    /**
     * Creates a Lambda function that retrieves the API key value and stores it in Secrets Manager
     */
    createApiKeyValueProviderFunction() {
        return new lambda.Function(this, 'ApiKeyValueProviderFunction', {
            functionName: 'rds-dashboard-api-key-provider',
            runtime: lambda.Runtime.PYTHON_3_11,
            handler: 'index.handler',
            timeout: cdk.Duration.minutes(5),
            code: lambda.Code.fromInline(`
import json
import boto3
import cfnresponse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Custom resource handler that:
    1. Gets the API key value from API Gateway
    2. Stores it in Secrets Manager with proper JSON format
    3. Handles CREATE, UPDATE, and DELETE events
    """
    
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        api_key_id = properties['ApiKeyId']
        secret_name = properties['SecretName']
        api_url = properties['ApiUrl']
        
        apigateway_client = boto3.client('apigateway')
        secrets_client = boto3.client('secretsmanager')
        
        if request_type in ['Create', 'Update']:
            # Get the API key value from API Gateway
            logger.info(f"Getting API key value for key ID: {api_key_id}")
            
            response = apigateway_client.get_api_key(
                apiKeyId=api_key_id,
                includeValue=True
            )
            
            api_key_value = response['value']
            logger.info(f"Retrieved API key value (length: {len(api_key_value)})")
            
            # Create the secret value in proper JSON format
            secret_value = {
                "apiKey": api_key_value,
                "apiUrl": api_url,
                "description": "RDS Dashboard API credentials - Auto-generated",
                "createdBy": "CDK-CustomResource",
                "lastUpdated": context.aws_request_id
            }
            
            # Store in Secrets Manager
            try:
                # Try to update existing secret first
                secrets_client.update_secret(
                    SecretId=secret_name,
                    SecretString=json.dumps(secret_value),
                    Description=f"API Gateway key for RDS Dashboard internal API - Auto-managed"
                )
                logger.info(f"Updated existing secret: {secret_name}")
                
            except secrets_client.exceptions.ResourceNotFoundException:
                # Create new secret if it doesn't exist
                secrets_client.create_secret(
                    Name=secret_name,
                    SecretString=json.dumps(secret_value),
                    Description=f"API Gateway key for RDS Dashboard internal API - Auto-managed"
                )
                logger.info(f"Created new secret: {secret_name}")
            
            # Return success
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'SecretName': secret_name,
                'ApiKeyId': api_key_id,
                'Message': f'Successfully stored API key in Secrets Manager'
            })
            
        elif request_type == 'Delete':
            # Optionally delete the secret (commented out for safety)
            # secrets_client.delete_secret(SecretId=secret_name, ForceDeleteWithoutRecovery=True)
            logger.info(f"Delete requested for secret: {secret_name} (skipped for safety)")
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': 'Delete completed (secret preserved for safety)'
            })
            
    except Exception as e:
        logger.error(f"Error in API key provider: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {
            'Error': str(e)
        })
`),
            role: this.createApiKeyProviderRole(),
            description: 'Custom resource to retrieve API key value and store in Secrets Manager',
        });
    }
    /**
     * Creates IAM role for the API key provider function
     */
    createApiKeyProviderRole() {
        const role = new iam.Role(this, 'ApiKeyProviderRole', {
            assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
            description: 'IAM role for API key provider custom resource',
            managedPolicies: [
                iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
            ],
        });
        // Grant permission to read API key values
        role.addToPolicy(new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
                'apigateway:GET',
            ],
            resources: [
                `arn:aws:apigateway:${this.region}::/apikeys/*`,
            ],
        }));
        // Grant permission to manage secrets
        role.addToPolicy(new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
                'secretsmanager:CreateSecret',
                'secretsmanager:UpdateSecret',
                'secretsmanager:DeleteSecret',
                'secretsmanager:GetSecretValue',
                'secretsmanager:DescribeSecret',
            ],
            resources: [
                `arn:aws:secretsmanager:${this.region}:${this.account}:secret:rds-dashboard-api-key*`,
            ],
        }));
        return role;
    }
}
exports.BffStack = BffStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYmZmLXN0YWNrLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiYmZmLXN0YWNrLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7QUFBQTs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0dBd0JHOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7QUFFSCxpREFBbUM7QUFDbkMsK0RBQWlEO0FBQ2pELHVFQUF5RDtBQUN6RCwrRUFBaUU7QUFDakUseURBQTJDO0FBQzNDLDJEQUE2QztBQUU3QywyQ0FBNkI7QUFVN0IsTUFBYSxRQUFTLFNBQVEsR0FBRyxDQUFDLEtBQUs7SUFLckMsWUFBWSxLQUFnQixFQUFFLEVBQVUsRUFBRSxLQUFvQjtRQUM1RCxLQUFLLENBQUMsS0FBSyxFQUFFLEVBQUUsRUFBRSxLQUFLLENBQUMsQ0FBQztRQUV4QiwyQ0FBMkM7UUFDM0Msa0NBQWtDO1FBQ2xDLDJDQUEyQztRQUUzQyxpREFBaUQ7UUFDakQsTUFBTSxjQUFjLEdBQUcsVUFBVSxDQUFDLE1BQU0sQ0FBQyxZQUFZLENBQUMsSUFBSSxFQUFFLGdCQUFnQixFQUFFLEtBQUssQ0FBQyxRQUFRLENBQUMsQ0FBQztRQUU5RixvRkFBb0Y7UUFDcEYsTUFBTSxtQkFBbUIsR0FBRyxJQUFJLEdBQUcsQ0FBQyxjQUFjLENBQUMsSUFBSSxFQUFFLHFCQUFxQixFQUFFO1lBQzlFLFlBQVksRUFBRSxJQUFJLENBQUMsaUNBQWlDLEVBQUUsQ0FBQyxXQUFXO1lBQ2xFLFVBQVUsRUFBRTtnQkFDVixRQUFRLEVBQUUsS0FBSyxDQUFDLFFBQVE7Z0JBQ3hCLFVBQVUsRUFBRSx1QkFBdUI7Z0JBQ25DLE1BQU0sRUFBRSxLQUFLLENBQUMsY0FBYzthQUM3QjtTQUNGLENBQUMsQ0FBQztRQUVILG1FQUFtRTtRQUNuRSxJQUFJLENBQUMsU0FBUyxHQUFHLGNBQWMsQ0FBQyxNQUFNLENBQUMsZ0JBQWdCLENBQUMsSUFBSSxFQUFFLFdBQVcsRUFBRSx1QkFBdUIsQ0FBMEIsQ0FBQztR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Q3ZDLE1BQU0sRUFBRSxHQUFHLENBQUMsTUFBTSxDQUFDLEtBQUs7WUFDeEIsT0FBTyxFQUFFO2dCQUNQLDZCQUE2QjtnQkFDN0IsNkJBQTZCO2dCQUM3Qiw2QkFBNkI7Z0JBQzdCLCtCQUErQjtnQkFDL0IsK0JBQStCO2FBQ2hDO1lBQ0QsU0FBUyxFQUFFO2dCQUNULDBCQUEwQixJQUFJLENBQUMsTUFBTSxJQUFJLElBQUksQ0FBQyxPQUFPLGdDQUFnQzthQUN0RjtTQUNGLENBQUMsQ0FBQyxDQUFDO1FBRUosT0FBTyxJQUFJLENBQUM7SUFDZCxDQUFDO0NBQ0Y7QUE3VUQsNEJBNlVDIiwic291cmNlc0NvbnRlbnQiOlsiLyoqXHJcbiAqIEJGRiBTdGFjayAtIEJhY2tlbmQtZm9yLUZyb250ZW5kIHdpdGggRXhwcmVzcyBDb250YWluZXJcclxuICogXHJcbiAqIFRoaXMgc3RhY2sgZGVwbG95cyB0aGUgRXhwcmVzcyBCRkYgYXBwbGljYXRpb24gYXMgYSBMYW1iZGEgY29udGFpbmVyLlxyXG4gKiBUaGUgRXhwcmVzcyBhcHBsaWNhdGlvbiBoYW5kbGVzIEpXVCB2YWxpZGF0aW9uLCBSQkFDLCBhbmQgYXVkaXQgbG9nZ2luZy5cclxuICogXHJcbiAqIEFyY2hpdGVjdHVyZSBEZWNpc2lvbjpcclxuICogLSBVc2VzIERvY2tlckltYWdlRnVuY3Rpb24gdG8gZGVwbG95IEV4cHJlc3MgYXBwbGljYXRpb25cclxuICogLSBBdXRoZW50aWNhdGlvbiBoYW5kbGVkIGJ5IEV4cHJlc3MgbWlkZGxld2FyZSAobm90IEFQSSBHYXRld2F5IGF1dGhvcml6ZXIpXHJcbiAqIC0gUHJvdmlkZXMgZmxleGliaWxpdHkgZm9yIGN1c3RvbSBhdXRob3JpemF0aW9uIGxvZ2ljIGFuZCBSQkFDXHJcbiAqIC0gU3VwcG9ydHMgc29waGlzdGljYXRlZCBhdWRpdCBsb2dnaW5nIGFuZCByZXF1ZXN0IHRyYWNraW5nXHJcbiAqIFxyXG4gKiBNZXRhZGF0YTpcclxuICoge1xyXG4gKiAgIFwiZ2VuZXJhdGVkX2J5XCI6IFwiY2xhdWRlLTMuNS1zb25uZXRcIixcclxuICogICBcInRpbWVzdGFtcFwiOiBcIjIwMjUtMTItMDFUMTA6MDA6MDBaXCIsXHJcbiAqICAgXCJ2ZXJzaW9uXCI6IFwiMi4wLjBcIixcclxuICogICBcInBvbGljeV92ZXJzaW9uXCI6IFwidjEuMC4wXCIsXHJcbiAqICAgXCJ0cmFjZWFiaWxpdHlcIjogXCJSRVEtMS4xLCBSRVEtMS40IOKGkiBERVNJR04tQkZGLUNvbnRhaW5lciDihpIgVEFTSy0xLjJcIixcclxuICogICBcInJldmlld19zdGF0dXNcIjogXCJQZW5kaW5nXCIsXHJcbiAqICAgXCJyaXNrX2xldmVsXCI6IFwiTGV2ZWwgMlwiLFxyXG4gKiAgIFwicmV2aWV3ZWRfYnlcIjogbnVsbCxcclxuICogICBcImFwcHJvdmVkX2J5XCI6IG51bGxcclxuICogfVxyXG4gKi9cclxuXHJcbmltcG9ydCAqIGFzIGNkayBmcm9tICdhd3MtY2RrLWxpYic7XHJcbmltcG9ydCAqIGFzIGxhbWJkYSBmcm9tICdhd3MtY2RrLWxpYi9hd3MtbGFtYmRhJztcclxuaW1wb3J0ICogYXMgYXBpZ2F0ZXdheSBmcm9tICdhd3MtY2RrLWxpYi9hd3MtYXBpZ2F0ZXdheSc7XHJcbmltcG9ydCAqIGFzIHNlY3JldHNtYW5hZ2VyIGZyb20gJ2F3cy1jZGstbGliL2F3cy1zZWNyZXRzbWFuYWdlcic7XHJcbmltcG9ydCAqIGFzIGlhbSBmcm9tICdhd3MtY2RrLWxpYi9hd3MtaWFtJztcclxuaW1wb3J0ICogYXMgbG9ncyBmcm9tICdhd3MtY2RrLWxpYi9hd3MtbG9ncyc7XHJcbmltcG9ydCB7IENvbnN0cnVjdCB9IGZyb20gJ2NvbnN0cnVjdHMnO1xyXG5pbXBvcnQgKiBhcyBwYXRoIGZyb20gJ3BhdGgnO1xyXG5cclxuZXhwb3J0IGludGVyZmFjZSBCZmZTdGFja1Byb3BzIGV4dGVuZHMgY2RrLlN0YWNrUHJvcHMge1xyXG4gIGludGVybmFsQXBpVXJsOiBzdHJpbmc7XHJcbiAgYXBpS2V5SWQ6IHN0cmluZztcclxuICB1c2VyUG9vbElkPzogc3RyaW5nO1xyXG4gIHVzZXJQb29sQ2xpZW50SWQ/OiBzdHJpbmc7XHJcbiAgZnJvbnRlbmRVcmw/OiBzdHJpbmc7XHJcbn1cclxuXHJcbmV4cG9ydCBjbGFzcyBCZmZTdGFjayBleHRlbmRzIGNkay5TdGFjayB7XHJcbiAgcHVibGljIHJlYWRvbmx5IGJmZkFwaTogYXBpZ2F0ZXdheS5SZXN0QXBpO1xyXG4gIHB1YmxpYyByZWFkb25seSBiZmZGdW5jdGlvbjogbGFtYmRhLkRvY2tlckltYWdlRnVuY3Rpb247XHJcbiAgcHVibGljIHJlYWRvbmx5IGFwaVNlY3JldDogc2VjcmV0c21hbmFnZXIuU2VjcmV0O1xyXG5cclxuICBjb25zdHJ1Y3RvcihzY29wZTogQ29uc3RydWN0LCBpZDogc3RyaW5nLCBwcm9wczogQmZmU3RhY2tQcm9wcykge1xyXG4gICAgc3VwZXIoc2NvcGUsIGlkLCBwcm9wcyk7XHJcblxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgLy8gU2VjcmV0cyBNYW5hZ2VyIC0gU3RvcmUgQVBJIEtleVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgXHJcbiAgICAvLyBJbXBvcnQgdGhlIGV4aXN0aW5nIEFQSSBrZXkgZnJvbSB0aGUgQVBJIHN0YWNrXHJcbiAgICBjb25zdCBleGlzdGluZ0FwaUtleSA9IGFwaWdhdGV3YXkuQXBpS2V5LmZyb21BcGlLZXlJZCh0aGlzLCAnSW1wb3J0ZWRBcGlLZXknLCBwcm9wcy5hcGlLZXlJZCk7XHJcbiAgICBcclxuICAgIC8vIENyZWF0ZSBhIGN1c3RvbSByZXNvdXJjZSB0byBnZXQgdGhlIEFQSSBrZXkgdmFsdWUgYW5kIHN0b3JlIGl0IGluIFNlY3JldHMgTWFuYWdlclxyXG4gICAgY29uc3QgYXBpS2V5VmFsdWVQcm92aWRlciA9IG5ldyBjZGsuQ3VzdG9tUmVzb3VyY2UodGhpcywgJ0FwaUtleVZhbHVlUHJvdmlkZXInLCB7XHJcbiAgICAgIHNlcnZpY2VUb2tlbjogdGhpcy5jcmVhdGVBcGlLZXlWYWx1ZVByb3ZpZGVyRnVuY3Rpb24oKS5mdW5jdGlvbkFybixcclxuICAgICAgcHJvcGVydGllczoge1xyXG4gICAgICAgIEFwaUtleUlkOiBwcm9wcy5hcGlLZXlJZCxcclxuICAgICAgICBTZWNyZXROYW1lOiAncmRzLWRhc2hib2FyZC1hcGkta2V5JyxcclxuICAgICAgICBBcGlVcmw6IHByb3BzLmludGVybmFsQXBpVXJsLFxyXG4gICAgICB9LFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gUmVmZXJlbmNlIHRoZSBzZWNyZXQgdGhhdCB3aWxsIGJlIGNyZWF0ZWQgYnkgdGhlIGN1c3RvbSByZXNvdXJjZVxyXG4gICAgdGhpcy5hcGlTZWNyZXQgPSBzZWNyZXRzbWFuYWdlci5TZWNyZXQuZnJvbVNlY3JldE5hbWVWMih0aGlzLCAnQXBpU2VjcmV0JywgJ3Jkcy1kYXNoYm9hcmQtYXBpLWtleScpIGFzIHNlY3JldHNtYW5hZ2VyLlNlY3JldDtcclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBJQU0gUm9sZSBmb3IgQkZGIExhbWJkYVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgY29uc3QgYmZmUm9sZSA9IG5ldyBpYW0uUm9sZSh0aGlzLCAnQmZmTGFtYmRhUm9sZScsIHtcclxuICAgICAgYXNzdW1lZEJ5OiBuZXcgaWFtLlNlcnZpY2VQcmluY2lwYWwoJ2xhbWJkYS5hbWF6b25hd3MuY29tJyksXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnSUFNIHJvbGUgZm9yIFJEUyBEYXNoYm9hcmQgQkZGIExhbWJkYSBmdW5jdGlvbicsXHJcbiAgICAgIG1hbmFnZWRQb2xpY2llczogW1xyXG4gICAgICAgIGlhbS5NYW5hZ2VkUG9saWN5LmZyb21Bd3NNYW5hZ2VkUG9saWN5TmFtZSgnc2VydmljZS1yb2xlL0FXU0xhbWJkYUJhc2ljRXhlY3V0aW9uUm9sZScpLFxyXG4gICAgICBdLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gR3JhbnQgcGVybWlzc2lvbiB0byByZWFkIHRoZSBBUEkgc2VjcmV0XHJcbiAgICB0aGlzLmFwaVNlY3JldC5ncmFudFJlYWQoYmZmUm9sZSk7XHJcblxyXG4gICAgLy8gR3JhbnQgcGVybWlzc2lvbiB0byByZWFkIENvZ25pdG8gVXNlciBQb29sIChmb3IgSldUIHZhbGlkYXRpb24pXHJcbiAgICBpZiAocHJvcHMudXNlclBvb2xJZCkge1xyXG4gICAgICBiZmZSb2xlLmFkZFRvUG9saWN5KG5ldyBpYW0uUG9saWN5U3RhdGVtZW50KHtcclxuICAgICAgICBlZmZlY3Q6IGlhbS5FZmZlY3QuQUxMT1csXHJcbiAgICAgICAgYWN0aW9uczogW1xyXG4gICAgICAgICAgJ2NvZ25pdG8taWRwOkdldFVzZXInLFxyXG4gICAgICAgICAgJ2NvZ25pdG8taWRwOkxpc3RVc2VycycsXHJcbiAgICAgICAgICAnY29nbml0by1pZHA6QWRtaW5HZXRVc2VyJyxcclxuICAgICAgICAgICdjb2duaXRvLWlkcDpBZG1pbkxpc3RHcm91cHNGb3JVc2VyJyxcclxuICAgICAgICBdLFxyXG4gICAgICAgIHJlc291cmNlczogW1xyXG4gICAgICAgICAgYGFybjphd3M6Y29nbml0by1pZHA6JHt0aGlzLnJlZ2lvbn06JHt0aGlzLmFjY291bnR9OnVzZXJwb29sLyR7cHJvcHMudXNlclBvb2xJZH1gLFxyXG4gICAgICAgIF0sXHJcbiAgICAgIH0pKTtcclxuICAgIH1cclxuXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICAvLyBDbG91ZFdhdGNoIExvZyBHcm91cCBmb3IgQkZGXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICBjb25zdCBsb2dHcm91cCA9IG5ldyBsb2dzLkxvZ0dyb3VwKHRoaXMsICdCZmZMb2dHcm91cCcsIHtcclxuICAgICAgbG9nR3JvdXBOYW1lOiAnL2F3cy9sYW1iZGEvcmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICByZXRlbnRpb246IGxvZ3MuUmV0ZW50aW9uRGF5cy5PTkVfV0VFSyxcclxuICAgICAgcmVtb3ZhbFBvbGljeTogY2RrLlJlbW92YWxQb2xpY3kuREVTVFJPWSxcclxuICAgIH0pO1xyXG5cclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIEJGRiBMYW1iZGEgRnVuY3Rpb24gKERvY2tlciBDb250YWluZXIpXHJcbiAgICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09XHJcbiAgICB0aGlzLmJmZkZ1bmN0aW9uID0gbmV3IGxhbWJkYS5Eb2NrZXJJbWFnZUZ1bmN0aW9uKHRoaXMsICdCZmZGdW5jdGlvbicsIHtcclxuICAgICAgZnVuY3Rpb25OYW1lOiAncmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICBjb2RlOiBsYW1iZGEuRG9ja2VySW1hZ2VDb2RlLmZyb21JbWFnZUFzc2V0KHBhdGguam9pbihfX2Rpcm5hbWUsICcuLi8uLi9iZmYnKSwge1xyXG4gICAgICAgIGZpbGU6ICdEb2NrZXJmaWxlJyxcclxuICAgICAgfSksXHJcbiAgICAgIHRpbWVvdXQ6IGNkay5EdXJhdGlvbi5zZWNvbmRzKDMwKSxcclxuICAgICAgbWVtb3J5U2l6ZTogMTAyNCxcclxuICAgICAgcm9sZTogYmZmUm9sZSxcclxuICAgICAgbG9nR3JvdXA6IGxvZ0dyb3VwLFxyXG4gICAgICBlbnZpcm9ubWVudDoge1xyXG4gICAgICAgIC8vIENvZ25pdG8gQ29uZmlndXJhdGlvblxyXG4gICAgICAgIENPR05JVE9fVVNFUl9QT09MX0lEOiBwcm9wcy51c2VyUG9vbElkIHx8ICcnLFxyXG4gICAgICAgIENPR05JVE9fUkVHSU9OOiB0aGlzLnJlZ2lvbixcclxuICAgICAgICBDT0dOSVRPX0NMSUVOVF9JRDogcHJvcHMudXNlclBvb2xDbGllbnRJZCB8fCAnJyxcclxuICAgICAgICBcclxuICAgICAgICAvLyBJbnRlcm5hbCBBUEkgQ29uZmlndXJhdGlvblxyXG4gICAgICAgIElOVEVSTkFMX0FQSV9VUkw6IHByb3BzLmludGVybmFsQXBpVXJsLFxyXG4gICAgICAgIElOVEVSTkFMX0FQSV9LRVk6ICcnLCAvLyBXaWxsIGJlIHBvcHVsYXRlZCBmcm9tIFNlY3JldHMgTWFuYWdlciBhdCBydW50aW1lXHJcbiAgICAgICAgQVBJX1NFQ1JFVF9BUk46IHRoaXMuYXBpU2VjcmV0LnNlY3JldEFybixcclxuICAgICAgICBcclxuICAgICAgICAvLyBGcm9udGVuZCBDb25maWd1cmF0aW9uXHJcbiAgICAgICAgRlJPTlRFTkRfVVJMOiBwcm9wcy5mcm9udGVuZFVybCB8fCAnKicsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gU2VydmVyIENvbmZpZ3VyYXRpb25cclxuICAgICAgICBQT1JUOiAnODA4MCcsIC8vIExhbWJkYSB1c2VzIHBvcnQgODA4MCBmb3IgY29udGFpbmVyIGltYWdlc1xyXG4gICAgICAgIE5PREVfRU5WOiAncHJvZHVjdGlvbicsXHJcbiAgICAgICAgTE9HX0xFVkVMOiAnaW5mbycsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gQXVkaXQgTG9nZ2luZ1xyXG4gICAgICAgIEFVRElUX0xPR19HUk9VUDogJy9hd3MvcmRzLWRhc2hib2FyZC9hdWRpdCcsXHJcbiAgICAgICAgRU5BQkxFX0FVRElUX0xPR0dJTkc6ICd0cnVlJyxcclxuICAgICAgICBcclxuICAgICAgICAvLyBBV1MgQ29uZmlndXJhdGlvblxyXG4gICAgICAgIEFXU19OT0RFSlNfQ09OTkVDVElPTl9SRVVTRV9FTkFCTEVEOiAnMScsXHJcbiAgICAgICAgXHJcbiAgICAgICAgLy8gRm9yY2UgcmVidWlsZFxyXG4gICAgICAgIEJVSUxEX1ZFUlNJT046ICcxLjAuMScsXHJcbiAgICAgIH0sXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQmFja2VuZC1mb3ItRnJvbnRlbmQgRXhwcmVzcyBzZXJ2aWNlIGZvciBSRFMgRGFzaGJvYXJkIHdpdGggSldUIHZhbGlkYXRpb24gYW5kIFJCQUMnLFxyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gTm90ZTogVGhlIG9sZCBpbmxpbmUgTGFtYmRhIGNvZGUgaGFzIGJlZW4gcmVwbGFjZWQgd2l0aCBEb2NrZXJJbWFnZUZ1bmN0aW9uXHJcbiAgICAvLyBUaGUgRXhwcmVzcyBCRkYgYXBwbGljYXRpb24gd2lsbCBoYW5kbGUgYWxsIHJvdXRpbmcsIGF1dGhlbnRpY2F0aW9uLCBhbmQgYXV0aG9yaXphdGlvblxyXG4gICAgLy8gU2VlIGJmZi9zcmMvaW5kZXgudHMgZm9yIHRoZSBFeHByZXNzIGFwcGxpY2F0aW9uIGltcGxlbWVudGF0aW9uXHJcblxyXG5cclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIEJGRiBBUEkgR2F0ZXdheSAoUHVibGljKVxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgdGhpcy5iZmZBcGkgPSBuZXcgYXBpZ2F0ZXdheS5SZXN0QXBpKHRoaXMsICdCZmZBcGknLCB7XHJcbiAgICAgIHJlc3RBcGlOYW1lOiAncmRzLWRhc2hib2FyZC1iZmYnLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0JhY2tlbmQtZm9yLUZyb250ZW5kIEFQSSBmb3IgUkRTIERhc2hib2FyZCB3aXRoIEV4cHJlc3MgQkZGJyxcclxuICAgICAgZGVmYXVsdENvcnNQcmVmbGlnaHRPcHRpb25zOiB7XHJcbiAgICAgICAgYWxsb3dPcmlnaW5zOiBwcm9wcy5mcm9udGVuZFVybCA/IFtwcm9wcy5mcm9udGVuZFVybF0gOiBhcGlnYXRld2F5LkNvcnMuQUxMX09SSUdJTlMsXHJcbiAgICAgICAgYWxsb3dNZXRob2RzOiBhcGlnYXRld2F5LkNvcnMuQUxMX01FVEhPRFMsXHJcbiAgICAgICAgYWxsb3dIZWFkZXJzOiBbXHJcbiAgICAgICAgICAnQ29udGVudC1UeXBlJyxcclxuICAgICAgICAgICdYLUFtei1EYXRlJyxcclxuICAgICAgICAgICdBdXRob3JpemF0aW9uJyxcclxuICAgICAgICAgICdYLUFwaS1LZXknLFxyXG4gICAgICAgICAgJ1gtQW16LVNlY3VyaXR5LVRva2VuJyxcclxuICAgICAgICBdLFxyXG4gICAgICAgIGFsbG93Q3JlZGVudGlhbHM6IHRydWUsXHJcbiAgICAgIH0sXHJcbiAgICAgIGRlcGxveU9wdGlvbnM6IHtcclxuICAgICAgICBzdGFnZU5hbWU6ICckZGVmYXVsdCcsXHJcbiAgICAgICAgdGhyb3R0bGluZ1JhdGVMaW1pdDogMTAwMCxcclxuICAgICAgICB0aHJvdHRsaW5nQnVyc3RMaW1pdDogMjAwMCxcclxuICAgICAgICBsb2dnaW5nTGV2ZWw6IGFwaWdhdGV3YXkuTWV0aG9kTG9nZ2luZ0xldmVsLklORk8sXHJcbiAgICAgICAgZGF0YVRyYWNlRW5hYmxlZDogdHJ1ZSxcclxuICAgICAgICBtZXRyaWNzRW5hYmxlZDogdHJ1ZSxcclxuICAgICAgfSxcclxuICAgIH0pO1xyXG5cclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIExhbWJkYSBJbnRlZ3JhdGlvbiAoTm8gQVBJIEdhdGV3YXkgQXV0aG9yaXplcilcclxuICAgIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1cclxuICAgIC8vIE5vdGU6IEF1dGhlbnRpY2F0aW9uIGFuZCBhdXRob3JpemF0aW9uIGFyZSBoYW5kbGVkIGJ5IHRoZSBFeHByZXNzIEJGRlxyXG4gICAgLy8gVGhlIEV4cHJlc3MgYXBwbGljYXRpb24gdmFsaWRhdGVzIEpXVCB0b2tlbnMgYW5kIGVuZm9yY2VzIFJCQUNcclxuICAgIC8vIEFQSSBHYXRld2F5IHNpbXBseSBwcm94aWVzIGFsbCByZXF1ZXN0cyB0byB0aGUgRXhwcmVzcyBjb250YWluZXJcclxuICAgIFxyXG4gICAgY29uc3QgbGFtYmRhSW50ZWdyYXRpb24gPSBuZXcgYXBpZ2F0ZXdheS5MYW1iZGFJbnRlZ3JhdGlvbih0aGlzLmJmZkZ1bmN0aW9uLCB7XHJcbiAgICAgIHByb3h5OiB0cnVlLFxyXG4gICAgICBhbGxvd1Rlc3RJbnZva2U6IHRydWUsXHJcbiAgICAgIHRpbWVvdXQ6IGNkay5EdXJhdGlvbi5zZWNvbmRzKDI5KSwgLy8gU2xpZ2h0bHkgbGVzcyB0aGFuIExhbWJkYSB0aW1lb3V0XHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBBZGQgcHJveHkgcmVzb3VyY2UgZm9yIGFsbCBzdWItcGF0aHM6IC97cHJveHkrfVxyXG4gICAgLy8gVGhpcyB3aWxsIGhhbmRsZSAvYXBpL2luc3RhbmNlcywgL2hlYWx0aCwgL2FwaS9jb3N0cywgZXRjLlxyXG4gICAgdGhpcy5iZmZBcGkucm9vdC5hZGRQcm94eSh7XHJcbiAgICAgIGRlZmF1bHRJbnRlZ3JhdGlvbjogbGFtYmRhSW50ZWdyYXRpb24sXHJcbiAgICAgIGFueU1ldGhvZDogdHJ1ZSwgLy8gQWxsb3cgYWxsIEhUVFAgbWV0aG9kc1xyXG4gICAgfSk7XHJcblxyXG4gICAgLy8gTm90ZTogTm8gQ29nbml0byBhdXRob3JpemVyIGF0IEFQSSBHYXRld2F5IGxldmVsXHJcbiAgICAvLyBUaGUgRXhwcmVzcyBCRkYgaGFuZGxlcyBKV1QgdmFsaWRhdGlvbiB1c2luZyBqd2tzLXJzYSBhbmQganNvbndlYnRva2VuXHJcbiAgICAvLyBUaGlzIHByb3ZpZGVzIG1vcmUgZmxleGliaWxpdHkgZm9yIGN1c3RvbSBhdXRob3JpemF0aW9uIGxvZ2ljIGFuZCBSQkFDXHJcblxyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgLy8gQ2xvdWRGb3JtYXRpb24gT3V0cHV0c1xyXG4gICAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0JmZkFwaVVybCcsIHtcclxuICAgICAgdmFsdWU6IHRoaXMuYmZmQXBpLnVybCxcclxuICAgICAgZGVzY3JpcHRpb246ICdCRkYgQVBJIEdhdGV3YXkgVVJMJyxcclxuICAgICAgZXhwb3J0TmFtZTogJ0JmZkFwaVVybCdcclxuICAgIH0pO1xyXG5cclxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdCZmZBcGlJZCcsIHtcclxuICAgICAgdmFsdWU6IHRoaXMuYmZmQXBpLnJlc3RBcGlJZCxcclxuICAgICAgZGVzY3JpcHRpb246ICdCRkYgQVBJIEdhdGV3YXkgSUQnLFxyXG4gICAgICBleHBvcnROYW1lOiAnQmZmQXBpSWQnXHJcbiAgICB9KTtcclxuXHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQXBpU2VjcmV0QXJuJywge1xyXG4gICAgICB2YWx1ZTogdGhpcy5hcGlTZWNyZXQuc2VjcmV0QXJuLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0FQSSBTZWNyZXQgQVJOIGluIFNlY3JldHMgTWFuYWdlcicsXHJcbiAgICAgIGV4cG9ydE5hbWU6ICdBcGlTZWNyZXRBcm4nXHJcbiAgICB9KTtcclxuICB9XHJcblxyXG4gIC8qKlxyXG4gICAqIENyZWF0ZXMgYSBMYW1iZGEgZnVuY3Rpb24gdGhhdCByZXRyaWV2ZXMgdGhlIEFQSSBrZXkgdmFsdWUgYW5kIHN0b3JlcyBpdCBpbiBTZWNyZXRzIE1hbmFnZXJcclxuICAgKi9cclxuICBwcml2YXRlIGNyZWF0ZUFwaUtleVZhbHVlUHJvdmlkZXJGdW5jdGlvbigpOiBsYW1iZGEuRnVuY3Rpb24ge1xyXG4gICAgcmV0dXJuIG5ldyBsYW1iZGEuRnVuY3Rpb24odGhpcywgJ0FwaUtleVZhbHVlUHJvdmlkZXJGdW5jdGlvbicsIHtcclxuICAgICAgZnVuY3Rpb25OYW1lOiAncmRzLWRhc2hib2FyZC1hcGkta2V5LXByb3ZpZGVyJyxcclxuICAgICAgcnVudGltZTogbGFtYmRhLlJ1bnRpbWUuUFlUSE9OXzNfMTEsXHJcbiAgICAgIGhhbmRsZXI6ICdpbmRleC5oYW5kbGVyJyxcclxuICAgICAgdGltZW91dDogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXHJcbiAgICAgIGNvZGU6IGxhbWJkYS5Db2RlLmZyb21JbmxpbmUoYFxyXG5pbXBvcnQganNvblxyXG5pbXBvcnQgYm90bzNcclxuaW1wb3J0IGNmbnJlc3BvbnNlXHJcbmltcG9ydCBsb2dnaW5nXHJcblxyXG5sb2dnZXIgPSBsb2dnaW5nLmdldExvZ2dlcigpXHJcbmxvZ2dlci5zZXRMZXZlbChsb2dnaW5nLklORk8pXHJcblxyXG5kZWYgaGFuZGxlcihldmVudCwgY29udGV4dCk6XHJcbiAgICBcIlwiXCJcclxuICAgIEN1c3RvbSByZXNvdXJjZSBoYW5kbGVyIHRoYXQ6XHJcbiAgICAxLiBHZXRzIHRoZSBBUEkga2V5IHZhbHVlIGZyb20gQVBJIEdhdGV3YXlcclxuICAgIDIuIFN0b3JlcyBpdCBpbiBTZWNyZXRzIE1hbmFnZXIgd2l0aCBwcm9wZXIgSlNPTiBmb3JtYXRcclxuICAgIDMuIEhhbmRsZXMgQ1JFQVRFLCBVUERBVEUsIGFuZCBERUxFVEUgZXZlbnRzXHJcbiAgICBcIlwiXCJcclxuICAgIFxyXG4gICAgdHJ5OlxyXG4gICAgICAgIHJlcXVlc3RfdHlwZSA9IGV2ZW50WydSZXF1ZXN0VHlwZSddXHJcbiAgICAgICAgcHJvcGVydGllcyA9IGV2ZW50WydSZXNvdXJjZVByb3BlcnRpZXMnXVxyXG4gICAgICAgIGFwaV9rZXlfaWQgPSBwcm9wZXJ0aWVzWydBcGlLZXlJZCddXHJcbiAgICAgICAgc2VjcmV0X25hbWUgPSBwcm9wZXJ0aWVzWydTZWNyZXROYW1lJ11cclxuICAgICAgICBhcGlfdXJsID0gcHJvcGVydGllc1snQXBpVXJsJ11cclxuICAgICAgICBcclxuICAgICAgICBhcGlnYXRld2F5X2NsaWVudCA9IGJvdG8zLmNsaWVudCgnYXBpZ2F0ZXdheScpXHJcbiAgICAgICAgc2VjcmV0c19jbGllbnQgPSBib3RvMy5jbGllbnQoJ3NlY3JldHNtYW5hZ2VyJylcclxuICAgICAgICBcclxuICAgICAgICBpZiByZXF1ZXN0X3R5cGUgaW4gWydDcmVhdGUnLCAnVXBkYXRlJ106XHJcbiAgICAgICAgICAgICMgR2V0IHRoZSBBUEkga2V5IHZhbHVlIGZyb20gQVBJIEdhdGV3YXlcclxuICAgICAgICAgICAgbG9nZ2VyLmluZm8oZlwiR2V0dGluZyBBUEkga2V5IHZhbHVlIGZvciBrZXkgSUQ6IHthcGlfa2V5X2lkfVwiKVxyXG4gICAgICAgICAgICBcclxuICAgICAgICAgICAgcmVzcG9uc2UgPSBhcGlnYXRld2F5X2NsaWVudC5nZXRfYXBpX2tleShcclxuICAgICAgICAgICAgICAgIGFwaUtleUlkPWFwaV9rZXlfaWQsXHJcbiAgICAgICAgICAgICAgICBpbmNsdWRlVmFsdWU9VHJ1ZVxyXG4gICAgICAgICAgICApXHJcbiAgICAgICAgICAgIFxyXG4gICAgICAgICAgICBhcGlfa2V5X3ZhbHVlID0gcmVzcG9uc2VbJ3ZhbHVlJ11cclxuICAgICAgICAgICAgbG9nZ2VyLmluZm8oZlwiUmV0cmlldmVkIEFQSSBrZXkgdmFsdWUgKGxlbmd0aDoge2xlbihhcGlfa2V5X3ZhbHVlKX0pXCIpXHJcbiAgICAgICAgICAgIFxyXG4gICAgICAgICAgICAjIENyZWF0ZSB0aGUgc2VjcmV0IHZhbHVlIGluIHByb3BlciBKU09OIGZvcm1hdFxyXG4gICAgICAgICAgICBzZWNyZXRfdmFsdWUgPSB7XHJcbiAgICAgICAgICAgICAgICBcImFwaUtleVwiOiBhcGlfa2V5X3ZhbHVlLFxyXG4gICAgICAgICAgICAgICAgXCJhcGlVcmxcIjogYXBpX3VybCxcclxuICAgICAgICAgICAgICAgIFwiZGVzY3JpcHRpb25cIjogXCJSRFMgRGFzaGJvYXJkIEFQSSBjcmVkZW50aWFscyAtIEF1dG8tZ2VuZXJhdGVkXCIsXHJcbiAgICAgICAgICAgICAgICBcImNyZWF0ZWRCeVwiOiBcIkNESy1DdXN0b21SZXNvdXJjZVwiLFxyXG4gICAgICAgICAgICAgICAgXCJsYXN0VXBkYXRlZFwiOiBjb250ZXh0LmF3c19yZXF1ZXN0X2lkXHJcbiAgICAgICAgICAgIH1cclxuICAgICAgICAgICAgXHJcbiAgICAgICAgICAgICMgU3RvcmUgaW4gU2VjcmV0cyBNYW5hZ2VyXHJcbiAgICAgICAgICAgIHRyeTpcclxuICAgICAgICAgICAgICAgICMgVHJ5IHRvIHVwZGF0ZSBleGlzdGluZyBzZWNyZXQgZmlyc3RcclxuICAgICAgICAgICAgICAgIHNlY3JldHNfY2xpZW50LnVwZGF0ZV9zZWNyZXQoXHJcbiAgICAgICAgICAgICAgICAgICAgU2VjcmV0SWQ9c2VjcmV0X25hbWUsXHJcbiAgICAgICAgICAgICAgICAgICAgU2VjcmV0U3RyaW5nPWpzb24uZHVtcHMoc2VjcmV0X3ZhbHVlKSxcclxuICAgICAgICAgICAgICAgICAgICBEZXNjcmlwdGlvbj1mXCJBUEkgR2F0ZXdheSBrZXkgZm9yIFJEUyBEYXNoYm9hcmQgaW50ZXJuYWwgQVBJIC0gQXV0by1tYW5hZ2VkXCJcclxuICAgICAgICAgICAgICAgIClcclxuICAgICAgICAgICAgICAgIGxvZ2dlci5pbmZvKGZcIlVwZGF0ZWQgZXhpc3Rpbmcgc2VjcmV0OiB7c2VjcmV0X25hbWV9XCIpXHJcbiAgICAgICAgICAgICAgICBcclxuICAgICAgICAgICAgZXhjZXB0IHNlY3JldHNfY2xpZW50LmV4Y2VwdGlvbnMuUmVzb3VyY2VOb3RGb3VuZEV4Y2VwdGlvbjpcclxuICAgICAgICAgICAgICAgICMgQ3JlYXRlIG5ldyBzZWNyZXQgaWYgaXQgZG9lc24ndCBleGlzdFxyXG4gICAgICAgICAgICAgICAgc2VjcmV0c19jbGllbnQuY3JlYXRlX3NlY3JldChcclxuICAgICAgICAgICAgICAgICAgICBOYW1lPXNlY3JldF9uYW1lLFxyXG4gICAgICAgICAgICAgICAgICAgIFNlY3JldFN0cmluZz1qc29uLmR1bXBzKHNlY3JldF92YWx1ZSksXHJcbiAgICAgICAgICAgICAgICAgICAgRGVzY3JpcHRpb249ZlwiQVBJIEdhdGV3YXkga2V5IGZvciBSRFMgRGFzaGJvYXJkIGludGVybmFsIEFQSSAtIEF1dG8tbWFuYWdlZFwiXHJcbiAgICAgICAgICAgICAgICApXHJcbiAgICAgICAgICAgICAgICBsb2dnZXIuaW5mbyhmXCJDcmVhdGVkIG5ldyBzZWNyZXQ6IHtzZWNyZXRfbmFtZX1cIilcclxuICAgICAgICAgICAgXHJcbiAgICAgICAgICAgICMgUmV0dXJuIHN1Y2Nlc3NcclxuICAgICAgICAgICAgY2ZucmVzcG9uc2Uuc2VuZChldmVudCwgY29udGV4dCwgY2ZucmVzcG9uc2UuU1VDQ0VTUywge1xyXG4gICAgICAgICAgICAgICAgJ1NlY3JldE5hbWUnOiBzZWNyZXRfbmFtZSxcclxuICAgICAgICAgICAgICAgICdBcGlLZXlJZCc6IGFwaV9rZXlfaWQsXHJcbiAgICAgICAgICAgICAgICAnTWVzc2FnZSc6IGYnU3VjY2Vzc2Z1bGx5IHN0b3JlZCBBUEkga2V5IGluIFNlY3JldHMgTWFuYWdlcidcclxuICAgICAgICAgICAgfSlcclxuICAgICAgICAgICAgXHJcbiAgICAgICAgZWxpZiByZXF1ZXN0X3R5cGUgPT0gJ0RlbGV0ZSc6XHJcbiAgICAgICAgICAgICMgT3B0aW9uYWxseSBkZWxldGUgdGhlIHNlY3JldCAoY29tbWVudGVkIG91dCBmb3Igc2FmZXR5KVxyXG4gICAgICAgICAgICAjIHNlY3JldHNfY2xpZW50LmRlbGV0ZV9zZWNyZXQoU2VjcmV0SWQ9c2VjcmV0X25hbWUsIEZvcmNlRGVsZXRlV2l0aG91dFJlY292ZXJ5PVRydWUpXHJcbiAgICAgICAgICAgIGxvZ2dlci5pbmZvKGZcIkRlbGV0ZSByZXF1ZXN0ZWQgZm9yIHNlY3JldDoge3NlY3JldF9uYW1lfSAoc2tpcHBlZCBmb3Igc2FmZXR5KVwiKVxyXG4gICAgICAgICAgICBcclxuICAgICAgICAgICAgY2ZucmVzcG9uc2Uuc2VuZChldmVudCwgY29udGV4dCwgY2ZucmVzcG9uc2UuU1VDQ0VTUywge1xyXG4gICAgICAgICAgICAgICAgJ01lc3NhZ2UnOiAnRGVsZXRlIGNvbXBsZXRlZCAoc2VjcmV0IHByZXNlcnZlZCBmb3Igc2FmZXR5KSdcclxuICAgICAgICAgICAgfSlcclxuICAgICAgICAgICAgXHJcbiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6XHJcbiAgICAgICAgbG9nZ2VyLmVycm9yKGZcIkVycm9yIGluIEFQSSBrZXkgcHJvdmlkZXI6IHtzdHIoZSl9XCIpXHJcbiAgICAgICAgY2ZucmVzcG9uc2Uuc2VuZChldmVudCwgY29udGV4dCwgY2ZucmVzcG9uc2UuRkFJTEVELCB7XHJcbiAgICAgICAgICAgICdFcnJvcic6IHN0cihlKVxyXG4gICAgICAgIH0pXHJcbmApLFxyXG4gICAgICByb2xlOiB0aGlzLmNyZWF0ZUFwaUtleVByb3ZpZGVyUm9sZSgpLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0N1c3RvbSByZXNvdXJjZSB0byByZXRyaWV2ZSBBUEkga2V5IHZhbHVlIGFuZCBzdG9yZSBpbiBTZWNyZXRzIE1hbmFnZXInLFxyXG4gICAgfSk7XHJcbiAgfVxyXG5cclxuICAvKipcclxuICAgKiBDcmVhdGVzIElBTSByb2xlIGZvciB0aGUgQVBJIGtleSBwcm92aWRlciBmdW5jdGlvblxyXG4gICAqL1xyXG4gIHByaXZhdGUgY3JlYXRlQXBpS2V5UHJvdmlkZXJSb2xlKCk6IGlhbS5Sb2xlIHtcclxuICAgIGNvbnN0IHJvbGUgPSBuZXcgaWFtLlJvbGUodGhpcywgJ0FwaUtleVByb3ZpZGVyUm9sZScsIHtcclxuICAgICAgYXNzdW1lZEJ5OiBuZXcgaWFtLlNlcnZpY2VQcmluY2lwYWwoJ2xhbWJkYS5hbWF6b25hd3MuY29tJyksXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnSUFNIHJvbGUgZm9yIEFQSSBrZXkgcHJvdmlkZXIgY3VzdG9tIHJlc291cmNlJyxcclxuICAgICAgbWFuYWdlZFBvbGljaWVzOiBbXHJcbiAgICAgICAgaWFtLk1hbmFnZWRQb2xpY3kuZnJvbUF3c01hbmFnZWRQb2xpY3lOYW1lKCdzZXJ2aWNlLXJvbGUvQVdTTGFtYmRhQmFzaWNFeGVjdXRpb25Sb2xlJyksXHJcbiAgICAgIF0sXHJcbiAgICB9KTtcclxuXHJcbiAgICAvLyBHcmFudCBwZXJtaXNzaW9uIHRvIHJlYWQgQVBJIGtleSB2YWx1ZXNcclxuICAgIHJvbGUuYWRkVG9Qb2xpY3kobmV3IGlhbS5Qb2xpY3lTdGF0ZW1lbnQoe1xyXG4gICAgICBlZmZlY3Q6IGlhbS5FZmZlY3QuQUxMT1csXHJcbiAgICAgIGFjdGlvbnM6IFtcclxuICAgICAgICAnYXBpZ2F0ZXdheTpHRVQnLFxyXG4gICAgICBdLFxyXG4gICAgICByZXNvdXJjZXM6IFtcclxuICAgICAgICBgYXJuOmF3czphcGlnYXRld2F5OiR7dGhpcy5yZWdpb259OjovYXBpa2V5cy8qYCxcclxuICAgICAgXSxcclxuICAgIH0pKTtcclxuXHJcbiAgICAvLyBHcmFudCBwZXJtaXNzaW9uIHRvIG1hbmFnZSBzZWNyZXRzXHJcbiAgICByb2xlLmFkZFRvUG9saWN5KG5ldyBpYW0uUG9saWN5U3RhdGVtZW50KHtcclxuICAgICAgZWZmZWN0OiBpYW0uRWZmZWN0LkFMTE9XLFxyXG4gICAgICBhY3Rpb25zOiBbXHJcbiAgICAgICAgJ3NlY3JldHNtYW5hZ2VyOkNyZWF0ZVNlY3JldCcsXHJcbiAgICAgICAgJ3NlY3JldHNtYW5hZ2VyOlVwZGF0ZVNlY3JldCcsXHJcbiAgICAgICAgJ3NlY3JldHNtYW5hZ2VyOkRlbGV0ZVNlY3JldCcsXHJcbiAgICAgICAgJ3NlY3JldHNtYW5hZ2VyOkdldFNlY3JldFZhbHVlJyxcclxuICAgICAgICAnc2VjcmV0c21hbmFnZXI6RGVzY3JpYmVTZWNyZXQnLFxyXG4gICAgICBdLFxyXG4gICAgICByZXNvdXJjZXM6IFtcclxuICAgICAgICBgYXJuOmF3czpzZWNyZXRzbWFuYWdlcjoke3RoaXMucmVnaW9ufToke3RoaXMuYWNjb3VudH06c2VjcmV0OnJkcy1kYXNoYm9hcmQtYXBpLWtleSpgLFxyXG4gICAgICBdLFxyXG4gICAgfSkpO1xyXG5cclxuICAgIHJldHVybiByb2xlO1xyXG4gIH1cclxufVxyXG4iXX0=