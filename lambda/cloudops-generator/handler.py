#!/usr/bin/env python3
"""
CloudOps Request Generator Lambda

Generates pre-filled CloudOps request templates for production RDS changes.
Loads templates from S3, fills with instance data, and saves to S3.

Requirements: REQ-5.1, REQ-5.2, REQ-5.3, REQ-5.4, REQ-5.5
"""

import json
import os
from datetime import datetime
from typing import Dict, Any, Optional
import boto3

# Import shared utilities
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from shared.logger import get_logger
from shared.aws_clients import AWSClients
from shared.config import Config

logger = None  # Initialized in handler


class CloudOpsRequestGenerator:
    """Generate CloudOps request templates."""
    
    TEMPLATE_TYPES = ['scaling', 'parameter_change', 'maintenance']
    
    def __init__(self):
        """Initialize generator."""
        self.config = Config.load()
        self.dynamodb = AWSClients.get_dynamodb_resource()
        self.s3 = AWSClients.get_s3_client()
        
        self.inventory_table = self.config.dynamodb.inventory_table
        self.compliance_table = 'rds_compliance'  # TODO: Add to config
        self.audit_log_table = self.config.dynamodb.audit_log_table
        self.s3_bucket = self.config.s3.data_bucket
        self.templates_prefix = 's3-templates/'
        self.requests_prefix = 'cloudops-requests/'
    
    def handle_request(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle CloudOps request generation.
        
        Args:
            event: API Gateway event
            
        Returns:
            dict: Generated request
        """
        try:
            body = json.loads(event.get('body', '{}'))
            
            instance_id = body.get('instance_id')
            request_type = body.get('request_type')
            changes = body.get('changes', {})
            
            # Validate request
            validation = self._validate_request(instance_id, request_type, changes)
            if not validation['valid']:
                return self._error_response(400, validation['error'])
            
            # Get instance details
            instance = self._get_instance(instance_id)
            if not instance:
                return self._error_response(404, f'Instance {instance_id} not found')
            
            # Get compliance status
            compliance = self._get_compliance(instance_id)
            
            # Load template
            template = self._load_template(request_type)
            
            # Generate request (Markdown format)
            request_content_md = self._generate_request(
                instance, request_type, changes, compliance, template
            )
            
            # Generate plain text version
            request_content_txt = self._markdown_to_plain_text(request_content_md)
            
            # Save both formats to S3
            request_id = self._save_request(
                instance_id, request_type, request_content_md, request_content_txt
            )
            
            # Log to audit trail with full details
            self._log_audit(instance_id, request_type, request_id, changes, body.get('requested_by'))
            
            logger.info('CloudOps request generated',
                instance_id=instance_id,
                request_type=request_type,
                request_id=request_id,
                requested_by=changes.get('requested_by')
            )
            
            return self._success_response({
                'request_id': request_id,
                'instance_id': instance_id,
                'request_type': request_type,
                'content_markdown': request_content_md,
                'content_plaintext': request_content_txt,
                's3_location_markdown': f's3://{self.s3_bucket}/{self.requests_prefix}{request_id}.md',
                's3_location_plaintext': f's3://{self.s3_bucket}/{self.requests_prefix}{request_id}.txt'
            })
            
        except Exception as e:
            logger.error('Error generating request', error=str(e))
            return self._error_response(500, f'Internal error: {str(e)}')
    
    def _validate_request(
        self,
        instance_id: str,
        request_type: str,
        changes: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Validate request parameters comprehensively.
        
        Requirements: REQ-5.3 - Validate all required fields before submission
        """
        # Basic validation
        if not instance_id:
            return {'valid': False, 'error': 'instance_id is required'}
        
        if not request_type:
            return {'valid': False, 'error': 'request_type is required'}
        
        if request_type not in self.TEMPLATE_TYPES:
            return {
                'valid': False,
                'error': f'Invalid request_type. Must be one of: {", ".join(self.TEMPLATE_TYPES)}'
            }
        
        # Validate common required fields
        if not changes.get('requested_by'):
            return {'valid': False, 'error': 'requested_by (user email) is required'}
        
        if not changes.get('justification'):
            return {'valid': False, 'error': 'justification is required'}
        
        # Validate type-specific required fields
        if request_type == 'scaling':
            validation = self._validate_scaling_request(changes)
            if not validation['valid']:
                return validation
        
        elif request_type == 'parameter_change':
            validation = self._validate_parameter_change_request(changes)
            if not validation['valid']:
                return validation
        
        elif request_type == 'maintenance':
            validation = self._validate_maintenance_request(changes)
            if not validation['valid']:
                return validation
        
        return {'valid': True, 'error': None}
    
    def _validate_scaling_request(self, changes: Dict[str, Any]) -> Dict[str, Any]:
        """Validate scaling request specific fields."""
        required_fields = {
            'target_instance_class': 'Target instance class',
            'preferred_date': 'Preferred maintenance date',
            'preferred_time': 'Preferred maintenance time'
        }
        
        for field, label in required_fields.items():
            if not changes.get(field):
                return {'valid': False, 'error': f'{label} is required for scaling requests'}
        
        return {'valid': True, 'error': None}
    
    def _validate_parameter_change_request(self, changes: Dict[str, Any]) -> Dict[str, Any]:
        """Validate parameter change request specific fields."""
        required_fields = {
            'parameter_changes': 'Parameter changes list',
            'requires_reboot': 'Requires reboot flag',
            'preferred_date': 'Preferred maintenance date',
            'preferred_time': 'Preferred maintenance time'
        }
        
        for field, label in required_fields.items():
            if field not in changes:
                return {'valid': False, 'error': f'{label} is required for parameter change requests'}
        
        # Validate parameter_changes is a list
        if not isinstance(changes.get('parameter_changes'), list):
            return {'valid': False, 'error': 'parameter_changes must be a list of parameter modifications'}
        
        if len(changes.get('parameter_changes', [])) == 0:
            return {'valid': False, 'error': 'At least one parameter change must be specified'}
        
        return {'valid': True, 'error': None}
    
    def _validate_maintenance_request(self, changes: Dict[str, Any]) -> Dict[str, Any]:
        """Validate maintenance request specific fields."""
        required_fields = {
            'new_maintenance_window': 'New maintenance window'
        }
        
        for field, label in required_fields.items():
            if not changes.get(field):
                return {'valid': False, 'error': f'{label} is required for maintenance requests'}
        
        return {'valid': True, 'error': None}
    
    def _get_instance(self, instance_id: str) -> Optional[Dict[str, Any]]:
        """Get instance from inventory."""
        try:
            table = self.dynamodb.Table(self.inventory_table)
            response = table.get_item(Key={'instance_id': instance_id})
            return response.get('Item')
        except Exception as e:
            logger.error('Error getting instance', error=str(e), instance_id=instance_id)
            return None
    
    def _get_compliance(self, instance_id: str) -> Optional[Dict[str, Any]]:
        """Get compliance status."""
        try:
            table = self.dynamodb.Table(self.compliance_table)
            response = table.get_item(Key={'instance_id': instance_id})
            return response.get('Item', {})
        except Exception as e:
            logger.error('Error getting compliance', error=str(e))
            return {}
    
    def _load_template(self, request_type: str) -> str:
        """Load template from S3."""
        try:
            template_key = f'{self.templates_prefix}cloudops_{request_type}_template.md'
            response = self.s3.get_object(Bucket=self.s3_bucket, Key=template_key)
            return response['Body'].read().decode('utf-8')
        except Exception as e:
            logger.error('Error loading template', error=str(e), request_type=request_type)
            return self._get_default_template(request_type)
    
    def _get_default_template(self, request_type: str) -> str:
        """Get default template if S3 load fails."""
        return f"""# CloudOps Request - {request_type.replace('_', ' ').title()}

## Instance Information
- Instance ID: {{instance_id}}
- Account: {{account_name}} ({{account_id}})
- Region: {{region}}
- Engine: {{engine}} {{engine_version}}

## Current Configuration
{{current_config}}

## Proposed Changes
{{proposed_changes}}

## Compliance Status
{{compliance_status}}

## Impact Assessment
{{impact_assessment}}

## Rollback Plan
{{rollback_plan}}

## Approval Required
- CloudOps Team Lead
- Application Owner
"""
    
    def _generate_request(
        self,
        instance: Dict[str, Any],
        request_type: str,
        changes: Dict[str, Any],
        compliance: Dict[str, Any],
        template: str
    ) -> str:
        """
        Generate filled request from template.
        
        Requirements: REQ-5.2, REQ-5.4 - Pre-fill instance details and compliance status
        """
        timestamp = datetime.utcnow()
        request_id = f'{instance.get("instance_id")}-{request_type}-{timestamp.strftime("%Y%m%d-%H%M%S")}'
        
        # Build comprehensive replacement values
        values = {
            # Request metadata
            'REQUEST_ID': request_id,
            'USER_EMAIL': changes.get('requested_by', 'Unknown'),
            'REQUEST_DATE': timestamp.strftime('%Y-%m-%d %H:%M:%S UTC'),
            'PRIORITY': changes.get('priority', 'Normal'),
            
            # Instance details
            'INSTANCE_ID': instance.get('instance_id', ''),
            'ACCOUNT_NAME': instance.get('account_name', ''),
            'ACCOUNT_ID': instance.get('account_id', ''),
            'REGION': instance.get('region', ''),
            'ENGINE': instance.get('engine', '').upper(),
            'ENGINE_VERSION': instance.get('engine_version', ''),
            'INSTANCE_CLASS': instance.get('instance_class', ''),
            'CURRENT_INSTANCE_CLASS': instance.get('instance_class', ''),
            'STORAGE_TYPE': instance.get('storage_type', ''),
            'ALLOCATED_STORAGE': str(instance.get('allocated_storage', '')),
            'MULTI_AZ': 'Yes' if instance.get('multi_az') else 'No',
            'ENCRYPTION_ENABLED': 'Yes' if instance.get('storage_encrypted') else 'No',
            'BACKUP_RETENTION_DAYS': str(instance.get('backup_retention_period', '')),
            'DELETION_PROTECTION': 'Yes' if instance.get('deletion_protection') else 'No',
            
            # Maintenance windows
            'CURRENT_MAINTENANCE_WINDOW': instance.get('preferred_maintenance_window', 'Not set'),
            'CURRENT_BACKUP_WINDOW': instance.get('preferred_backup_window', 'Not set'),
            
            # Common change fields
            'JUSTIFICATION': changes.get('justification', ''),
            'PREFERRED_DATE': changes.get('preferred_date', 'TBD'),
            'PREFERRED_TIME': changes.get('preferred_time', 'TBD'),
            'TIMEZONE': changes.get('timezone', 'UTC'),
            'ADDITIONAL_NOTES': changes.get('additional_notes', 'None'),
            
            # Compliance status
            'BACKUP_STATUS': '✓' if compliance.get('backup_compliant') else '✗',
            'ENCRYPTION_STATUS': '✓' if compliance.get('encryption_compliant') else '✗',
            'PATCH_STATUS': '✓' if compliance.get('version_compliant') else '✗',
            'MULTI_AZ_STATUS': '✓' if instance.get('multi_az') else '✗',
            'DELETION_PROTECTION_STATUS': '✓' if instance.get('deletion_protection') else '✗',
            'LATEST_VERSION': compliance.get('latest_version', 'Unknown'),
            
            # Type-specific values
            **self._get_type_specific_values(request_type, instance, changes, compliance)
        }
        
        # Replace placeholders (case-insensitive)
        content = template
        for key, value in values.items():
            # Replace both {{KEY}} and {{key}} formats
            content = content.replace(f'{{{{{key}}}}}', str(value))
            content = content.replace(f'{{{{{key.lower()}}}}}', str(value))
        
        return content
    
    def _get_type_specific_values(
        self,
        request_type: str,
        instance: Dict[str, Any],
        changes: Dict[str, Any],
        compliance: Dict[str, Any]
    ) -> Dict[str, str]:
        """Get type-specific template values."""
        if request_type == 'scaling':
            return self._get_scaling_values(instance, changes)
        elif request_type == 'parameter_change':
            return self._get_parameter_change_values(instance, changes)
        elif request_type == 'maintenance':
            return self._get_maintenance_values(instance, changes, compliance)
        return {}
    
    def _get_scaling_values(self, instance: Dict[str, Any], changes: Dict[str, Any]) -> Dict[str, str]:
        """Get scaling-specific template values."""
        return {
            'TARGET_INSTANCE_CLASS': changes.get('target_instance_class', ''),
            'AVG_CPU': changes.get('avg_cpu', 'N/A'),
            'PEAK_CPU': changes.get('peak_cpu', 'N/A'),
            'AVG_CONNECTIONS': changes.get('avg_connections', 'N/A'),
            'PEAK_CONNECTIONS': changes.get('peak_connections', 'N/A'),
            'AVG_FREE_MEMORY': changes.get('avg_free_memory', 'N/A'),
            'ESTIMATED_DOWNTIME': changes.get('estimated_downtime', '2-5'),
            'CURRENT_COST': changes.get('current_cost', 'TBD'),
            'NEW_COST': changes.get('new_cost', 'TBD'),
            'COST_DELTA': changes.get('cost_delta', 'TBD'),
            'RISK_LEVEL': changes.get('risk_level', 'Medium'),
            'ROLLBACK_PLAN': self._format_rollback('scaling', instance, changes)
        }
    
    def _get_parameter_change_values(self, instance: Dict[str, Any], changes: Dict[str, Any]) -> Dict[str, str]:
        """Get parameter change-specific template values."""
        parameter_changes = changes.get('parameter_changes', [])
        
        # Format parameter changes as table
        table = "| Parameter | Current Value | New Value |\n"
        table += "|-----------|---------------|------------|\n"
        for param in parameter_changes:
            table += f"| {param.get('name', '')} | {param.get('current', '')} | {param.get('new', '')} |\n"
        
        requires_reboot = changes.get('requires_reboot', True)
        
        return {
            'CURRENT_PARAMETER_GROUP': instance.get('parameter_group', 'default'),
            'PARAMETER_CHANGES_TABLE': table,
            'REQUIRES_REBOOT': 'Yes' if requires_reboot else 'No',
            'ESTIMATED_DOWNTIME': '2-3' if requires_reboot else '0',
            'RISK_LEVEL': changes.get('risk_level', 'Medium' if requires_reboot else 'Low'),
            'PERFORMANCE_IMPACT': changes.get('performance_impact', 'TBD'),
            'ROLLBACK_TIME': '2-3' if requires_reboot else '1',
            'TESTING_PLAN': changes.get('testing_plan', 'TBD'),
            'AUTO_MINOR_VERSION_UPGRADE': 'Yes' if instance.get('auto_minor_version_upgrade') else 'No'
        }
    
    def _get_maintenance_values(
        self,
        instance: Dict[str, Any],
        changes: Dict[str, Any],
        compliance: Dict[str, Any]
    ) -> Dict[str, str]:
        """Get maintenance-specific template values."""
        pending_actions = compliance.get('pending_maintenance_actions', [])
        
        if pending_actions:
            actions_list = '\n'.join([f'- {action}' for action in pending_actions])
        else:
            actions_list = 'None'
        
        return {
            'NEW_MAINTENANCE_WINDOW': changes.get('new_maintenance_window', ''),
            'NEW_BACKUP_WINDOW': changes.get('new_backup_window', 'No change'),
            'AUTO_MINOR_VERSION_UPGRADE': 'Yes' if instance.get('auto_minor_version_upgrade') else 'No',
            'PENDING_MAINTENANCE_ACTIONS': 'Yes' if pending_actions else 'No',
            'PENDING_ACTIONS_LIST': actions_list
        }
    
    def _format_current_config(self, instance: Dict[str, Any]) -> str:
        """Format current configuration."""
        return f"""- Instance Class: {instance.get('instance_class', 'N/A')}
- vCPUs: {instance.get('vcpus', 'N/A')} | Memory: {instance.get('memory_gb', 'N/A')} GB
- Storage: {instance.get('allocated_storage', 'N/A')} GB ({instance.get('storage_type', 'N/A')})
- IOPS: {instance.get('iops', 'N/A')}
- Multi-AZ: {'Yes' if instance.get('multi_az') else 'No'}
- Encryption: {'Yes' if instance.get('encryption_enabled') else 'No'}
- Backup Retention: {instance.get('backup_retention_days', 'N/A')} days"""
    
    def _format_proposed_changes(self, request_type: str, changes: Dict[str, Any]) -> str:
        """Format proposed changes."""
        if request_type == 'scaling':
            return f"""- New Instance Class: {changes.get('new_instance_class', 'N/A')}
- Apply Immediately: {changes.get('apply_immediately', 'No')}
- Reason: {changes.get('reason', 'N/A')}"""
        
        elif request_type == 'parameter_change':
            return f"""- New Parameter Group: {changes.get('parameter_group', 'N/A')}
- Apply Immediately: {changes.get('apply_immediately', 'No')}
- Requires Reboot: {changes.get('requires_reboot', 'Unknown')}
- Reason: {changes.get('reason', 'N/A')}"""
        
        elif request_type == 'maintenance':
            return f"""- Maintenance Action: {changes.get('maintenance_action', 'N/A')}
- Scheduled Time: {changes.get('scheduled_time', 'N/A')}
- Reason: {changes.get('reason', 'N/A')}"""
        
        return 'N/A'
    
    def _format_compliance(self, compliance: Dict[str, Any]) -> str:
        """Format compliance status."""
        if not compliance:
            return 'Compliance status not available'
        
        compliant = compliance.get('compliant', False)
        violations = compliance.get('violations', [])
        
        status = '✓ Compliant' if compliant else f'✗ {len(violations)} violation(s)'
        
        if violations:
            status += '\n' + '\n'.join([f'  - {v}' for v in violations[:5]])
        
        return status
    
    def _format_impact(self, request_type: str, changes: Dict[str, Any]) -> str:
        """Format impact assessment."""
        if request_type == 'scaling':
            return f"""- Requires instance reboot: Yes
- Estimated downtime: 2-5 minutes
- Application impact: Brief connection interruption
- Data loss risk: None"""
        
        elif request_type == 'parameter_change':
            reboot = changes.get('requires_reboot', True)
            return f"""- Requires instance reboot: {'Yes' if reboot else 'No'}
- Estimated downtime: {'2-3 minutes' if reboot else 'None'}
- Application impact: {'Brief connection interruption' if reboot else 'None'}
- Data loss risk: None"""
        
        elif request_type == 'maintenance':
            return f"""- Estimated downtime: {changes.get('estimated_downtime', 'TBD')}
- Application impact: {changes.get('application_impact', 'TBD')}
- Data loss risk: None"""
        
        return 'TBD'
    
    def _format_rollback(
        self,
        request_type: str,
        instance: Dict[str, Any],
        changes: Dict[str, Any]
    ) -> str:
        """Format rollback plan."""
        if request_type == 'scaling':
            return f"""1. Revert to previous instance class: {instance.get('instance_class', 'N/A')}
2. Reboot instance to apply previous configuration
3. Estimated rollback time: 2-5 minutes"""
        
        elif request_type == 'parameter_change':
            return f"""1. Revert to previous parameter group
2. Reboot instance if required
3. Estimated rollback time: 2-3 minutes"""
        
        elif request_type == 'maintenance':
            return f"""1. {changes.get('rollback_steps', 'Rollback steps TBD')}
2. Estimated rollback time: {changes.get('rollback_time', 'TBD')}"""
        
        return 'Rollback plan TBD'
    
    def _markdown_to_plain_text(self, markdown: str) -> str:
        """
        Convert markdown to plain text format.
        
        Requirements: REQ-5.5 - Generate formatted output suitable for ticketing systems
        """
        # Simple markdown to plain text conversion
        text = markdown
        
        # Remove markdown headers (# ## ###)
        import re
        text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
        
        # Remove bold/italic markers
        text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
        text = re.sub(r'\*([^*]+)\*', r'\1', text)
        
        # Convert markdown tables to plain text
        lines = text.split('\n')
        plain_lines = []
        in_table = False
        
        for line in lines:
            if '|' in line and not line.strip().startswith('|---'):
                # Table row
                if not in_table:
                    in_table = True
                # Convert table row to plain text
                cells = [cell.strip() for cell in line.split('|') if cell.strip()]
                plain_lines.append('  '.join(cells))
            elif line.strip().startswith('|---'):
                # Table separator - skip
                continue
            else:
                in_table = False
                plain_lines.append(line)
        
        return '\n'.join(plain_lines)
    
    def _save_request(
        self,
        instance_id: str,
        request_type: str,
        content_md: str,
        content_txt: str
    ) -> str:
        """
        Save request to S3 in both Markdown and plain text formats.
        
        Requirements: REQ-5.5 - Save generated request for reference
        """
        try:
            timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
            request_id = f'{instance_id}-{request_type}-{timestamp}'
            
            # Save Markdown version
            key_md = f'{self.requests_prefix}{request_id}.md'
            self.s3.put_object(
                Bucket=self.s3_bucket,
                Key=key_md,
                Body=content_md.encode('utf-8'),
                ContentType='text/markdown',
                Metadata={
                    'request-id': request_id,
                    'instance-id': instance_id,
                    'request-type': request_type,
                    'format': 'markdown'
                }
            )
            
            # Save plain text version
            key_txt = f'{self.requests_prefix}{request_id}.txt'
            self.s3.put_object(
                Bucket=self.s3_bucket,
                Key=key_txt,
                Body=content_txt.encode('utf-8'),
                ContentType='text/plain',
                Metadata={
                    'request-id': request_id,
                    'instance-id': instance_id,
                    'request-type': request_type,
                    'format': 'plaintext'
                }
            )
            
            logger.info('Request saved to S3',
                request_id=request_id,
                markdown_key=key_md,
                plaintext_key=key_txt
            )
            return request_id
            
        except Exception as e:
            logger.error('Error saving request', error=str(e))
            raise
    
    def _log_audit(
        self,
        instance_id: str,
        request_type: str,
        request_id: str,
        changes: Dict[str, Any],
        requested_by: str
    ):
        """
        Log request generation to audit trail.
        
        Requirements: REQ-5.5, REQ-7.5 - Log all operations with details
        """
        try:
            table = self.dynamodb.Table(self.audit_log_table)
            
            timestamp = datetime.utcnow().isoformat()
            
            item = {
                'audit_id': f'{instance_id}#{timestamp}',
                'timestamp': timestamp,
                'operation': 'cloudops_request_generated',
                'instance_id': instance_id,
                'request_type': request_type,
                'request_id': request_id,
                'requested_by': requested_by,
                'justification': changes.get('justification', ''),
                'priority': changes.get('priority', 'Normal'),
                'success': True,
                'metadata': {
                    'preferred_date': changes.get('preferred_date'),
                    'preferred_time': changes.get('preferred_time'),
                    'has_additional_notes': bool(changes.get('additional_notes'))
                }
            }
            
            table.put_item(Item=item)
            
            logger.info('Audit log created',
                audit_id=item['audit_id'],
                operation='cloudops_request_generated'
            )
            
        except Exception as e:
            logger.error('Error logging audit', error=str(e))
    
    def _success_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create success response."""
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(data)
        }
    
    def _error_response(self, status_code: int, message: str) -> Dict[str, Any]:
        """Create error response."""
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': message})
        }


def lambda_handler(event, context):
    """
    Lambda handler for CloudOps request generation.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        dict: API Gateway response
    """
    global logger
    logger = get_logger('cloudops-generator', lambda_context=context)
    
    logger.info('CloudOps request generation started')
    
    generator = CloudOpsRequestGenerator()
    return generator.handle_request(event)
