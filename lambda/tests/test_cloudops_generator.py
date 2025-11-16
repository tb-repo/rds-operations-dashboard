#!/usr/bin/env python3
"""
Tests for CloudOps Request Generator Lambda

Tests validation, request generation, and storage functionality.
Requirements: REQ-5.3, REQ-5.4, REQ-5.5
"""

import json
import pytest
from datetime import datetime
from unittest.mock import Mock, patch, MagicMock
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Import with proper path handling
try:
    from cloudops_generator.handler import CloudOpsRequestGenerator, lambda_handler
except ImportError:
    # Try alternative import for different test environments
    import importlib.util
    handler_path = os.path.join(os.path.dirname(__file__), '..', 'cloudops-generator', 'handler.py')
    spec = importlib.util.spec_from_file_location("handler", handler_path)
    handler_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(handler_module)
    CloudOpsRequestGenerator = handler_module.CloudOpsRequestGenerator
    lambda_handler = handler_module.lambda_handler


@pytest.fixture
def mock_config():
    """Mock configuration."""
    from types import SimpleNamespace
    return SimpleNamespace(
        dynamodb=SimpleNamespace(
            inventory_table='test_rds_inventory',
            audit_log_table='test_rds_audit_log'
        ),
        s3=SimpleNamespace(
            data_bucket='test-rds-ops-dashboard'
        )
    )


@pytest.fixture
def mock_instance():
    """Mock RDS instance data."""
    return {
        'instance_id': 'test-postgres-01',
        'account_id': '123456789012',
        'account_name': 'Test Account',
        'region': 'ap-southeast-1',
        'engine': 'postgres',
        'engine_version': '15.4',
        'instance_class': 'db.r6g.large',
        'storage_type': 'gp3',
        'allocated_storage': 100,
        'multi_az': True,
        'storage_encrypted': True,
        'backup_retention_period': 7,
        'deletion_protection': True,
        'preferred_maintenance_window': 'sun:04:00-sun:05:00',
        'preferred_backup_window': '03:00-04:00'
    }


@pytest.fixture
def mock_compliance():
    """Mock compliance data."""
    return {
        'instance_id': 'test-postgres-01',
        'backup_compliant': True,
        'encryption_compliant': True,
        'version_compliant': True,
        'latest_version': '15.5',
        'pending_maintenance_actions': []
    }


@pytest.fixture
def generator(mock_config):
    """Create generator instance with mocked dependencies."""
    with patch('cloudops_generator.handler.Config.load', return_value=mock_config), \
         patch('cloudops_generator.handler.AWSClients.get_dynamodb_resource'), \
         patch('cloudops_generator.handler.AWSClients.get_s3_client'), \
         patch('cloudops_generator.handler.get_logger'):
        
        gen = CloudOpsRequestGenerator()
        gen.dynamodb = MagicMock()
        gen.s3 = MagicMock()
        return gen


class TestRequestValidation:
    """Test request validation logic."""
    
    def test_validate_missing_instance_id(self, generator):
        """Test validation fails when instance_id is missing."""
        result = generator._validate_request(None, 'scaling', {})
        assert not result['valid']
        assert 'instance_id' in result['error']
    
    def test_validate_missing_request_type(self, generator):
        """Test validation fails when request_type is missing."""
        result = generator._validate_request('test-instance', None, {})
        assert not result['valid']
        assert 'request_type' in result['error']
    
    def test_validate_invalid_request_type(self, generator):
        """Test validation fails for invalid request type."""
        result = generator._validate_request('test-instance', 'invalid_type', {})
        assert not result['valid']
        assert 'Invalid request_type' in result['error']
    
    def test_validate_missing_requested_by(self, generator):
        """Test validation fails when requested_by is missing."""
        result = generator._validate_request('test-instance', 'scaling', {})
        assert not result['valid']
        assert 'requested_by' in result['error']
    
    def test_validate_missing_justification(self, generator):
        """Test validation fails when justification is missing."""
        changes = {'requested_by': 'test@example.com'}
        result = generator._validate_request('test-instance', 'scaling', changes)
        assert not result['valid']
        assert 'justification' in result['error']
    
    def test_validate_scaling_missing_target_class(self, generator):
        """Test scaling validation fails without target instance class."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Need more capacity'
        }
        result = generator._validate_request('test-instance', 'scaling', changes)
        assert not result['valid']
        assert 'Target instance class' in result['error']
    
    def test_validate_scaling_success(self, generator):
        """Test successful scaling request validation."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Need more capacity',
            'target_instance_class': 'db.r6g.xlarge',
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00'
        }
        result = generator._validate_request('test-instance', 'scaling', changes)
        assert result['valid']
        assert result['error'] is None
    
    def test_validate_parameter_change_missing_changes(self, generator):
        """Test parameter change validation fails without parameter changes."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Update settings'
        }
        result = generator._validate_request('test-instance', 'parameter_change', changes)
        assert not result['valid']
        assert 'Parameter changes' in result['error']
    
    def test_validate_parameter_change_empty_list(self, generator):
        """Test parameter change validation fails with empty changes list."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Update settings',
            'parameter_changes': [],
            'requires_reboot': True,
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00'
        }
        result = generator._validate_request('test-instance', 'parameter_change', changes)
        assert not result['valid']
        assert 'At least one parameter change' in result['error']
    
    def test_validate_parameter_change_success(self, generator):
        """Test successful parameter change request validation."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Update settings',
            'parameter_changes': [
                {'name': 'max_connections', 'current': '100', 'new': '200'}
            ],
            'requires_reboot': True,
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00'
        }
        result = generator._validate_request('test-instance', 'parameter_change', changes)
        assert result['valid']
    
    def test_validate_maintenance_missing_window(self, generator):
        """Test maintenance validation fails without new maintenance window."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Change maintenance window'
        }
        result = generator._validate_request('test-instance', 'maintenance', changes)
        assert not result['valid']
        assert 'New maintenance window' in result['error']
    
    def test_validate_maintenance_success(self, generator):
        """Test successful maintenance request validation."""
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Change maintenance window',
            'new_maintenance_window': 'mon:02:00-mon:03:00'
        }
        result = generator._validate_request('test-instance', 'maintenance', changes)
        assert result['valid']


