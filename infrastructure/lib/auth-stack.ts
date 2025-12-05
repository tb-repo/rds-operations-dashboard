import * as cdk from 'aws-cdk-lib'
import * as cognito from 'aws-cdk-lib/aws-cognito'
import { Construct } from 'constructs'

export interface AuthStackProps extends cdk.StackProps {
  frontendDomain?: string
}

export class AuthStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool
  public readonly userPoolClient: cognito.UserPoolClient
  public readonly userPoolDomain: cognito.UserPoolDomain

  constructor(scope: Construct, id: string, props: AuthStackProps) {
    super(scope, id, props)

    const { frontendDomain } = props

    // Create User Pool
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: 'rds-dashboard-users',
      selfSignUpEnabled: false, // Admin creates users
      signInAliases: {
        email: true,
        username: false,
      },
      autoVerify: {
        email: true,
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
        tempPasswordValidity: cdk.Duration.days(7),
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      standardAttributes: {
        email: {
          required: true,
          mutable: true,
        },
        fullname: {
          required: false,
          mutable: true,
        },
      },
      customAttributes: {
        employee_id: new cognito.StringAttribute({ minLen: 1, maxLen: 50, mutable: true }),
        department: new cognito.StringAttribute({ minLen: 1, maxLen: 100, mutable: true }),
      },
      removalPolicy: cdk.RemovalPolicy.RETAIN, // Keep user data on stack deletion
      mfa: cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: false,
        otp: true, // TOTP (authenticator apps)
      },
    })

    // Create User Groups (Roles)
    const adminGroup = new cognito.CfnUserPoolGroup(this, 'AdminGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'Admin',
      description: 'Administrators with full system access including user management',
      precedence: 1,
    })

    const dbaGroup = new cognito.CfnUserPoolGroup(this, 'DBAGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'DBA',
      description: 'Database administrators with operational access to non-production instances',
      precedence: 2,
    })

    const readOnlyGroup = new cognito.CfnUserPoolGroup(this, 'ReadOnlyGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'ReadOnly',
      description: 'Read-only users with view-only access to all dashboards',
      precedence: 3,
    })

    // Create App Client for Web Application
    this.userPoolClient = this.userPool.addClient('WebClient', {
      userPoolClientName: 'rds-dashboard-web',
      generateSecret: false, // Public client (SPA)
      authFlows: {
        userPassword: false,
        userSrp: false,
        custom: false,
      },
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: false,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: [
          frontendDomain ? `https://${frontendDomain}/callback` : 'http://localhost:5173/callback',
          'http://localhost:5173/callback', // Vite dev server
          'http://localhost:3000/callback', // Alternative dev server
        ],
        logoutUrls: [
          frontendDomain ? `https://${frontendDomain}/` : 'http://localhost:5173/',
          'http://localhost:5173/', // Vite dev server
          'http://localhost:3000/', // Alternative dev server
        ],
      },
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      preventUserExistenceErrors: true,
      // Enable PKCE for public clients (required for secure authorization code flow without client secret)
      enableTokenRevocation: true,
    })

    // Explicitly configure PKCE support using L1 construct
    const cfnUserPoolClient = this.userPoolClient.node.defaultChild as cognito.CfnUserPoolClient
    cfnUserPoolClient.addPropertyOverride('AllowedOAuthFlowsUserPoolClient', true)
    cfnUserPoolClient.addPropertyOverride('SupportedIdentityProviders', ['COGNITO'])
    
    // Ensure PKCE is supported by enabling the correct auth flows
    // For public clients (no secret), Cognito automatically requires PKCE for authorization code flow
    cfnUserPoolClient.addPropertyOverride('ExplicitAuthFlows', [
      'ALLOW_USER_SRP_AUTH',
      'ALLOW_REFRESH_TOKEN_AUTH'
    ])

    // Create Hosted UI Domain
    this.userPoolDomain = this.userPool.addDomain('Domain', {
      cognitoDomain: {
        domainPrefix: `rds-dashboard-auth-${cdk.Aws.ACCOUNT_ID}`,
      },
    })

    // Outputs
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${id}-UserPoolId`,
    })

    new cdk.CfnOutput(this, 'UserPoolArn', {
      value: this.userPool.userPoolArn,
      description: 'Cognito User Pool ARN',
      exportName: `${id}-UserPoolArn`,
    })

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: `${id}-UserPoolClientId`,
    })

    new cdk.CfnOutput(this, 'UserPoolDomain', {
      value: this.userPoolDomain.domainName,
      description: 'Cognito Hosted UI Domain',
      exportName: `${id}-UserPoolDomain`,
    })

    new cdk.CfnOutput(this, 'HostedUIUrl', {
      value: `https://${this.userPoolDomain.domainName}.auth.${cdk.Aws.REGION}.amazoncognito.com`,
      description: 'Cognito Hosted UI URL',
    })

    new cdk.CfnOutput(this, 'JwtIssuer', {
      value: `https://cognito-idp.${cdk.Aws.REGION}.amazonaws.com/${this.userPool.userPoolId}`,
      description: 'JWT Token Issuer URL',
      exportName: `${id}-JwtIssuer`,
    })

    // Tags
    cdk.Tags.of(this).add('Project', 'RDS-Operations-Dashboard')
    cdk.Tags.of(this).add('Component', 'Authentication')
  }
}
