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

import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import * as path from 'path';

export interface BffStackProps extends cdk.StackProps {
  internalApiUrl: string;
  apiKeyId: string;
  userPoolId?: string;
  userPoolClientId?: string;
  frontendUrl?: string;
}

export class BffStack extends cdk.Stack {
  public readonly bffApi: apigateway.RestApi;
  public readonly bffFunction: lambda.DockerImageFunction;
  public readonly apiSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: BffStackProps) {
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