class TestRequestGeneration:
    """Test request generation logic."""
    
    def test_generate_scaling_request(self, generator, mock_instance, mock_compliance):
        """Test scaling request generation with all fields."""
        template = """# CloudOps Request: Scale RDS Instance
**Request ID:** {{REQUEST_ID}}
**Instance ID:** {{INSTANCE_ID}}
**Target Class:** {{TARGET_INSTANCE_CLASS}}
**Justification:** {{JUSTIFICATION}}"""
        
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Need more capacity',
            'target_instance_class': 'db.r6g.xlarge',
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00',
            'avg_cpu': '85',
            'peak_cpu': '95'
        }
        
        result = generator._generate_request(
            mock_instance, 'scaling', changes, mock_compliance, template
        )
        
        assert 'test-postgres-01' in result
        assert 'db.r6g.xlarge' in result
        assert 'Need more capacity' in result
        assert '{{' not in result  # No unfilled placeholders
    
    def test_generate_parameter_change_request(self, generator, mock_instance, mock_compliance):
        """Test parameter change request generation."""
        template = """# CloudOps Request: Parameter Change
**Instance ID:** {{INSTANCE_ID}}
**Parameter Changes:**
{{PARAMETER_CHANGES_TABLE}}
**Requires Reboot:** {{REQUIRES_REBOOT}}"""
        
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Update settings',
            'parameter_changes': [
                {'name': 'max_connections', 'current': '100', 'new': '200'},
                {'name': 'shared_buffers', 'current': '256MB', 'new': '512MB'}
            ],
            'requires_reboot': True,
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00'
        }
        
        result = generator._generate_request(
            mock_instance, 'parameter_change', changes, mock_compliance, template
        )
        
        assert 'test-postgres-01' in result
        assert 'max_connections' in result
        assert 'shared_buffers' in result
        assert 'Yes' in result  # Requires reboot
    
    def test_generate_maintenance_request(self, generator, mock_instance, mock_compliance):
        """Test maintenance request generation."""
        template = """# CloudOps Request: Maintenance Window
**Instance ID:** {{INSTANCE_ID}}
**Current Window:** {{CURRENT_MAINTENANCE_WINDOW}}
**New Window:** {{NEW_MAINTENANCE_WINDOW}}"""
        
        changes = {
            'requested_by': 'test@example.com',
            'justification': 'Change maintenance window',
            'new_maintenance_window': 'mon:02:00-mon:03:00'
        }
        
        result = generator._generate_request(
            mock_instance, 'maintenance', changes, mock_compliance, template
        )
        
        assert 'test-postgres-01' in result
        assert 'sun:04:00-sun:05:00' in result  # Current window
        assert 'mon:02:00-mon:03:00' in result  # New window


class TestMarkdownConversion:
    """Test markdown to plain text conversion."""
    
    def test_convert_headers(self, generator):
        """Test header conversion."""
        markdown = "# Header 1\n## Header 2\n### Header 3"
        result = generator._markdown_to_plain_text(markdown)
        assert '#' not in result
        assert 'Header 1' in result
        assert 'Header 2' in result
    
    def test_convert_bold_text(self, generator):
        """Test bold text conversion."""
        markdown = "This is **bold** text"
        result = generator._markdown_to_plain_text(markdown)
        assert '**' not in result
        assert 'bold' in result
    
    def test_convert_table(self, generator):
        """Test table conversion."""
        markdown = """| Column 1 | Column 2 |
|----------|----------|
| Value 1  | Value 2  |"""
        result = generator._markdown_to_plain_text(markdown)
        assert '|' not in result or result.count('|') < markdown.count('|')
        assert 'Column 1' in result
        assert 'Value 1' in result


