#!/usr/bin/env python3
"""
Test Operations Service

Tests for self-service RDS operations including snapshot creation,
instance reboot, and backup window modification.
"""

import unittest
import sys
import os
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

# Add parent directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from operations.handler import OperationsHandler


class TestOperationsHandler(unittest.TestCase):
    """Test operations handler functionality."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.handler = OperationsHandler()
        self.handler.config = {
            'audit_log_table': 'test_audit_log',
            'inventory_table': 'test_inventory',
            'environment_classification': {
                'default_environment': 'non-production'
            }
        }
    
    def test_validate_request_success(self):
        """Test successful request validation."""
        result = self.handler._validate_request(
            operation='create_snapshot',
            instance_id='test-db-01',
            parameters={'snapshot_id': 'test-snapshot-01'},
            user_identity={'userId': 'test-user'}
        )
        
        self.assertTrue(result['valid'])
        self.assertIsNone(result['error'])
    
    def test_validate_request_missing_operation(self):
        """Test validation with missing operation."""
        result = self.handler._validate_request(
            operation=None,
            instance_id='test-db-01',
            parameters={},
            user_identity={}
        )
        
        self.assertFalse(result['valid'])
        self.assertIn('Operation type is required', result['error'])
    
    def test_validate_request_invalid_operation(self):
        """Test validation with invalid operation."""
        result = self.handler._validate_request(
            operation='delete_instance',
            instance_id='test-db-01',
            parameters={},
            user_identity={}
        )
        
        self.assertFalse(result['valid'])
        self.assertIn('not allowed', result['error'])
    
    def test_validate_request_missing_instance_id(self):
        """Test validation with missing instance ID."""
        result = self.handler._validate_request(
            operation='create_snapshot',
            instance_id=None,
            parameters={'snapshot_id': 'test-snapshot'},
            user_identity={}
        )
        
        self.assertFalse(result['valid'])
        self.assertIn('Instance ID is required', result['error'])
    
    def test_validate_request_missing_snapshot_id(self):
        """Test validation for create_snapshot without snapshot_id."""
        result = self.handler._validate_request(
            operation='create_snapshot',
            instance_id='test-db-01',
            parameters={},
            user_identity={}
        )
        
        self.assertFalse(result['valid'])
        self.assertIn('snapshot_id is required', result['error'])
    
    def test_validate_request_missing_backup_window(self):
        """Test validation for modify_backup_window without backup_window."""
        result = self.handler._validate_request(
            operation='modify_backup_window',
            instance_id='test-db-01',
            parameters={},
            user_identity={}
        )
        
        self.assertFalse(result['valid'])
        self.assertIn('backup_window is required', result['error'])
    
    def test_validate_backup_window_format_valid(self):
        """Test valid backup window format."""
        self.assertTrue(self.handler._validate_backup_window_format('03:00-04:00'))
        self.assertTrue(self.handler._validate_backup_window_format('23:30-00:30'))
        self.assertTrue(self.handler._validate_backup_window_format('00:00-01:00'))
    
    def test_validate_backup_window_format_invalid(self):
        """Test invalid backup window formats."""
        self.assertFalse(self.handler._validate_backup_window_format('3:00-4:00'))
        self.assertFalse(self.handler._validate_backup_window_format('03:00'))
        self.assertFalse(self.handler._validate_backup_window_format('25:00-26:00'))
        self.assertFalse(self.handler._validate_backup_window_format('03:60-04:00'))
        self.assertFalse(self.handler._validate_backup_window_format('invalid'))
    
    @patch('operations.handler.get_dynamodb_client')
    def test_get_instance_success(self, mock_dynamodb):
        """Test successful instance retrieval."""
        mock_table = Mock()
        mock_table.get_item.return_value = {
            'Item': {
                'instance_id': 'test-db-01',
                'account_id': '123456789012',
                'region': 'ap-southeast-1',
                'tags': {'Environment': 'Development'}
            }
        }
        mock_dynamodb.return_value.Table.return_value = mock_table
        
        instance = self.handler._get_instance('test-db-01')
        
        self.assertIsNotNone(instance)
        self.assertEqual(instance['instance_id'], 'test-db-01')
    
    @patch('operations.handler.get_dynamodb_client')
    def test_get_instance_not_found(self, mock_dynamodb):
        """Test instance not found."""
        mock_table = Mock()
        mock_table.get_item.return_value = {}
        mock_dynamodb.return_value.Table.return_value = mock_table
        
        instance = self.handler._get_instance('nonexistent-db')
        
        self.assertIsNone(instance)
    
    @patch('operations.handler.get_rds_client')
    def test_create_snapshot_success(self, mock_rds_client):
        """Test successful snapshot creation."""
        mock_client = Mock()
        mock_client.create_db_snapshot.return_value = {
            'DBSnapshot': {
                'DBSnapshotIdentifier': 'test-snapshot-01',
                'DBSnapshotArn': 'arn:aws:rds:region:account:snapshot:test-snapshot-01',
                'SnapshotCreateTime': datetime(2025, 11, 13, 10, 0, 0),
                'Status': 'creating'
            }
        }
        mock_client.describe_db_snapshots.return_value = {
            'DBSnapshots': [{
                'DBSnapshotIdentifier': 'test-snapshot-01',
                'Status': 'available'
            }]
        }
        mock_rds_client.return_value = mock_client
        
        result = self.handler._create_snapshot(
            mock_client,
            'test-db-01',
            {'snapshot_id': 'test-snapshot-01', 'tags': []}
        )
        
        self.assertEqual(result['operation'], 'create_snapshot')
        self.assertEqual(result['snapshot_id'], 'test-snapshot-01')
        self.assertEqual(result['status'], 'available')
    
    @patch('operations.handler.get_rds_client')
    def test_reboot_instance_success(self, mock_rds_client):
        """Test successful instance reboot."""
        mock_client = Mock()
        mock_client.reboot_db_instance.return_value = {
            'DBInstance': {
                'DBInstanceIdentifier': 'test-db-01',
                'DBInstanceStatus': 'rebooting'
            }
        }
        mock_client.describe_db_instances.return_value = {
            'DBInstances': [{
                'DBInstanceIdentifier': 'test-db-01',
                'DBInstanceStatus': 'available'
            }]
        }
        mock_rds_client.return_value = mock_client
        
        result = self.handler._reboot_instance(
            mock_client,
            'test-db-01',
            {'force_failover': False}
        )
        
        self.assertEqual(result['operation'], 'reboot_instance')
        self.assertEqual(result['instance_id'], 'test-db-01')
        self.assertEqual(result['status'], 'available')
        self.assertFalse(result['force_failover'])
    
    @patch('operations.handler.get_rds_client')
    def test_modify_backup_window_success(self, mock_rds_client):
        """Test successful backup window modification."""
        mock_client = Mock()
        mock_client.modify_db_instance.return_value = {
            'DBInstance': {
                'DBInstanceIdentifier': 'test-db-01',
                'DBInstanceStatus': 'available',
                'PreferredBackupWindow': '03:00-04:00',
                'PendingModifiedValues': {}
            }
        }
        mock_rds_client.return_value = mock_client
        
        result = self.handler._modify_backup_window(
            mock_client,
            'test-db-01',
            {'backup_window': '03:00-04:00', 'apply_immediately': True}
        )
        
        self.assertEqual(result['operation'], 'modify_backup_window')
        self.assertEqual(result['instance_id'], 'test-db-01')
        self.assertEqual(result['backup_window'], '03:00-04:00')
        self.assertTrue(result['apply_immediately'])
    
    @patch('operations.handler.get_dynamodb_client')
    def test_log_audit_success(self, mock_dynamodb):
        """Test successful audit logging."""
        mock_table = Mock()
        mock_dynamodb.return_value.Table.return_value = mock_table
        
        self.handler._log_audit(
            operation='create_snapshot',
            instance_id='test-db-01',
            parameters={'snapshot_id': 'test-snapshot-01'},
            user_identity={'userId': 'test-user'},
            result={'success': True, 'duration_seconds': 120.5}
        )
        
        mock_table.put_item.assert_called_once()
        call_args = mock_table.put_item.call_args
        item = call_args[1]['Item']
        
        self.assertEqual(item['operation'], 'create_snapshot')
        self.assertEqual(item['instance_id'], 'test-db-01')
        self.assertTrue(item['success'])
    
    def test_success_response(self):
        """Test success response format."""
        response = self.handler._success_response({'result': 'success'})
        
        self.assertEqual(response['statusCode'], 200)
        self.assertIn('Content-Type', response['headers'])
        self.assertIn('result', response['body'])
    
    def test_error_response(self):
        """Test error response format."""
        response = self.handler._error_response(400, 'Bad request')
        
        self.assertEqual(response['statusCode'], 400)
        self.assertIn('Content-Type', response['headers'])
        self.assertIn('error', response['body'])
    
    @patch('operations.handler.get_dynamodb_client')
    @patch('operations.handler.get_rds_client')
    def test_handle_request_production_blocked(self, mock_rds, mock_dynamodb):
        """Test that operations are blocked on production instances."""
        # Mock instance retrieval
        mock_table = Mock()
        mock_table.get_item.return_value = {
            'Item': {
                'instance_id': 'prod-db-01',
                'account_id': '123456789012',
                'region': 'ap-southeast-1',
                'tags': {'Environment': 'Production'}
            }
        }
        mock_dynamodb.return_value.Table.return_value = mock_table
        
        event = {
            'body': '{"operation": "reboot_instance", "instance_id": "prod-db-01", "parameters": {}}',
            'requestContext': {'identity': {'userId': 'test-user'}}
        }
        
        response = self.handler.handle_request(event)
        
        self.assertEqual(response['statusCode'], 403)
        self.assertIn('not allowed on production', response['body'])
    
    @patch('operations.handler.get_dynamodb_client')
    def test_handle_request_instance_not_found(self, mock_dynamodb):
        """Test handling of non-existent instance."""
        mock_table = Mock()
        mock_table.get_item.return_value = {}
        mock_dynamodb.return_value.Table.return_value = mock_table
        
        event = {
            'body': '{"operation": "reboot_instance", "instance_id": "nonexistent-db", "parameters": {}}',
            'requestContext': {'identity': {'userId': 'test-user'}}
        }
        
        response = self.handler.handle_request(event)
        
        self.assertEqual(response['statusCode'], 404)
        self.assertIn('not found', response['body'])
    
    def test_handle_request_invalid_json(self):
        """Test handling of invalid JSON in request body."""
        event = {
            'body': 'invalid json',
            'requestContext': {'identity': {}}
        }
        
        response = self.handler.handle_request(event)
        
        self.assertEqual(response['statusCode'], 500)


if __name__ == '__main__':
    unittest.main()
