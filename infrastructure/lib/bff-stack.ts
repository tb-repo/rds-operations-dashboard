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
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const https = require('https');
const url = require('url');

const secretsManager = new SecretsManagerClient({});

// Cache for API credentials
let cachedCredentials = null;
let cacheExpiry = 0;

async function getApiCredentials() {
  console.log('[getApiCredentials] Starting...');
  const now = Date.now();
  
  // Return cached credentials if still valid (5 minutes cache)
  if (cachedCredentials && now < cacheExpiry) {
    console.log('[getApiCredentials] Using cached credentials');
    return cachedCredentials;
  }

  try {
    console.log('[getApiCredentials] Fetching from Secrets Manager:', process.env.API_SECRET_ARN);
    const command = new GetSecretValueCommand({
      SecretId: process.env.API_SECRET_ARN
    });
    const result = await secretsManager.send(command);
    
    console.log('[getApiCredentials] Secret retrieved successfully');
    const secret = JSON.parse(result.SecretString);
    
    console.log('[getApiCredentials] API URL:', secret.apiUrl);
    console.log('[getApiCredentials] API Key exists:', !!secret.apiKey);
    console.log('[getApiCredentials] API Key length:', secret.apiKey?.length);
    
    cachedCredentials = {
      apiUrl: secret.apiUrl,
      apiKey: secret.apiKey
    };
    cacheExpiry = now + (5 * 60 * 1000); // 5 minutes
    
    return cachedCredentials;
  } catch (error) {
    console.error('[getApiCredentials] ERROR:', {
      message: error.message,
      code: error.code,
      stack: error.stack
    });
    throw new Error(\`Unable to retrieve API credentials: \${error.message}\`);
  }
}

async function makeApiRequest(path, method, body, headers) {
  console.log('[makeApiRequest] Starting...');
  console.log('[makeApiRequest] Path:', path);
  console.log('[makeApiRequest] Method:', method);
  
  try {
    const credentials = await getApiCredentials();
    
    // Construct full URL by appending path to base URL
    // Remove trailing slash from apiUrl and leading slash from path to avoid double slashes
    const baseUrl = credentials.apiUrl.replace(/\\/$/, '');
    const cleanPath = path.replace(/^\\//, '');
    const fullUrl = baseUrl + '/' + cleanPath;
    const apiUrl = new URL(fullUrl);
    
    console.log('[makeApiRequest] Base URL:', baseUrl);
    console.log('[makeApiRequest] Clean path:', cleanPath);
    console.log('[makeApiRequest] Full URL:', apiUrl.href);
    console.log('[makeApiRequest] Hostname:', apiUrl.hostname);
    console.log('[makeApiRequest] Path:', apiUrl.pathname + apiUrl.search);
    
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
    
    console.log('[makeApiRequest] Request options:', JSON.stringify({
      ...options,
      headers: {
        ...options.headers,
        'x-api-key': options.headers['x-api-key'] ? '[REDACTED]' : undefined
      }
    }));

    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        console.log('[makeApiRequest] Response status:', res.statusCode);
        console.log('[makeApiRequest] Response headers:', JSON.stringify(res.headers));
        
        let data = '';
        
        res.on('data', (chunk) => {
          data += chunk;
        });
        
        res.on('end', () => {
          try {
            console.log('[makeApiRequest] Response body length:', data.length);
            console.log('[makeApiRequest] Response body preview:', data.substring(0, 200));
            
            const response = {
              statusCode: res.statusCode,
              headers: res.headers,
              body: data
            };
            resolve(response);
          } catch (error) {
            console.error('[makeApiRequest] Error parsing response:', error);
            reject(error);
          }
        });
      });

      req.on('error', (error) => {
        console.error('[makeApiRequest] Request error:', {
          message: error.message,
          code: error.code,
          stack: error.stack
        });
        reject(error);
      });

      if (body) {
        const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
        console.log('[makeApiRequest] Request body:', bodyStr);
        req.write(bodyStr);
      }
      
      req.end();
      console.log('[makeApiRequest] Request sent');
    });
  } catch (error) {
    console.error('[makeApiRequest] ERROR:', {
      message: error.message,
      code: error.code,
      stack: error.stack
    });
    throw error;
  }
}

exports.handler = async (event) => {
  console.log('=== BFF Request Start ===');
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    // Extract path and method from API Gateway event
    const path = event.path || event.rawPath || '/';
    const method = event.httpMethod || event.requestContext?.http?.method || 'GET';
    const body = event.body;
    const headers = event.headers || {};

    console.log('[handler] Extracted path:', path);
    console.log('[handler] Extracted method:', method);
    console.log('[handler] Headers:', JSON.stringify(headers));

    // Remove host and other headers that shouldn't be forwarded
    const forwardHeaders = { ...headers };
    delete forwardHeaders.host;
    delete forwardHeaders.Host;
    delete forwardHeaders.authorization;
    delete forwardHeaders.Authorization;
    delete forwardHeaders['x-api-key'];
    delete forwardHeaders['X-Api-Key'];
    
    console.log('[handler] Forward headers:', JSON.stringify(forwardHeaders));

    // Make request to internal API
    console.log('[handler] Calling internal API...');
    const response = await makeApiRequest(path, method, body, forwardHeaders);
    
    console.log('[handler] Internal API response status:', response.statusCode);
    console.log('[handler] Internal API response body preview:', response.body.substring(0, 200));

    // Return response in API Gateway format
    const result = {
      statusCode: response.statusCode,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
      },
      body: response.body
    };
    
    console.log('[handler] Returning status:', result.statusCode);
    console.log('=== BFF Request End (Success) ===');
    return result;
  } catch (error) {
    console.error('=== BFF Request End (Error) ===');
    console.error('[handler] ERROR:', {
      message: error.message,
      code: error.code,
      stack: error.stack,
      name: error.name
    });
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        message: error.message,
        type: error.name
      })
    };
  }
};
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        API_SECRET_ARN: this.apiSecret.secretArn,
        NODE_ENV: 'production',
        AWS_NODEJS_CONNECTION_REUSE_ENABLED: '1'
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