class TestStorageAndAudit:
    """Test S3 storage and audit logging."""
    
    def test_save_request_both_formats(self, generator):
        """Test request is saved in both Markdown and plain text formats."""
        content_md = "# Test Request\n**Field:** Value"
        content_txt = "Test Request\nField: Value"
        
        generator.s3.put_object = Mock()
        
        request_id = generator._save_request(
            'test-instance', 'scaling', content_md, content_txt
        )
        
        assert request_id.startswith('test-instance-scaling-')
        assert generator.s3.put_object.call_count == 2
        
        # Check Markdown save
        md_call = generator.s3.put_object.call_args_list[0]
        assert md_call[1]['Key'].endswith('.md')
        assert md_call[1]['ContentType'] == 'text/markdown'
        
        # Check plain text save
        txt_call = generator.s3.put_object.call_args_list[1]
        assert txt_call[1]['Key'].endswith('.txt')
        assert txt_call[1]['ContentType'] == 'text/plain'
    
    def test_audit_logging(self, generator):
        """Test audit trail logging with full details."""
        mock_table = Mock()
        generator.dynamodb.Table = Mock(return_value=mock_table)
        
        changes = {
            'justification': 'Test justification',
            'priority': 'High',
            'preferred_date': '2025-11-20',
            'preferred_time': '02:00'
        }
        
        generator._log_audit(
            'test-instance',
            'scaling',
            'test-request-id',
            changes,
            'test@example.com'
        )
        
        mock_table.put_item.assert_called_once()
        item = mock_table.put_item.call_args[1]['Item']
        
        assert item['instance_id'] == 'test-instance'
        assert item['request_type'] == 'scaling'
        assert item['request_id'] == 'test-request-id'
        assert item['requested_by'] == 'test@example.com'
        assert item['justification'] == 'Test justification'
        assert item['priority'] == 'High'
        assert item['success'] is True


class TestEndToEnd:
    """Test end-to-end request handling."""
    
    @patch('cloudops_generator.handler.get_logger')
    @patch('cloudops_generator.handler.Config.load')
    @patch('cloudops_generator.handler.AWSClients.get_dynamodb_resource')
    @patch('cloudops_generator.handler.AWSClients.get_s3_client')
    def test_successful_scaling_request(
        self, mock_s3, mock_dynamo, mock_config, mock_logger,
        mock_instance, mock_compliance
    ):
        """Test complete scaling request flow."""
        # Setup mocks
        from types import SimpleNamespace
        mock_config.return_value = SimpleNamespace(
            dynamodb=SimpleNamespace(
                inventory_table='test_inventory',
                audit_log_table='test_audit'
            ),
            s3=SimpleNamespace(
                data_bucket='test-bucket'
            )
        )
        
        mock_dynamo_client = MagicMock()
        mock_dynamo.return_value = mock_dynamo_client
        
        # Mock DynamoDB responses
        mock_inventory_table = Mock()
        mock_inventory_table.get_item.return_value = {'Item': mock_instance}
        
        mock_compliance_table = Mock()
        mock_compliance_table.get_item.return_value = {'Item': mock_compliance}
        
        mock_audit_table = Mock()
        
        def table_selector(table_name):
            if 'inventory' in table_name:
                return mock_inventory_table
            elif 'compliance' in table_name:
                return mock_compliance_table
            else:
                return mock_audit_table
        
        mock_dynamo_client.Table.side_effect = table_selector
        
        # Mock S3
        mock_s3_client = MagicMock()
        mock_s3_client.get_object.return_value = {
            'Body': Mock(read=lambda: b'# Template\n{{INSTANCE_ID}}')
        }
        mock_s3.return_value = mock_s3_client
        
        # Create event
        event = {
            'body': json.dumps({
                'instance_id': 'test-postgres-01',
                'request_type': 'scaling',
                'changes': {
                    'requested_by': 'test@example.com',
                    'justification': 'Need more capacity',
                    'target_instance_class': 'db.r6g.xlarge',
                    'preferred_date': '2025-11-20',
                    'preferred_time': '02:00'
                }
            })
        }
        
        # Execute
        response = lambda_handler(event, Mock())
        
        # Verify
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'request_id' in body
        assert 'content_markdown' in body
        assert 'content_plaintext' in body
        assert body['instance_id'] == 'test-postgres-01'
        assert body['request_type'] == 'scaling'


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
