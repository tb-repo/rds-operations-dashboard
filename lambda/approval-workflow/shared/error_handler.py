"""
Intelligent Error Handler

Provides actionable error messages with remediation steps.
Includes Lambda error handling decorator with correlation ID support.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-04T10:00:00Z",
  "version": "2.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.3 → DESIGN-ErrorHandling → TASK-6.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

from typing import Dict, Any, Optional, Callable
from datetime import datetime
from functools import wraps
import json
import traceback


class ActionableError:
    """
    Represents an error with context and remediation steps.
    """
    
    def __init__(
        self,
        error_type: str,
        error_message: str,
        context: Dict[str, Any],
        severity: str = "warning",
        remediation: Optional[Dict[str, Any]] = None
    ):
        self.error_type = error_type
        self.error_message = error_message
        self.context = context
        self.severity = severity  # info, warning, error, critical
        self.remediation = remediation or {}
        self.timestamp = datetime.utcnow().isoformat() + 'Z'
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            'error_type': self.error_type,
            'error_message': self.error_message,
            'context': self.context,
            'severity': self.severity,
            'remediation': self.remediation,
            'timestamp': self.timestamp
        }


class ErrorCatalog:
    """
    Catalog of known errors with remediation steps.
    """
    
    @staticmethod
    def cross_account_access_denied(account_id: str, region: str, role_name: str) -> ActionableError:
        """Cross-account role assumption failed."""
        return ActionableError(
            error_type="CrossAccountAccessDenied",
            error_message=f"Cannot access account {account_id} in region {region}",
            context={
                'account_id': account_id,
                'region': region,
                'role_name': role_name
            },
            severity="warning",
            remediation={
                'title': "Cross-Account Role Not Configured",
                'description': f"The dashboard cannot discover RDS instances in account {account_id} because the cross-account IAM role is not set up.",
                'impact': "RDS instances in this account will not be visible in the dashboard.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': f"Create IAM role '{role_name}' in account {account_id}",
                        'details': "This role allows the dashboard to read RDS instance information."
                    },
                    {
                        'step': 2,
                        'action': "Configure trust relationship",
                        'details': f"Allow the dashboard Lambda role to assume this role with the configured external ID."
                    },
                    {
                        'step': 3,
                        'action': "Attach required permissions",
                        'details': "Grant rds:Describe*, cloudwatch:GetMetricStatistics, and tag:GetResources permissions."
                    }
                ],
                'documentation_link': "/docs/cross-account-setup.md",
                'can_skip': True,
                'skip_reason': "Discovery will continue in other configured accounts and regions."
            }
        )
    
    @staticmethod
    def region_not_enabled(account_id: str, region: str) -> ActionableError:
        """AWS region is not enabled in the account."""
        return ActionableError(
            error_type="RegionNotEnabled",
            error_message=f"Region {region} is not enabled in account {account_id}",
            context={
                'account_id': account_id,
                'region': region
            },
            severity="info",
            remediation={
                'title': "AWS Region Not Enabled",
                'description': f"Region {region} is not enabled in account {account_id}. This is normal if you don't use this region.",
                'impact': "No RDS instances will be discovered in this region.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': "Enable the region (optional)",
                        'details': f"Go to AWS Console → Account Settings → Enable {region}"
                    },
                    {
                        'step': 2,
                        'action': "Or remove from configuration",
                        'details': f"Update TARGET_REGIONS environment variable to exclude {region}"
                    }
                ],
                'can_skip': True,
                'skip_reason': "Discovery will continue in other enabled regions."
            }
        )
    
    @staticmethod
    def insufficient_permissions(account_id: str, region: str, missing_permissions: list) -> ActionableError:
        """Lambda role lacks required permissions."""
        return ActionableError(
            error_type="InsufficientPermissions",
            error_message=f"Missing permissions in account {account_id}, region {region}",
            context={
                'account_id': account_id,
                'region': region,
                'missing_permissions': missing_permissions
            },
            severity="error",
            remediation={
                'title': "Insufficient IAM Permissions",
                'description': "The dashboard Lambda role does not have all required permissions.",
                'impact': "Cannot discover or monitor RDS instances properly.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': "Update IAM role policy",
                        'details': f"Add these permissions: {', '.join(missing_permissions)}"
                    },
                    {
                        'step': 2,
                        'action': "Verify policy attachment",
                        'details': "Ensure the policy is attached to the Lambda execution role."
                    },
                    {
                        'step': 3,
                        'action': "Wait for propagation",
                        'details': "IAM changes may take up to 60 seconds to propagate."
                    }
                ],
                'documentation_link': "/docs/iam-permissions.md",
                'can_skip': False,
                'skip_reason': None
            }
        )
    
    @staticmethod
    def no_rds_instances(account_id: str, region: str) -> ActionableError:
        """No RDS instances found in the region."""
        return ActionableError(
            error_type="NoInstancesFound",
            error_message=f"No RDS instances found in account {account_id}, region {region}",
            context={
                'account_id': account_id,
                'region': region
            },
            severity="info",
            remediation={
                'title': "No RDS Instances Discovered",
                'description': f"No RDS instances were found in {region}. This is normal if you don't have RDS instances in this region.",
                'impact': "No impact - this is informational only.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': "Verify RDS instances exist",
                        'details': f"Check AWS Console → RDS → {region} to confirm instances exist."
                    },
                    {
                        'step': 2,
                        'action': "Check filters (if applicable)",
                        'details': "Ensure no tag-based filters are excluding your instances."
                    }
                ],
                'can_skip': True,
                'skip_reason': "This is informational - no action needed if you don't use RDS in this region."
            }
        )
    
    @staticmethod
    def generic_error(error: Exception, context: Dict[str, Any]) -> ActionableError:
        """Generic error with basic remediation."""
        error_type = type(error).__name__
        error_message = str(error)
        
        return ActionableError(
            error_type=error_type,
            error_message=error_message,
            context=context,
            severity="error",
            remediation={
                'title': f"Unexpected Error: {error_type}",
                'description': error_message,
                'impact': "Discovery may be incomplete for this account/region.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': "Check CloudWatch Logs",
                        'details': "Review Lambda logs for detailed error information."
                    },
                    {
                        'step': 2,
                        'action': "Verify AWS service status",
                        'details': "Check https://status.aws.amazon.com/ for service issues."
                    },
                    {
                        'step': 3,
                        'action': "Retry discovery",
                        'details': "Manually trigger discovery again or wait for next scheduled run."
                    }
                ],
                'can_skip': True,
                'skip_reason': "Discovery will continue in other accounts/regions."
            }
        )


def categorize_aws_error(error: Exception, context: Dict[str, Any]) -> ActionableError:
    """
    Categorize AWS errors and provide actionable remediation.
    
    Args:
        error: The exception that occurred
        context: Context information (account_id, region, etc.)
    
    Returns:
        ActionableError with remediation steps
    """
    error_message = str(error)
    error_type = type(error).__name__
    
    account_id = context.get('account_id', 'unknown')
    region = context.get('region', 'unknown')
    
    # AccessDenied errors
    if 'AccessDenied' in error_message or 'not authorized' in error_message:
        if 'AssumeRole' in error_message:
            role_name = context.get('role_name', 'RDSDashboardCrossAccountRole')
            return ErrorCatalog.cross_account_access_denied(account_id, region, role_name)
        else:
            # Extract missing permissions if possible
            missing_perms = ['rds:DescribeDBInstances']  # Default
            return ErrorCatalog.insufficient_permissions(account_id, region, missing_perms)
    
    # Region not enabled
    if 'OptInRequired' in error_message or 'not subscribed' in error_message:
        return ErrorCatalog.region_not_enabled(account_id, region)
    
    # Throttling
    if 'Throttling' in error_message or 'Rate exceeded' in error_message:
        return ActionableError(
            error_type="ThrottlingException",
            error_message=f"AWS API rate limit exceeded in {region}",
            context=context,
            severity="warning",
            remediation={
                'title': "AWS API Rate Limit Exceeded",
                'description': "Too many API calls to AWS services. This is temporary.",
                'impact': "Discovery may be delayed but will retry automatically.",
                'required_actions': [
                    {
                        'step': 1,
                        'action': "Wait and retry",
                        'details': "AWS will automatically allow requests after the rate limit window passes."
                    },
                    {
                        'step': 2,
                        'action': "Consider request throttling",
                        'details': "If this happens frequently, contact AWS support to increase limits."
                    }
                ],
                'can_skip': True,
                'skip_reason': "Discovery will retry automatically on next scheduled run."
            }
        )
    
    # Generic error
    return ErrorCatalog.generic_error(error, context)


# HTTP Status Code Mapping
ERROR_STATUS_CODES = {
    'ValidationError': 400,
    'ValueError': 400,
    'KeyError': 400,
    'TypeError': 400,
    'AccessDenied': 403,
    'Forbidden': 403,
    'InsufficientPermissions': 403,
    'NotFound': 404,
    'ResourceNotFound': 404,
    'Conflict': 409,
    'ThrottlingException': 429,
    'TooManyRequests': 429,
    'InternalError': 500,
    'ServiceUnavailable': 503,
    'Timeout': 504,
}


def get_status_code(error: Exception) -> int:
    """
    Map exception to HTTP status code.
    
    Args:
        error: The exception
    
    Returns:
        HTTP status code
    """
    error_type = type(error).__name__
    error_message = str(error)
    
    # Check error type
    if error_type in ERROR_STATUS_CODES:
        return ERROR_STATUS_CODES[error_type]
    
    # Check error message for keywords
    for keyword, status_code in ERROR_STATUS_CODES.items():
        if keyword.lower() in error_message.lower():
            return status_code
    
    # Default to 500
    return 500


def handle_lambda_error(func: Callable) -> Callable:
    """
    Decorator for Lambda handlers to provide consistent error handling.
    
    Features:
    - Catches all exceptions
    - Maps to appropriate HTTP status codes
    - Includes correlation IDs in error responses
    - Logs errors with full context
    - Returns properly formatted error responses
    
    Usage:
        @handle_lambda_error
        def lambda_handler(event, context):
            # Your handler code
            pass
    """
    @wraps(func)
    def wrapper(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
        correlation_id = None
        
        try:
            # Extract correlation ID if present
            correlation_id = event.get('headers', {}).get('X-Correlation-ID')
            if not correlation_id:
                correlation_id = event.get('requestContext', {}).get('requestId', 'unknown')
            
            # Call the actual handler
            return func(event, context)
            
        except Exception as e:
            # Get status code
            status_code = get_status_code(e)
            
            # Build error context
            error_context = {
                'function_name': getattr(context, 'function_name', 'unknown'),
                'request_id': getattr(context, 'aws_request_id', 'unknown'),
                'correlation_id': correlation_id,
                'error_type': type(e).__name__,
                'error_message': str(e),
                'traceback': traceback.format_exc()
            }
            
            # Try to categorize AWS errors
            actionable_error = None
            if 'boto' in str(type(e).__module__).lower() or 'botocore' in str(type(e).__module__).lower():
                try:
                    actionable_error = categorize_aws_error(e, error_context)
                except:
                    pass
            
            # Build error response
            error_response = {
                'error': type(e).__name__,
                'message': str(e),
                'correlation_id': correlation_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            
            # Add actionable error details if available
            if actionable_error:
                error_response['actionable_error'] = actionable_error.to_dict()
            
            # Log the error (will be picked up by structured logger if configured)
            print(json.dumps({
                'level': 'ERROR',
                'message': f'Lambda handler error: {type(e).__name__}',
                'correlation_id': correlation_id,
                'error': error_response,
                'context': error_context
            }))
            
            # Return error response
            return {
                'statusCode': status_code,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Correlation-ID': correlation_id or 'unknown'
                },
                'body': json.dumps(error_response)
            }
    
    return wrapper
