import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export interface BffStackProps extends cdk.StackProps {
  internalApiUrl: string;
  apiKeyId: string;
}

export class BffStack extends cdk.Stack {
  public readonly bffApi: apigateway.RestApi;
  public readonly bffFunction: lambda.Function;
  public readonly apiSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: BffStackProps) {
    super(scope, id, props);

    const environment = this.node.tryGetContext('environment') || 'prod';

    // ========================================
    // Secrets Manager - Store API Key
    // ========================================
    this.apiSecret = new secretsmanager.Secret(this, 'ApiSecret', {
      secretName: `rds-dashboard-api-key-${environment}`,
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
    // BFF Lambda Function
    // ========================================
    this.bffFunction = new lambda.Function(this, 'BffFunction', {
      functionName: `rds-dashboard-bff-${environment}`,
      runtime: lambda.Runtime.NODEJS_16_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');
const https = require('https');
const url = require('url');

const secretsManager = new AWS.SecretsManager();

// Cache for API credentials
let cachedCredentials = null;
let cacheExpiry = 0;

async function getApiCredentials() {
  const now = Date.now();
  
  // Return cached credentials if still valid (5 minutes cache)
  if (cachedCredentials && now < cacheExpiry) {
    return cachedCredentials;
  }

  try {
    const result = await secretsManager.getSecretValue({
      SecretId: process.env.API_SECRET_ARN
    }).promise();
    
    const secret = JSON.parse(result.SecretString);
    
    cachedCredentials = {
      apiUrl: secret.apiUrl,
      apiKey: secret.apiKey
    };
    cacheExpiry = now + (5 * 60 * 1000); // 5 minutes
    
    return cachedCredentials;
  } catch (error) {
    console.error('Failed to retrieve API credentials:', error);
    throw new Error('Unable to retrieve API credentials');
  }
}

async function makeApiRequest(path, method, body, headers) {
  const credentials = await getApiCredentials();
  const apiUrl = new URL(path, credentials.apiUrl);
  
  const options = {
    hostname: apiUrl.hostname,
    port: 443,
    path: apiUrl.pathname + apiUrl.search,
    method: method,
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': credentials.apiKey,
      ...headers
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = {
            statusCode: res.statusCode,
            headers: res.headers,
            body: data
          };
          resolve(response);
        } catch (error) {
          reject(error);
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    
    req.end();
  });
}

exports.handler = async (event) => {
  console.log('BFF Request:', JSON.stringify(event, null, 2));
  
  try {
    // Extract path and method from API Gateway event
    const path = event.path || event.rawPath || '/';
    const method = event.httpMethod || event.requestContext?.http?.method || 'GET';
    const body = event.body;
    const headers = event.headers || {};

    // Remove host and other headers that shouldn't be forwarded
    const forwardHeaders = { ...headers };
    delete forwardHeaders.host;
    delete forwardHeaders.authorization;
    delete forwardHeaders['x-api-key'];

    // Make request to internal API
    const response = await makeApiRequest(path, method, body, forwardHeaders);

    // Return response in API Gateway format
    return {
      statusCode: response.statusCode,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
      },
      body: response.body
    };
  } catch (error) {
    console.error('BFF Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        message: error.message
      })
    };
  }
};
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        API_SECRET_ARN: this.apiSecret.secretArn,
        NODE_ENV: 'production'
      },
      description: 'Backend-for-Frontend proxy for RDS Dashboard'
    });

    // Grant permission to read the secret
    this.apiSecret.grantRead(this.bffFunction);

    // ========================================
    // BFF API Gateway (Public)
    // ========================================
    this.bffApi = new apigateway.RestApi(this, 'BffApi', {
      restApiName: `rds-dashboard-bff-${environment}`,
      description: 'Backend-for-Frontend API for RDS Dashboard',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token'
        ]
      },
      deployOptions: {
        stageName: 'prod',
        throttlingRateLimit: 1000,
        throttlingBurstLimit: 2000,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true
      }
    });

    // Create Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(this.bffFunction, {
      proxy: true,
      allowTestInvoke: true
    });

    // Add proxy resource for all sub-paths: /{proxy+}
    // This will handle /instances, /health, /costs, etc.
    this.bffApi.root.addProxy({
      defaultIntegration: lambdaIntegration,
      anyMethod: true  // Adds ANY method to {proxy+} resource
    });

    // Note: We don't add a separate root method because the proxy handles all paths
    // The {proxy+} resource will catch all requests including root

    // ========================================
    // CloudFormation Outputs
    // ========================================
    new cdk.CfnOutput(this, 'BffApiUrl', {
      value: this.bffApi.url,
      description: 'BFF API Gateway URL',
      exportName: `${environment}-BffApiUrl`
    });

    new cdk.CfnOutput(this, 'BffApiId', {
      value: this.bffApi.restApiId,
      description: 'BFF API Gateway ID',
      exportName: `${environment}-BffApiId`
    });

    new cdk.CfnOutput(this, 'ApiSecretArn', {
      value: this.apiSecret.secretArn,
      description: 'API Secret ARN in Secrets Manager',
      exportName: `${environment}-ApiSecretArn`
    });
  }
}
