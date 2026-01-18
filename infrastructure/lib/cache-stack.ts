import * as cdk from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import { Construct } from 'constructs';

/**
 * Cache Stack for RDS Discovery Integration
 * 
 * Creates DynamoDB table for caching discovery service results
 * with TTL support for automatic cleanup.
 */
export class CacheStack extends cdk.Stack {
  public readonly cacheTable: dynamodb.Table;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create DynamoDB table for caching discovery results
    this.cacheTable = new dynamodb.Table(this, 'DiscoveryCache', {
      tableName: 'rds-discovery-cache',
      partitionKey: {
        name: 'cache_key',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      timeToLiveAttribute: 'ttl',
      removalPolicy: cdk.RemovalPolicy.RETAIN, // Keep data on stack deletion
      pointInTimeRecovery: true, // Enable backup
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      
      // Tags for governance
      tags: {
        'Purpose': 'RDS Discovery Cache',
        'Component': 'BFF Integration',
        'Environment': 'Production'
      }
    });

    // Output the table name for other stacks
    new cdk.CfnOutput(this, 'CacheTableName', {
      value: this.cacheTable.tableName,
      description: 'Name of the DynamoDB cache table',
      exportName: 'RDSDiscoveryCacheTableName'
    });

    // Output the table ARN for IAM permissions
    new cdk.CfnOutput(this, 'CacheTableArn', {
      value: this.cacheTable.tableArn,
      description: 'ARN of the DynamoDB cache table',
      exportName: 'RDSDiscoveryCacheTableArn'
    });
  }
}