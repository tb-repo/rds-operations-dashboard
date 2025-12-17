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
exports.AuthStack = void 0;
const cdk = __importStar(require("aws-cdk-lib"));
const cognito = __importStar(require("aws-cdk-lib/aws-cognito"));
class AuthStack extends cdk.Stack {
    constructor(scope, id, props) {
        super(scope, id, props);
        const { frontendDomain } = props;
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
        });
        // Create User Groups (Roles)
        const adminGroup = new cognito.CfnUserPoolGroup(this, 'AdminGroup', {
            userPoolId: this.userPool.userPoolId,
            groupName: 'Admin',
            description: 'Administrators with full system access including user management',
            precedence: 1,
        });
        const dbaGroup = new cognito.CfnUserPoolGroup(this, 'DBAGroup', {
            userPoolId: this.userPool.userPoolId,
            groupName: 'DBA',
            description: 'Database administrators with operational access to non-production instances',
            precedence: 2,
        });
        const readOnlyGroup = new cognito.CfnUserPoolGroup(this, 'ReadOnlyGroup', {
            userPoolId: this.userPool.userPoolId,
            groupName: 'ReadOnly',
            description: 'Read-only users with view-only access to all dashboards',
            precedence: 3,
        });
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
        });
        // Explicitly configure PKCE support using L1 construct
        const cfnUserPoolClient = this.userPoolClient.node.defaultChild;
        cfnUserPoolClient.addPropertyOverride('AllowedOAuthFlowsUserPoolClient', true);
        cfnUserPoolClient.addPropertyOverride('SupportedIdentityProviders', ['COGNITO']);
        // Ensure PKCE is supported by enabling the correct auth flows
        // For public clients (no secret), Cognito automatically requires PKCE for authorization code flow
        cfnUserPoolClient.addPropertyOverride('ExplicitAuthFlows', [
            'ALLOW_USER_SRP_AUTH',
            'ALLOW_REFRESH_TOKEN_AUTH'
        ]);
        // Create Hosted UI Domain
        this.userPoolDomain = this.userPool.addDomain('Domain', {
            cognitoDomain: {
                domainPrefix: `rds-dashboard-auth-${cdk.Aws.ACCOUNT_ID}`,
            },
        });
        // Outputs
        new cdk.CfnOutput(this, 'UserPoolId', {
            value: this.userPool.userPoolId,
            description: 'Cognito User Pool ID',
            exportName: `${id}-UserPoolId`,
        });
        new cdk.CfnOutput(this, 'UserPoolArn', {
            value: this.userPool.userPoolArn,
            description: 'Cognito User Pool ARN',
            exportName: `${id}-UserPoolArn`,
        });
        new cdk.CfnOutput(this, 'UserPoolClientId', {
            value: this.userPoolClient.userPoolClientId,
            description: 'Cognito User Pool Client ID',
            exportName: `${id}-UserPoolClientId`,
        });
        new cdk.CfnOutput(this, 'UserPoolDomain', {
            value: this.userPoolDomain.domainName,
            description: 'Cognito Hosted UI Domain',
            exportName: `${id}-UserPoolDomain`,
        });
        new cdk.CfnOutput(this, 'HostedUIUrl', {
            value: `https://${this.userPoolDomain.domainName}.auth.${cdk.Aws.REGION}.amazoncognito.com`,
            description: 'Cognito Hosted UI URL',
        });
        new cdk.CfnOutput(this, 'JwtIssuer', {
            value: `https://cognito-idp.${cdk.Aws.REGION}.amazonaws.com/${this.userPool.userPoolId}`,
            description: 'JWT Token Issuer URL',
            exportName: `${id}-JwtIssuer`,
        });
        // Tags
        cdk.Tags.of(this).add('Project', 'RDS-Operations-Dashboard');
        cdk.Tags.of(this).add('Component', 'Authentication');
    }
}
exports.AuthStack = AuthStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYXV0aC1zdGFjay5qcyIsInNvdXJjZVJvb3QiOiIiLCJzb3VyY2VzIjpbImF1dGgtc3RhY2sudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6Ijs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0FBQUEsaURBQWtDO0FBQ2xDLGlFQUFrRDtBQU9sRCxNQUFhLFNBQVUsU0FBUSxHQUFHLENBQUMsS0FBSztJQUt0QyxZQUFZLEtBQWdCLEVBQUUsRUFBVSxFQUFFLEtBQXFCO1FBQzdELEtBQUssQ0FBQyxLQUFLLEVBQUUsRUFBRSxFQUFFLEtBQUssQ0FBQyxDQUFBO1FBRXZCLE1BQU0sRUFBRSxjQUFjLEVBQUUsR0FBRyxLQUFLLENBQUE7UUFFaEMsbUJBQW1CO1FBQ25CLElBQUksQ0FBQyxRQUFRLEdBQUcsSUFBSSxPQUFPLENBQUMsUUFBUSxDQUFDLElBQUksRUFBRSxVQUFVLEVBQUU7WUFDckQsWUFBWSxFQUFFLHFCQUFxQjtZQUNuQyxpQkFBaUIsRUFBRSxLQUFLLEVBQUUsc0JBQXNCO1lBQ2hELGFBQWEsRUFBRTtnQkFDYixLQUFLLEVBQUUsSUFBSTtnQkFDWCxRQUFRLEVBQUUsS0FBSzthQUNoQjtZQUNELFVBQVUsRUFBRTtnQkFDVixLQUFLLEVBQUUsSUFBSTthQUNaO1lBQ0QsY0FBYyxFQUFFO2dCQUNkLFNBQVMsRUFBRSxDQUFDO2dCQUNaLGdCQUFnQixFQUFFLElBQUk7Z0JBQ3RCLGdCQUFnQixFQUFFLElBQUk7Z0JBQ3RCLGFBQWEsRUFBRSxJQUFJO2dCQUNuQixjQUFjLEVBQUUsSUFBSTtnQkFDcEIsb0JBQW9CLEVBQUUsR0FBRyxDQUFDLFFBQVEsQ0FBQyxJQUFJLENBQUMsQ0FBQyxDQUFDO2FBQzNDO1lBQ0QsZUFBZSxFQUFFLE9BQU8sQ0FBQyxlQUFlLENBQUMsVUFBVTtZQUNuRCxrQkFBa0IsRUFBRTtnQkFDbEIsS0FBSyxFQUFFO29CQUNMLFFBQVEsRUFBRSxJQUFJO29CQUNkLE9BQU8sRUFBRSxJQUFJO2lCQUNkO2dCQUNELFFBQVEsRUFBRTtvQkFDUixRQUFRLEVBQUUsS0FBSztvQkFDZixPQUFPLEVBQUUsSUFBSTtpQkFDZDthQUNGO1lBQ0QsZ0JBQWdCLEVBQUU7Z0JBQ2hCLFdBQVcsRUFBRSxJQUFJLE9BQU8sQ0FBQyxlQUFlLENBQUMsRUFBRSxNQUFNLEVBQUUsQ0FBQyxFQUFFLE1BQU0sRUFBRSxFQUFFLEVBQUUsT0FBTyxFQUFFLElBQUksRUFBRSxDQUFDO2dCQUNsRixVQUFVLEVBQUUsSUFBSSxPQUFPLENBQUMsZUFBZSxDQUFDLEVBQUUsTUFBTSxFQUFFLENBQUMsRUFBRSxNQUFNLEVBQUUsR0FBRyxFQUFFLE9BQU8sRUFBRSxJQUFJLEVBQUUsQ0FBQzthQUNuRjtZQUNELGFBQWEsRUFBRSxHQUFHLENBQUMsYUFBYSxDQUFDLE1BQU0sRUFBRSxtQ0FBbUM7WUFDNUUsR0FBRyxFQUFFLE9BQU8sQ0FBQyxHQUFHLENBQUMsUUFBUTtZQUN6QixlQUFlLEVBQUU7Z0JBQ2YsR0FBRyxFQUFFLEtBQUs7Z0JBQ1YsR0FBRyxFQUFFLElBQUksRUFBRSw0QkFBNEI7YUFDeEM7U0FDRixDQUFDLENBQUE7UUFFRiw2QkFBNkI7UUFDN0IsTUFBTSxVQUFVLEdBQUcsSUFBSSxPQUFPLENBQUMsZ0JBQWdCLENBQUMsSUFBSSxFQUFFLFlBQVksRUFBRTtZQUNsRSxVQUFVLEVBQUUsSUFBSSxDQUFDLFFBQVEsQ0FBQyxVQUFVO1lBQ3BDLFNBQVMsRUFBRSxPQUFPO1lBQ2xCLFdBQVcsRUFBRSxrRUFBa0U7WUFDL0UsVUFBVSxFQUFFLENBQUM7U0FDZCxDQUFDLENBQUE7UUFFRixNQUFNLFFBQVEsR0FBRyxJQUFJLE9BQU8sQ0FBQyxnQkFBZ0IsQ0FBQyxJQUFJLEVBQUUsVUFBVSxFQUFFO1lBQzlELFVBQVUsRUFBRSxJQUFJLENBQUMsUUFBUSxDQUFDLFVBQVU7WUFDcEMsU0FBUyxFQUFFLEtBQUs7WUFDaEIsV0FBVyxFQUFFLDZFQUE2RTtZQUMxRixVQUFVLEVBQUUsQ0FBQztTQUNkLENBQUMsQ0FBQTtRQUVGLE1BQU0sYUFBYSxHQUFHLElBQUksT0FBTyxDQUFDLGdCQUFnQixDQUFDLElBQUksRUFBRSxlQUFlLEVBQUU7WUFDeEUsVUFBVSxFQUFFLElBQUksQ0FBQyxRQUFRLENBQUMsVUFBVTtZQUNwQyxTQUFTLEVBQUUsVUFBVTtZQUNyQixXQUFXLEVBQUUseURBQXlEO1lBQ3RFLFVBQVUsRUFBRSxDQUFDO1NBQ2QsQ0FBQyxDQUFBO1FBRUYsd0NBQXdDO1FBQ3hDLElBQUksQ0FBQyxjQUFjLEdBQUcsSUFBSSxDQUFDLFFBQVEsQ0FBQyxTQUFTLENBQUMsV0FBVyxFQUFFO1lBQ3pELGtCQUFrQixFQUFFLG1CQUFtQjtZQUN2QyxjQUFjLEVBQUUsS0FBSyxFQUFFLHNCQUFzQjtZQUM3QyxTQUFTLEVBQUU7Z0JBQ1QsWUFBWSxFQUFFLEtBQUs7Z0JBQ25CLE9BQU8sRUFBRSxLQUFLO2dCQUNkLE1BQU0sRUFBRSxLQUFLO2FBQ2Q7WUFDRCxLQUFLLEVBQUU7Z0JBQ0wsS0FBSyxFQUFFO29CQUNMLHNCQUFzQixFQUFFLElBQUk7b0JBQzVCLGlCQUFpQixFQUFFLEtBQUs7aUJBQ3pCO2dCQUNELE1BQU0sRUFBRTtvQkFDTixPQUFPLENBQUMsVUFBVSxDQUFDLE1BQU07b0JBQ3pCLE9BQU8sQ0FBQyxVQUFVLENBQUMsS0FBSztvQkFDeEIsT0FBTyxDQUFDLFVBQVUsQ0FBQyxPQUFPO2lCQUMzQjtnQkFDRCxZQUFZLEVBQUU7b0JBQ1osY0FBYyxDQUFDLENBQUMsQ0FBQyxXQUFXLGNBQWMsV0FBVyxDQUFDLENBQUMsQ0FBQyxnQ0FBZ0M7b0JBQ3hGLGdDQUFnQyxFQUFFLGtCQUFrQjtvQkFDcEQsZ0NBQWdDLEVBQUUseUJBQXlCO2lCQUM1RDtnQkFDRCxVQUFVLEVBQUU7b0JBQ1YsY0FBYyxDQUFDLENBQUMsQ0FBQyxXQUFXLGNBQWMsR0FBRyxDQUFDLENBQUMsQ0FBQyx3QkFBd0I7b0JBQ3hFLHdCQUF3QixFQUFFLGtCQUFrQjtvQkFDNUMsd0JBQXdCLEVBQUUseUJBQXlCO2lCQUNwRDthQUNGO1lBQ0QsbUJBQW1CLEVBQUUsR0FBRyxDQUFDLFFBQVEsQ0FBQyxLQUFLLENBQUMsQ0FBQyxDQUFDO1lBQzFDLGVBQWUsRUFBRSxHQUFHLENBQUMsUUFBUSxDQUFDLEtBQUssQ0FBQyxDQUFDLENBQUM7WUFDdEMsb0JBQW9CLEVBQUUsR0FBRyxDQUFDLFFBQVEsQ0FBQyxJQUFJLENBQUMsRUFBRSxDQUFDO1lBQzNDLDBCQUEwQixFQUFFLElBQUk7WUFDaEMscUdBQXFHO1lBQ3JHLHFCQUFxQixFQUFFLElBQUk7U0FDNUIsQ0FBQyxDQUFBO1FBRUYsdURBQXVEO1FBQ3ZELE1BQU0saUJBQWlCLEdBQUcsSUFBSSxDQUFDLGNBQWMsQ0FBQyxJQUFJLENBQUMsWUFBeUMsQ0FBQTtRQUM1RixpQkFBaUIsQ0FBQyxtQkFBbUIsQ0FBQyxpQ0FBaUMsRUFBRSxJQUFJLENBQUMsQ0FBQTtRQUM5RSxpQkFBaUIsQ0FBQyxtQkFBbUIsQ0FBQyw0QkFBNEIsRUFBRSxDQUFDLFNBQVMsQ0FBQyxDQUFDLENBQUE7UUFFaEYsOERBQThEO1FBQzlELGtHQUFrRztRQUNsRyxpQkFBaUIsQ0FBQyxtQkFBbUIsQ0FBQyxtQkFBbUIsRUFBRTtZQUN6RCxxQkFBcUI7WUFDckIsMEJBQTBCO1NBQzNCLENBQUMsQ0FBQTtRQUVGLDBCQUEwQjtRQUMxQixJQUFJLENBQUMsY0FBYyxHQUFHLElBQUksQ0FBQyxRQUFRLENBQUMsU0FBUyxDQUFDLFFBQVEsRUFBRTtZQUN0RCxhQUFhLEVBQUU7Z0JBQ2IsWUFBWSxFQUFFLHNCQUFzQixHQUFHLENBQUMsR0FBRyxDQUFDLFVBQVUsRUFBRTthQUN6RDtTQUNGLENBQUMsQ0FBQTtRQUVGLFVBQVU7UUFDVixJQUFJLEdBQUcsQ0FBQyxTQUFTLENBQUMsSUFBSSxFQUFFLFlBQVksRUFBRTtZQUNwQyxLQUFLLEVBQUUsSUFBSSxDQUFDLFFBQVEsQ0FBQyxVQUFVO1lBQy9CLFdBQVcsRUFBRSxzQkFBc0I7WUFDbkMsVUFBVSxFQUFFLEdBQUcsRUFBRSxhQUFhO1NBQy9CLENBQUMsQ0FBQTtRQUVGLElBQUksR0FBRyxDQUFDLFNBQVMsQ0FBQyxJQUFJLEVBQUUsYUFBYSxFQUFFO1lBQ3JDLEtBQUssRUFBRSxJQUFJLENBQUMsUUFBUSxDQUFDLFdBQVc7WUFDaEMsV0FBVyxFQUFFLHVCQUF1QjtZQUNwQyxVQUFVLEVBQUUsR0FBRyxFQUFFLGNBQWM7U0FDaEMsQ0FBQyxDQUFBO1FBRUYsSUFBSSxHQUFHLENBQUMsU0FBUyxDQUFDLElBQUksRUFBRSxrQkFBa0IsRUFBRTtZQUMxQyxLQUFLLEVBQUUsSUFBSSxDQUFDLGNBQWMsQ0FBQyxnQkFBZ0I7WUFDM0MsV0FBVyxFQUFFLDZCQUE2QjtZQUMxQyxVQUFVLEVBQUUsR0FBRyxFQUFFLG1CQUFtQjtTQUNyQyxDQUFDLENBQUE7UUFFRixJQUFJLEdBQUcsQ0FBQyxTQUFTLENBQUMsSUFBSSxFQUFFLGdCQUFnQixFQUFFO1lBQ3hDLEtBQUssRUFBRSxJQUFJLENBQUMsY0FBYyxDQUFDLFVBQVU7WUFDckMsV0FBVyxFQUFFLDBCQUEwQjtZQUN2QyxVQUFVLEVBQUUsR0FBRyxFQUFFLGlCQUFpQjtTQUNuQyxDQUFDLENBQUE7UUFFRixJQUFJLEdBQUcsQ0FBQyxTQUFTLENBQUMsSUFBSSxFQUFFLGFBQWEsRUFBRTtZQUNyQyxLQUFLLEVBQUUsV0FBVyxJQUFJLENBQUMsY0FBYyxDQUFDLFVBQVUsU0FBUyxHQUFHLENBQUMsR0FBRyxDQUFDLE1BQU0sb0JBQW9CO1lBQzNGLFdBQVcsRUFBRSx1QkFBdUI7U0FDckMsQ0FBQyxDQUFBO1FBRUYsSUFBSSxHQUFHLENBQUMsU0FBUyxDQUFDLElBQUksRUFBRSxXQUFXLEVBQUU7WUFDbkMsS0FBSyxFQUFFLHVCQUF1QixHQUFHLENBQUMsR0FBRyxDQUFDLE1BQU0sa0JBQWtCLElBQUksQ0FBQyxRQUFRLENBQUMsVUFBVSxFQUFFO1lBQ3hGLFdBQVcsRUFBRSxzQkFBc0I7WUFDbkMsVUFBVSxFQUFFLEdBQUcsRUFBRSxZQUFZO1NBQzlCLENBQUMsQ0FBQTtRQUVGLE9BQU87UUFDUCxHQUFHLENBQUMsSUFBSSxDQUFDLEVBQUUsQ0FBQyxJQUFJLENBQUMsQ0FBQyxHQUFHLENBQUMsU0FBUyxFQUFFLDBCQUEwQixDQUFDLENBQUE7UUFDNUQsR0FBRyxDQUFDLElBQUksQ0FBQyxFQUFFLENBQUMsSUFBSSxDQUFDLENBQUMsR0FBRyxDQUFDLFdBQVcsRUFBRSxnQkFBZ0IsQ0FBQyxDQUFBO0lBQ3RELENBQUM7Q0FDRjtBQTNLRCw4QkEyS0MiLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgKiBhcyBjZGsgZnJvbSAnYXdzLWNkay1saWInXHJcbmltcG9ydCAqIGFzIGNvZ25pdG8gZnJvbSAnYXdzLWNkay1saWIvYXdzLWNvZ25pdG8nXHJcbmltcG9ydCB7IENvbnN0cnVjdCB9IGZyb20gJ2NvbnN0cnVjdHMnXHJcblxyXG5leHBvcnQgaW50ZXJmYWNlIEF1dGhTdGFja1Byb3BzIGV4dGVuZHMgY2RrLlN0YWNrUHJvcHMge1xyXG4gIGZyb250ZW5kRG9tYWluPzogc3RyaW5nXHJcbn1cclxuXHJcbmV4cG9ydCBjbGFzcyBBdXRoU3RhY2sgZXh0ZW5kcyBjZGsuU3RhY2sge1xyXG4gIHB1YmxpYyByZWFkb25seSB1c2VyUG9vbDogY29nbml0by5Vc2VyUG9vbFxyXG4gIHB1YmxpYyByZWFkb25seSB1c2VyUG9vbENsaWVudDogY29nbml0by5Vc2VyUG9vbENsaWVudFxyXG4gIHB1YmxpYyByZWFkb25seSB1c2VyUG9vbERvbWFpbjogY29nbml0by5Vc2VyUG9vbERvbWFpblxyXG5cclxuICBjb25zdHJ1Y3RvcihzY29wZTogQ29uc3RydWN0LCBpZDogc3RyaW5nLCBwcm9wczogQXV0aFN0YWNrUHJvcHMpIHtcclxuICAgIHN1cGVyKHNjb3BlLCBpZCwgcHJvcHMpXHJcblxyXG4gICAgY29uc3QgeyBmcm9udGVuZERvbWFpbiB9ID0gcHJvcHNcclxuXHJcbiAgICAvLyBDcmVhdGUgVXNlciBQb29sXHJcbiAgICB0aGlzLnVzZXJQb29sID0gbmV3IGNvZ25pdG8uVXNlclBvb2wodGhpcywgJ1VzZXJQb29sJywge1xyXG4gICAgICB1c2VyUG9vbE5hbWU6ICdyZHMtZGFzaGJvYXJkLXVzZXJzJyxcclxuICAgICAgc2VsZlNpZ25VcEVuYWJsZWQ6IGZhbHNlLCAvLyBBZG1pbiBjcmVhdGVzIHVzZXJzXHJcbiAgICAgIHNpZ25JbkFsaWFzZXM6IHtcclxuICAgICAgICBlbWFpbDogdHJ1ZSxcclxuICAgICAgICB1c2VybmFtZTogZmFsc2UsXHJcbiAgICAgIH0sXHJcbiAgICAgIGF1dG9WZXJpZnk6IHtcclxuICAgICAgICBlbWFpbDogdHJ1ZSxcclxuICAgICAgfSxcclxuICAgICAgcGFzc3dvcmRQb2xpY3k6IHtcclxuICAgICAgICBtaW5MZW5ndGg6IDgsXHJcbiAgICAgICAgcmVxdWlyZUxvd2VyY2FzZTogdHJ1ZSxcclxuICAgICAgICByZXF1aXJlVXBwZXJjYXNlOiB0cnVlLFxyXG4gICAgICAgIHJlcXVpcmVEaWdpdHM6IHRydWUsXHJcbiAgICAgICAgcmVxdWlyZVN5bWJvbHM6IHRydWUsXHJcbiAgICAgICAgdGVtcFBhc3N3b3JkVmFsaWRpdHk6IGNkay5EdXJhdGlvbi5kYXlzKDcpLFxyXG4gICAgICB9LFxyXG4gICAgICBhY2NvdW50UmVjb3Zlcnk6IGNvZ25pdG8uQWNjb3VudFJlY292ZXJ5LkVNQUlMX09OTFksXHJcbiAgICAgIHN0YW5kYXJkQXR0cmlidXRlczoge1xyXG4gICAgICAgIGVtYWlsOiB7XHJcbiAgICAgICAgICByZXF1aXJlZDogdHJ1ZSxcclxuICAgICAgICAgIG11dGFibGU6IHRydWUsXHJcbiAgICAgICAgfSxcclxuICAgICAgICBmdWxsbmFtZToge1xyXG4gICAgICAgICAgcmVxdWlyZWQ6IGZhbHNlLFxyXG4gICAgICAgICAgbXV0YWJsZTogdHJ1ZSxcclxuICAgICAgICB9LFxyXG4gICAgICB9LFxyXG4gICAgICBjdXN0b21BdHRyaWJ1dGVzOiB7XHJcbiAgICAgICAgZW1wbG95ZWVfaWQ6IG5ldyBjb2duaXRvLlN0cmluZ0F0dHJpYnV0ZSh7IG1pbkxlbjogMSwgbWF4TGVuOiA1MCwgbXV0YWJsZTogdHJ1ZSB9KSxcclxuICAgICAgICBkZXBhcnRtZW50OiBuZXcgY29nbml0by5TdHJpbmdBdHRyaWJ1dGUoeyBtaW5MZW46IDEsIG1heExlbjogMTAwLCBtdXRhYmxlOiB0cnVlIH0pLFxyXG4gICAgICB9LFxyXG4gICAgICByZW1vdmFsUG9saWN5OiBjZGsuUmVtb3ZhbFBvbGljeS5SRVRBSU4sIC8vIEtlZXAgdXNlciBkYXRhIG9uIHN0YWNrIGRlbGV0aW9uXHJcbiAgICAgIG1mYTogY29nbml0by5NZmEuT1BUSU9OQUwsXHJcbiAgICAgIG1mYVNlY29uZEZhY3Rvcjoge1xyXG4gICAgICAgIHNtczogZmFsc2UsXHJcbiAgICAgICAgb3RwOiB0cnVlLCAvLyBUT1RQIChhdXRoZW50aWNhdG9yIGFwcHMpXHJcbiAgICAgIH0sXHJcbiAgICB9KVxyXG5cclxuICAgIC8vIENyZWF0ZSBVc2VyIEdyb3VwcyAoUm9sZXMpXHJcbiAgICBjb25zdCBhZG1pbkdyb3VwID0gbmV3IGNvZ25pdG8uQ2ZuVXNlclBvb2xHcm91cCh0aGlzLCAnQWRtaW5Hcm91cCcsIHtcclxuICAgICAgdXNlclBvb2xJZDogdGhpcy51c2VyUG9vbC51c2VyUG9vbElkLFxyXG4gICAgICBncm91cE5hbWU6ICdBZG1pbicsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQWRtaW5pc3RyYXRvcnMgd2l0aCBmdWxsIHN5c3RlbSBhY2Nlc3MgaW5jbHVkaW5nIHVzZXIgbWFuYWdlbWVudCcsXHJcbiAgICAgIHByZWNlZGVuY2U6IDEsXHJcbiAgICB9KVxyXG5cclxuICAgIGNvbnN0IGRiYUdyb3VwID0gbmV3IGNvZ25pdG8uQ2ZuVXNlclBvb2xHcm91cCh0aGlzLCAnREJBR3JvdXAnLCB7XHJcbiAgICAgIHVzZXJQb29sSWQ6IHRoaXMudXNlclBvb2wudXNlclBvb2xJZCxcclxuICAgICAgZ3JvdXBOYW1lOiAnREJBJyxcclxuICAgICAgZGVzY3JpcHRpb246ICdEYXRhYmFzZSBhZG1pbmlzdHJhdG9ycyB3aXRoIG9wZXJhdGlvbmFsIGFjY2VzcyB0byBub24tcHJvZHVjdGlvbiBpbnN0YW5jZXMnLFxyXG4gICAgICBwcmVjZWRlbmNlOiAyLFxyXG4gICAgfSlcclxuXHJcbiAgICBjb25zdCByZWFkT25seUdyb3VwID0gbmV3IGNvZ25pdG8uQ2ZuVXNlclBvb2xHcm91cCh0aGlzLCAnUmVhZE9ubHlHcm91cCcsIHtcclxuICAgICAgdXNlclBvb2xJZDogdGhpcy51c2VyUG9vbC51c2VyUG9vbElkLFxyXG4gICAgICBncm91cE5hbWU6ICdSZWFkT25seScsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnUmVhZC1vbmx5IHVzZXJzIHdpdGggdmlldy1vbmx5IGFjY2VzcyB0byBhbGwgZGFzaGJvYXJkcycsXHJcbiAgICAgIHByZWNlZGVuY2U6IDMsXHJcbiAgICB9KVxyXG5cclxuICAgIC8vIENyZWF0ZSBBcHAgQ2xpZW50IGZvciBXZWIgQXBwbGljYXRpb25cclxuICAgIHRoaXMudXNlclBvb2xDbGllbnQgPSB0aGlzLnVzZXJQb29sLmFkZENsaWVudCgnV2ViQ2xpZW50Jywge1xyXG4gICAgICB1c2VyUG9vbENsaWVudE5hbWU6ICdyZHMtZGFzaGJvYXJkLXdlYicsXHJcbiAgICAgIGdlbmVyYXRlU2VjcmV0OiBmYWxzZSwgLy8gUHVibGljIGNsaWVudCAoU1BBKVxyXG4gICAgICBhdXRoRmxvd3M6IHtcclxuICAgICAgICB1c2VyUGFzc3dvcmQ6IGZhbHNlLFxyXG4gICAgICAgIHVzZXJTcnA6IGZhbHNlLFxyXG4gICAgICAgIGN1c3RvbTogZmFsc2UsXHJcbiAgICAgIH0sXHJcbiAgICAgIG9BdXRoOiB7XHJcbiAgICAgICAgZmxvd3M6IHtcclxuICAgICAgICAgIGF1dGhvcml6YXRpb25Db2RlR3JhbnQ6IHRydWUsXHJcbiAgICAgICAgICBpbXBsaWNpdENvZGVHcmFudDogZmFsc2UsXHJcbiAgICAgICAgfSxcclxuICAgICAgICBzY29wZXM6IFtcclxuICAgICAgICAgIGNvZ25pdG8uT0F1dGhTY29wZS5PUEVOSUQsXHJcbiAgICAgICAgICBjb2duaXRvLk9BdXRoU2NvcGUuRU1BSUwsXHJcbiAgICAgICAgICBjb2duaXRvLk9BdXRoU2NvcGUuUFJPRklMRSxcclxuICAgICAgICBdLFxyXG4gICAgICAgIGNhbGxiYWNrVXJsczogW1xyXG4gICAgICAgICAgZnJvbnRlbmREb21haW4gPyBgaHR0cHM6Ly8ke2Zyb250ZW5kRG9tYWlufS9jYWxsYmFja2AgOiAnaHR0cDovL2xvY2FsaG9zdDo1MTczL2NhbGxiYWNrJyxcclxuICAgICAgICAgICdodHRwOi8vbG9jYWxob3N0OjUxNzMvY2FsbGJhY2snLCAvLyBWaXRlIGRldiBzZXJ2ZXJcclxuICAgICAgICAgICdodHRwOi8vbG9jYWxob3N0OjMwMDAvY2FsbGJhY2snLCAvLyBBbHRlcm5hdGl2ZSBkZXYgc2VydmVyXHJcbiAgICAgICAgXSxcclxuICAgICAgICBsb2dvdXRVcmxzOiBbXHJcbiAgICAgICAgICBmcm9udGVuZERvbWFpbiA/IGBodHRwczovLyR7ZnJvbnRlbmREb21haW59L2AgOiAnaHR0cDovL2xvY2FsaG9zdDo1MTczLycsXHJcbiAgICAgICAgICAnaHR0cDovL2xvY2FsaG9zdDo1MTczLycsIC8vIFZpdGUgZGV2IHNlcnZlclxyXG4gICAgICAgICAgJ2h0dHA6Ly9sb2NhbGhvc3Q6MzAwMC8nLCAvLyBBbHRlcm5hdGl2ZSBkZXYgc2VydmVyXHJcbiAgICAgICAgXSxcclxuICAgICAgfSxcclxuICAgICAgYWNjZXNzVG9rZW5WYWxpZGl0eTogY2RrLkR1cmF0aW9uLmhvdXJzKDEpLFxyXG4gICAgICBpZFRva2VuVmFsaWRpdHk6IGNkay5EdXJhdGlvbi5ob3VycygxKSxcclxuICAgICAgcmVmcmVzaFRva2VuVmFsaWRpdHk6IGNkay5EdXJhdGlvbi5kYXlzKDMwKSxcclxuICAgICAgcHJldmVudFVzZXJFeGlzdGVuY2VFcnJvcnM6IHRydWUsXHJcbiAgICAgIC8vIEVuYWJsZSBQS0NFIGZvciBwdWJsaWMgY2xpZW50cyAocmVxdWlyZWQgZm9yIHNlY3VyZSBhdXRob3JpemF0aW9uIGNvZGUgZmxvdyB3aXRob3V0IGNsaWVudCBzZWNyZXQpXHJcbiAgICAgIGVuYWJsZVRva2VuUmV2b2NhdGlvbjogdHJ1ZSxcclxuICAgIH0pXHJcblxyXG4gICAgLy8gRXhwbGljaXRseSBjb25maWd1cmUgUEtDRSBzdXBwb3J0IHVzaW5nIEwxIGNvbnN0cnVjdFxyXG4gICAgY29uc3QgY2ZuVXNlclBvb2xDbGllbnQgPSB0aGlzLnVzZXJQb29sQ2xpZW50Lm5vZGUuZGVmYXVsdENoaWxkIGFzIGNvZ25pdG8uQ2ZuVXNlclBvb2xDbGllbnRcclxuICAgIGNmblVzZXJQb29sQ2xpZW50LmFkZFByb3BlcnR5T3ZlcnJpZGUoJ0FsbG93ZWRPQXV0aEZsb3dzVXNlclBvb2xDbGllbnQnLCB0cnVlKVxyXG4gICAgY2ZuVXNlclBvb2xDbGllbnQuYWRkUHJvcGVydHlPdmVycmlkZSgnU3VwcG9ydGVkSWRlbnRpdHlQcm92aWRlcnMnLCBbJ0NPR05JVE8nXSlcclxuICAgIFxyXG4gICAgLy8gRW5zdXJlIFBLQ0UgaXMgc3VwcG9ydGVkIGJ5IGVuYWJsaW5nIHRoZSBjb3JyZWN0IGF1dGggZmxvd3NcclxuICAgIC8vIEZvciBwdWJsaWMgY2xpZW50cyAobm8gc2VjcmV0KSwgQ29nbml0byBhdXRvbWF0aWNhbGx5IHJlcXVpcmVzIFBLQ0UgZm9yIGF1dGhvcml6YXRpb24gY29kZSBmbG93XHJcbiAgICBjZm5Vc2VyUG9vbENsaWVudC5hZGRQcm9wZXJ0eU92ZXJyaWRlKCdFeHBsaWNpdEF1dGhGbG93cycsIFtcclxuICAgICAgJ0FMTE9XX1VTRVJfU1JQX0FVVEgnLFxyXG4gICAgICAnQUxMT1dfUkVGUkVTSF9UT0tFTl9BVVRIJ1xyXG4gICAgXSlcclxuXHJcbiAgICAvLyBDcmVhdGUgSG9zdGVkIFVJIERvbWFpblxyXG4gICAgdGhpcy51c2VyUG9vbERvbWFpbiA9IHRoaXMudXNlclBvb2wuYWRkRG9tYWluKCdEb21haW4nLCB7XHJcbiAgICAgIGNvZ25pdG9Eb21haW46IHtcclxuICAgICAgICBkb21haW5QcmVmaXg6IGByZHMtZGFzaGJvYXJkLWF1dGgtJHtjZGsuQXdzLkFDQ09VTlRfSUR9YCxcclxuICAgICAgfSxcclxuICAgIH0pXHJcblxyXG4gICAgLy8gT3V0cHV0c1xyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ1VzZXJQb29sSWQnLCB7XHJcbiAgICAgIHZhbHVlOiB0aGlzLnVzZXJQb29sLnVzZXJQb29sSWQsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ29nbml0byBVc2VyIFBvb2wgSUQnLFxyXG4gICAgICBleHBvcnROYW1lOiBgJHtpZH0tVXNlclBvb2xJZGAsXHJcbiAgICB9KVxyXG5cclxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdVc2VyUG9vbEFybicsIHtcclxuICAgICAgdmFsdWU6IHRoaXMudXNlclBvb2wudXNlclBvb2xBcm4sXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ29nbml0byBVc2VyIFBvb2wgQVJOJyxcclxuICAgICAgZXhwb3J0TmFtZTogYCR7aWR9LVVzZXJQb29sQXJuYCxcclxuICAgIH0pXHJcblxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ1VzZXJQb29sQ2xpZW50SWQnLCB7XHJcbiAgICAgIHZhbHVlOiB0aGlzLnVzZXJQb29sQ2xpZW50LnVzZXJQb29sQ2xpZW50SWQsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ29nbml0byBVc2VyIFBvb2wgQ2xpZW50IElEJyxcclxuICAgICAgZXhwb3J0TmFtZTogYCR7aWR9LVVzZXJQb29sQ2xpZW50SWRgLFxyXG4gICAgfSlcclxuXHJcbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnVXNlclBvb2xEb21haW4nLCB7XHJcbiAgICAgIHZhbHVlOiB0aGlzLnVzZXJQb29sRG9tYWluLmRvbWFpbk5hbWUsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ29nbml0byBIb3N0ZWQgVUkgRG9tYWluJyxcclxuICAgICAgZXhwb3J0TmFtZTogYCR7aWR9LVVzZXJQb29sRG9tYWluYCxcclxuICAgIH0pXHJcblxyXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0hvc3RlZFVJVXJsJywge1xyXG4gICAgICB2YWx1ZTogYGh0dHBzOi8vJHt0aGlzLnVzZXJQb29sRG9tYWluLmRvbWFpbk5hbWV9LmF1dGguJHtjZGsuQXdzLlJFR0lPTn0uYW1hem9uY29nbml0by5jb21gLFxyXG4gICAgICBkZXNjcmlwdGlvbjogJ0NvZ25pdG8gSG9zdGVkIFVJIFVSTCcsXHJcbiAgICB9KVxyXG5cclxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdKd3RJc3N1ZXInLCB7XHJcbiAgICAgIHZhbHVlOiBgaHR0cHM6Ly9jb2duaXRvLWlkcC4ke2Nkay5Bd3MuUkVHSU9OfS5hbWF6b25hd3MuY29tLyR7dGhpcy51c2VyUG9vbC51c2VyUG9vbElkfWAsXHJcbiAgICAgIGRlc2NyaXB0aW9uOiAnSldUIFRva2VuIElzc3VlciBVUkwnLFxyXG4gICAgICBleHBvcnROYW1lOiBgJHtpZH0tSnd0SXNzdWVyYCxcclxuICAgIH0pXHJcblxyXG4gICAgLy8gVGFnc1xyXG4gICAgY2RrLlRhZ3Mub2YodGhpcykuYWRkKCdQcm9qZWN0JywgJ1JEUy1PcGVyYXRpb25zLURhc2hib2FyZCcpXHJcbiAgICBjZGsuVGFncy5vZih0aGlzKS5hZGQoJ0NvbXBvbmVudCcsICdBdXRoZW50aWNhdGlvbicpXHJcbiAgfVxyXG59XHJcbiJdfQ==