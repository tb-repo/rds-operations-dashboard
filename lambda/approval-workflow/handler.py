"""
RDS Operations Approval Workflow Service

Manages approval workflow for high-risk RDS operations.
Supports single and dual approval requirements based on operation risk level.

Requirements: REQ-APPROVAL (Operations Approval Workflow), REQ-5.1 (structured logging)


Governance Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-02T14:33:09.286788+00:00",
  "version": "1.1.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-10.1, REQ-10.2, REQ-10.3 → DESIGN-001 → TASK-10",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": None,
  "approved_by": None
}
"""

import json
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

# Shared imports
import sys
sys.path.append('/opt/python')
from shared.logger import StructuredLogger
from shared.aws_clients import AWSClients
from shared.config import Config

logger = StructuredLogger("approval-workflow")


class ApprovalWorkflowService:
    """Manage approval workflow for RDS operations."""
    
    # Approval statuses
    STATUS_PENDING = 'pending'
    STATUS_APPROVED = 'approved'
    STATUS_REJECTED = 'rejected'
    STATUS_EXPIRED = 'expired'
    STATUS_EXECUTED = 'executed'
    STATUS_CANCELLED = 'cancelled'
    
    # Risk levels
    RISK_LOW = 'low'
    RISK_MEDIUM = 'medium'
    RISK_HIGH = 'high'
    
    # Approval requirements by risk level
    APPROVAL_REQUIREMENTS = {
        RISK_LOW: {'approvals_required': 0, 'auto_approve': True},
        RISK_MEDIUM: {'approvals_required': 1, 'auto_approve': False},
        RISK_HIGH: {'approvals_required': 2, 'auto_approve': False}
    }
    
    # Expiration time (hours)
    EXPIRATION_HOURS = 72  # 3 days
    
    def __init__(self):
        """Initialize approval workflow service."""
        self.dynamodb = AWSClients.get_dynamodb_resource()
        self.sns = boto3.client('sns')
        self.config = Config.load()
        
        # DynamoDB tables
        self.approvals_table_name = os.environ.get('APPROVALS_TABLE', 'rds-approvals-prod')
        self.approvals_table = self.dynamodb.Table(self.approvals_table_name)
        self.audit_table_name = os.environ.get('AUDIT_LOG_TABLE', 'audit-log-prod')
        self.audit_table = self.dynamodb.Table(self.audit_table_name)
        
        # SNS topic for notifications
        self.sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    def create_approval_request(
        self,
        operation_type: str,
        instance_id: str,
        parameters: Dict[str, Any],
        requested_by: str,
        risk_level: str,
        environment: str,
        justification: str,
        estimated_cost: Optional[float] = None,
        estimated_duration: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Create a new approval request.
        
        Args:
            operation_type: Type of operation (e.g., 'modify_instance_class')
            instance_id: RDS instance identifier
            parameters: Operation parameters
            requested_by: User email who requested the operation
            risk_level: Risk level (low, medium, high)
            environment: Environment (production, non-production)
            justification: Reason for the operation
            estimated_cost: Estimated cost impact
            estimated_duration: Estimated duration
            
        Returns:
            dict: Created approval request
        """
        try:
            # Generate request ID
            request_id = str(uuid.uuid4())
            
            # Get approval requirements
            requirements = self.APPROVAL_REQUIREMENTS.get(
                risk_level,
                self.APPROVAL_REQUIREMENTS[self.RISK_MEDIUM]
            )
            
            # Calculate expiration
            expiration_time = datetime.utcnow() + timedelta(hours=self.EXPIRATION_HOURS)
            
            # Determine initial status
            if requirements['auto_approve']:
                status = self.STATUS_APPROVED
                approved_by = ['system']
                approved_at = datetime.utcnow().isoformat()
            else:
                status = self.STATUS_PENDING
                approved_by = []
                approved_at = None
            
            # Create approval request
            approval_request = {
                'request_id': request_id,
                'operation_type': operation_type,
                'instance_id': instance_id,
                'parameters': parameters,
                'requested_by': requested_by,
                'requested_at': datetime.utcnow().isoformat(),
                'risk_level': risk_level,
                'environment': environment,
                'justification': justification,
                'estimated_cost': Decimal(str(estimated_cost)) if estimated_cost else None,
                'estimated_duration': estimated_duration,
                'status': status,
                'approvals_required': requirements['approvals_required'],
                'approvals_received': len(approved_by),
                'approved_by': approved_by,
                'approved_at': approved_at,
                'rejected_by': None,
                'rejected_at': None,
                'rejection_reason': None,
                'expires_at': expiration_time.isoformat(),
                'executed_at': None,
                'execution_result': None,
                'comments': []
            }
            
            # Save to DynamoDB
            self.approvals_table.put_item(Item=approval_request)
            
            logger.info(f"Created approval request {request_id}", extra={
                'request_id': request_id,
                'operation_type': operation_type,
                'instance_id': instance_id,
                'risk_level': risk_level,
                'status': status
            })
            
            # Send notification if approval required
            if not requirements['auto_approve']:
                self._send_approval_notification(approval_request)
            
            # Log to audit table
            self._log_audit_event(
                'APPROVAL_REQUEST_CREATED',
                requested_by,
                request_id,
                approval_request
            )
            
            return approval_request
            
        except Exception as e:
            logger.error(f"Error creating approval request: {str(e)}")
            raise
    
    def approve_request(
        self,
        request_id: str,
        approved_by: str,
        comments: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Approve an approval request.
        
        Args:
            request_id: Approval request ID
            approved_by: User email who approved
            comments: Optional approval comments
            
        Returns:
            dict: Updated approval request
        """
        try:
            # Get current request
            request = self._get_request(request_id)
            
            if not request:
                raise ValueError(f"Approval request {request_id} not found")
            
            # Validate status
            if request['status'] != self.STATUS_PENDING:
                raise ValueError(f"Cannot approve request with status {request['status']}")
            
            # Check if already approved by this user
            if approved_by in request.get('approved_by', []):
                raise ValueError(f"Request already approved by {approved_by}")
            
            # Check if requester is trying to approve their own request
            if approved_by == request['requested_by']:
                raise ValueError("Cannot approve your own request")
            
            # Add approval
            approved_by_list = request.get('approved_by', [])
            approved_by_list.append(approved_by)
            
            # Add comment if provided
            comments_list = request.get('comments', [])
            if comments:
                comments_list.append({
                    'user': approved_by,
                    'timestamp': datetime.utcnow().isoformat(),
                    'action': 'approved',
                    'comment': comments
                })
            
            # Check if all approvals received
            approvals_received = len(approved_by_list)
            approvals_required = request['approvals_required']
            
            new_status = self.STATUS_PENDING
            approved_at = None
            
            if approvals_received >= approvals_required:
                new_status = self.STATUS_APPROVED
                approved_at = datetime.utcnow().isoformat()
            
            # Update request
            self.approvals_table.update_item(
                Key={'request_id': request_id},
                UpdateExpression='SET #status = :status, approved_by = :approved_by, '
                                'approvals_received = :approvals_received, '
                                'approved_at = :approved_at, comments = :comments',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': new_status,
                    ':approved_by': approved_by_list,
                    ':approvals_received': approvals_received,
                    ':approved_at': approved_at,
                    ':comments': comments_list
                }
            )
            
            logger.info(f"Approval added to request {request_id}", extra={
                'request_id': request_id,
                'approved_by': approved_by,
                'approvals_received': approvals_received,
                'approvals_required': approvals_required,
                'new_status': new_status
            })
            
            # Send notification
            if new_status == self.STATUS_APPROVED:
                self._send_approved_notification(request, approved_by_list)
            
            # Log to audit
            self._log_audit_event(
                'APPROVAL_GRANTED',
                approved_by,
                request_id,
                {'approvals_received': approvals_received, 'status': new_status}
            )
            
            # Get updated request
            return self._get_request(request_id)
            
        except Exception as e:
            logger.error(f"Error approving request: {str(e)}")
            raise
    
    def reject_request(
        self,
        request_id: str,
        rejected_by: str,
        reason: str
    ) -> Dict[str, Any]:
        """
        Reject an approval request.
        
        Args:
            request_id: Approval request ID
            rejected_by: User email who rejected
            reason: Rejection reason
            
        Returns:
            dict: Updated approval request
        """
        try:
            # Get current request
            request = self._get_request(request_id)
            
            if not request:
                raise ValueError(f"Approval request {request_id} not found")
            
            # Validate status
            if request['status'] != self.STATUS_PENDING:
                raise ValueError(f"Cannot reject request with status {request['status']}")
            
            # Add comment
            comments_list = request.get('comments', [])
            comments_list.append({
                'user': rejected_by,
                'timestamp': datetime.utcnow().isoformat(),
                'action': 'rejected',
                'comment': reason
            })
            
            # Update request
            self.approvals_table.update_item(
                Key={'request_id': request_id},
                UpdateExpression='SET #status = :status, rejected_by = :rejected_by, '
                                'rejected_at = :rejected_at, rejection_reason = :reason, '
                                'comments = :comments',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': self.STATUS_REJECTED,
                    ':rejected_by': rejected_by,
                    ':rejected_at': datetime.utcnow().isoformat(),
                    ':reason': reason,
                    ':comments': comments_list
                }
            )
            
            logger.info(f"Request {request_id} rejected", extra={
                'request_id': request_id,
                'rejected_by': rejected_by,
                'reason': reason
            })
            
            # Send notification
            self._send_rejected_notification(request, rejected_by, reason)
            
            # Log to audit
            self._log_audit_event(
                'APPROVAL_REJECTED',
                rejected_by,
                request_id,
                {'reason': reason}
            )
            
            # Get updated request
            return self._get_request(request_id)
            
        except Exception as e:
            logger.error(f"Error rejecting request: {str(e)}")
            raise
    
    def cancel_request(
        self,
        request_id: str,
        cancelled_by: str,
        reason: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Cancel an approval request.
        
        Args:
            request_id: Approval request ID
            cancelled_by: User email who cancelled
            reason: Optional cancellation reason
            
        Returns:
            dict: Updated approval request
        """
        try:
            # Get current request
            request = self._get_request(request_id)
            
            if not request:
                raise ValueError(f"Approval request {request_id} not found")
            
            # Only requester can cancel
            if cancelled_by != request['requested_by']:
                raise ValueError("Only the requester can cancel the request")
            
            # Validate status
            if request['status'] not in [self.STATUS_PENDING, self.STATUS_APPROVED]:
                raise ValueError(f"Cannot cancel request with status {request['status']}")
            
            # Update request
            self.approvals_table.update_item(
                Key={'request_id': request_id},
                UpdateExpression='SET #status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': self.STATUS_CANCELLED
                }
            )
            
            logger.info(f"Request {request_id} cancelled", extra={
                'request_id': request_id,
                'cancelled_by': cancelled_by
            })
            
            # Log to audit
            self._log_audit_event(
                'APPROVAL_CANCELLED',
                cancelled_by,
                request_id,
                {'reason': reason}
            )
            
            # Get updated request
            return self._get_request(request_id)
            
        except Exception as e:
            logger.error(f"Error cancelling request: {str(e)}")
            raise
    
    def mark_executed(
        self,
        request_id: str,
        execution_result: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Mark an approval request as executed.
        
        Args:
            request_id: Approval request ID
            execution_result: Result of the operation execution
            
        Returns:
            dict: Updated approval request
        """
        try:
            # Update request
            self.approvals_table.update_item(
                Key={'request_id': request_id},
                UpdateExpression='SET #status = :status, executed_at = :executed_at, '
                                'execution_result = :result',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': self.STATUS_EXECUTED,
                    ':executed_at': datetime.utcnow().isoformat(),
                    ':result': execution_result
                }
            )
            
            logger.info(f"Request {request_id} marked as executed")
            
            return self._get_request(request_id)
            
        except Exception as e:
            logger.error(f"Error marking request as executed: {str(e)}")
            raise
    
    def get_pending_approvals(
        self,
        user_email: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Get pending approval requests.
        
        Args:
            user_email: Optional filter by user (requests they can approve)
            
        Returns:
            list: Pending approval requests
        """
        try:
            # Scan for pending requests
            response = self.approvals_table.scan(
                FilterExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': self.STATUS_PENDING}
            )
            
            requests = response.get('Items', [])
            
            # Filter out expired requests
            now = datetime.utcnow()
            active_requests = []
            
            for request in requests:
                expires_at = datetime.fromisoformat(request['expires_at'])
                if expires_at > now:
                    # Filter by user if specified
                    if user_email:
                        # User can approve if they didn't request it and haven't approved yet
                        if (request['requested_by'] != user_email and
                            user_email not in request.get('approved_by', [])):
                            active_requests.append(request)
                    else:
                        active_requests.append(request)
            
            return active_requests
            
        except Exception as e:
            logger.error(f"Error getting pending approvals: {str(e)}")
            raise
    
    def get_user_requests(
        self,
        user_email: str,
        status: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Get approval requests created by a user.
        
        Args:
            user_email: User email
            status: Optional status filter
            
        Returns:
            list: User's approval requests
        """
        try:
            # Scan for user's requests
            filter_expression = 'requested_by = :user'
            expression_values = {':user': user_email}
            
            if status:
                filter_expression += ' AND #status = :status'
                expression_values[':status'] = status
            
            response = self.approvals_table.scan(
                FilterExpression=filter_expression,
                ExpressionAttributeNames={'#status': 'status'} if status else None,
                ExpressionAttributeValues=expression_values
            )
            
            return response.get('Items', [])
            
        except Exception as e:
            logger.error(f"Error getting user requests: {str(e)}")
            raise
    
    def _get_request(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Get approval request by ID."""
        try:
            response = self.approvals_table.get_item(Key={'request_id': request_id})
            return response.get('Item')
        except Exception as e:
            logger.error(f"Error getting request: {str(e)}")
            return None
    
    def _send_approval_notification(self, request: Dict[str, Any]):
        """Send notification for new approval request."""
        if not self.sns_topic_arn:
            return
        
        try:
            message = f"""
New RDS Operation Approval Request

Request ID: {request['request_id']}
Operation: {request['operation_type']}
Instance: {request['instance_id']}
Environment: {request['environment']}
Risk Level: {request['risk_level']}
Requested By: {request['requested_by']}
Justification: {request['justification']}
Approvals Required: {request['approvals_required']}
Expires: {request['expires_at']}

Please review and approve/reject this request in the RDS Operations Dashboard.
            """
            
            self.sns.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"RDS Operation Approval Required: {request['operation_type']}",
                Message=message
            )
        except Exception as e:
            logger.error(f"Error sending approval notification: {str(e)}")
    
    def _send_approved_notification(self, request: Dict[str, Any], approved_by: List[str]):
        """Send notification when request is fully approved."""
        if not self.sns_topic_arn:
            return
        
        try:
            message = f"""
RDS Operation Approved

Request ID: {request['request_id']}
Operation: {request['operation_type']}
Instance: {request['instance_id']}
Requested By: {request['requested_by']}
Approved By: {', '.join(approved_by)}

The operation can now be executed.
            """
            
            self.sns.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"RDS Operation Approved: {request['operation_type']}",
                Message=message
            )
        except Exception as e:
            logger.error(f"Error sending approved notification: {str(e)}")
    
    def _send_rejected_notification(self, request: Dict[str, Any], rejected_by: str, reason: str):
        """Send notification when request is rejected."""
        if not self.sns_topic_arn:
            return
        
        try:
            message = f"""
RDS Operation Rejected

Request ID: {request['request_id']}
Operation: {request['operation_type']}
Instance: {request['instance_id']}
Requested By: {request['requested_by']}
Rejected By: {rejected_by}
Reason: {reason}
            """
            
            self.sns.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"RDS Operation Rejected: {request['operation_type']}",
                Message=message
            )
        except Exception as e:
            logger.error(f"Error sending rejected notification: {str(e)}")
    
    def _log_audit_event(
        self,
        event_type: str,
        user: str,
        request_id: str,
        details: Dict[str, Any]
    ):
        """Log event to audit table."""
        try:
            audit_entry = {
                'event_id': str(uuid.uuid4()),
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': event_type,
                'user': user,
                'request_id': request_id,
                'details': details
            }
            
            self.audit_table.put_item(Item=audit_entry)
        except Exception as e:
            logger.error(f"Error logging audit event: {str(e)}")


from shared.structured_logger import get_logger
from shared.correlation_middleware import with_correlation_id, CorrelationContext


@with_correlation_id
def lambda_handler(event, context):
    """
    Lambda handler for approval workflow service.
    
    Supported operations:
    - create_request
    - approve_request
    - reject_request
    - cancel_request
    - get_pending_approvals
    - get_user_requests
    - get_request
    """
    try:
        # Parse request
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})
        
        operation = body.get('operation')
        
        if not operation:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Missing required parameter: operation'})
            }
        
        # Initialize service
        service = ApprovalWorkflowService()
        
        # Handle operations
        if operation == 'create_request':
            result = service.create_approval_request(
                operation_type=body['operation_type'],
                instance_id=body['instance_id'],
                parameters=body.get('parameters', {}),
                requested_by=body['requested_by'],
                risk_level=body['risk_level'],
                environment=body['environment'],
                justification=body['justification'],
                estimated_cost=body.get('estimated_cost'),
                estimated_duration=body.get('estimated_duration')
            )
        
        elif operation == 'approve_request':
            result = service.approve_request(
                request_id=body['request_id'],
                approved_by=body['approved_by'],
                comments=body.get('comments')
            )
        
        elif operation == 'reject_request':
            result = service.reject_request(
                request_id=body['request_id'],
                rejected_by=body['rejected_by'],
                reason=body['reason']
            )
        
        elif operation == 'cancel_request':
            result = service.cancel_request(
                request_id=body['request_id'],
                cancelled_by=body['cancelled_by'],
                reason=body.get('reason')
            )
        
        elif operation == 'get_pending_approvals':
            result = service.get_pending_approvals(
                user_email=body.get('user_email')
            )
        
        elif operation == 'get_user_requests':
            result = service.get_user_requests(
                user_email=body['user_email'],
                status=body.get('status')
            )
        
        elif operation == 'get_request':
            result = service._get_request(body['request_id'])
            if not result:
                return {
                    'statusCode': 404,
                    'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                    'body': json.dumps({'error': 'Request not found'})
                }
        
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': f'Unknown operation: {operation}'})
            }
        
        # Return success response
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(result, default=str)
        }
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
    
    except Exception as e:
        logger.error(f"Error in approval workflow handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error', 'message': str(e)})
        }
