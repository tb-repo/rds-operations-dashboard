#!/usr/bin/env python3
"""
Unit Tests for Cost Trend Tracking

Tests the cost snapshot storage, trend calculation, and reporting functionality.
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime, timedelta
from decimal import Decimal
import sys
import os

# Add parent directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(os.path.join(os.path.dirname(__file__), '../cost-analyzer'))

from reporting import CostReporter


class TestCostTrendTracking(unittest.TestCase):
    """Test cost trend tracking functionality."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.config = {
            's3_bucket': 'test-bucket',
            'cost_snapshots_table': 'test-cost-snapshots'
        }
        
        # Mock AWS clients
        self.mock_s3 = Mock()
        self.mock_dynamodb = Mock()
        self.mock_cloudwatch = Mock()
        
        with patch('reporting.get_s3_client', return_value=self.mock_s3), \
             patch('reporting.get_dynamodb_client', return_value=self.mock_dynamodb), \
             patch('reporting.get_cloudwatch_client', return_value=self.mock_cloudwatch):
            self.reporter = CostReporter(self.config)
    
    def test_store_cost_snapshot(self):
        """Test storing daily cost snapshot in DynamoDB."""
        total_cost = Decimal('12450.75')
        cost_aggregations = {
            'by_account': {'123456789012': Decimal('8500.50')},
            'by_region': {'ap-southeast-1': Decimal('9338.06')},
            'by_engine': {'postgres': Decimal('7470.45')},
            'by_instance_family': {'db.r6g': Decimal('5000.00')}
        }
        instance_count = 52
        
        # Execute
        self.reporter.store_cost_snapshot(total_cost, cost_aggregations, instance_count)
        
        # Verify DynamoDB put_item was called
        self.mock_dynamodb.put_item.assert_called_once()
        call_args = self.mock_dynamodb.put_item.call_args
        
        # Verify table name
        self.assertEqual(call_args[1]['TableName'], 'test-cost-snapshots')
        
        # Verify item structure
        item = call_args[1]['Item']
        self.assertIn('snapshot_date', item)
        self.assertIn('total_monthly_cost', item)
        self.assertIn('instance_count', item)
    
    def test_calculate_cost_trends_with_previous_data(self):
        """Test cost trend calculation with historical data."""
        # Mock current snapshot
        current_snapshot = {
            'snapshot_date': '2025-11-13',
            'total_monthly_cost': 12450.75,
            'instance_count': 52
        }
        
        # Mock previous month snapshot
        previous_snapshot = {
            'snapshot_date': '2025-10-14',
            'total_monthly_cost': 11800.50,
            'instance_count': 50
        }
        
        # Mock _get_snapshot_by_date to return test data
        def mock_get_snapshot(date):
            if date == datetime.utcnow().strftime('%Y-%m-%d'):
                return current_snapshot
            elif date == (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d'):
                return previous_snapshot
            return None
        
        self.reporter._get_snapshot_by_date = Mock(side_effect=mock_get_snapshot)
        
        # Execute
        trends = self.reporter.calculate_cost_trends()
        
        # Verify
        self.assertIn('current_cost', trends)
        self.assertIn('month_over_month', trends)
        
        mom = trends['month_over_month']
        self.assertEqual(mom['previous_cost'], 11800.50)
        self.assertAlmostEqual(mom['cost_change'], 650.25, places=2)
        self.assertAlmostEqual(mom['cost_change_percentage'], 5.5, places=1)
        self.assertEqual(mom['trend'], 'increasing')
    
    def test_calculate_cost_trends_decreasing(self):
        """Test cost trend calculation when costs are decreasing."""
        current_snapshot = {
            'snapshot_date': '2025-11-13',
            'total_monthly_cost': 11000.00,
            'instance_count': 48
        }
        
        previous_snapshot = {
            'snapshot_date': '2025-10-14',
            'total_monthly_cost': 12000.00,
            'instance_count': 52
        }
        
        def mock_get_snapshot(date):
            if date == datetime.utcnow().strftime('%Y-%m-%d'):
                return current_snapshot
            elif date == (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d'):
                return previous_snapshot
            return None
        
        self.reporter._get_snapshot_by_date = Mock(side_effect=mock_get_snapshot)
        
        # Execute
        trends = self.reporter.calculate_cost_trends()
        
        # Verify decreasing trend
        mom = trends['month_over_month']
        self.assertEqual(mom['cost_change'], -1000.00)
        self.assertAlmostEqual(mom['cost_change_percentage'], -8.3, places=1)
        self.assertEqual(mom['trend'], 'decreasing')
    
    def test_calculate_cost_trends_no_previous_data(self):
        """Test cost trend calculation with no historical data."""
        current_snapshot = {
            'snapshot_date': '2025-11-13',
            'total_monthly_cost': 12450.75,
            'instance_count': 52
        }
        
        def mock_get_snapshot(date):
            if date == datetime.utcnow().strftime('%Y-%m-%d'):
                return current_snapshot
            return None
        
        self.reporter._get_snapshot_by_date = Mock(side_effect=mock_get_snapshot)
        
        # Execute
        trends = self.reporter.calculate_cost_trends()
        
        # Verify - should have current data but no MoM comparison
        self.assertIn('current_cost', trends)
        self.assertNotIn('month_over_month', trends)
    
    def test_publish_cost_metrics(self):
        """Test publishing cost metrics to CloudWatch."""
        total_cost = Decimal('12450.75')
        cost_aggregations = {
            'by_account': {
                '123456789012': Decimal('8500.50'),
                '234567890123': Decimal('3950.25')
            },
            'by_region': {
                'ap-southeast-1': Decimal('9338.06'),
                'eu-west-2': Decimal('1867.61')
            },
            'by_engine': {'postgres': Decimal('7470.45')},
            'by_instance_family': {'db.r6g': Decimal('5000.00')}
        }
        
        # Execute
        self.reporter.publish_cost_metrics(total_cost, cost_aggregations)
        
        # Verify CloudWatch put_metric_data was called
        self.assertTrue(self.mock_cloudwatch.put_metric_data.called)
        
        # Verify total cost metric
        calls = self.mock_cloudwatch.put_metric_data.call_args_list
        first_call = calls[0]
        self.assertEqual(first_call[1]['Namespace'], 'RDSDashboard')
        
        metric_data = first_call[1]['MetricData']
        self.assertEqual(metric_data[0]['MetricName'], 'TotalMonthlyCost')
        self.assertEqual(metric_data[0]['Value'], 12450.75)
    
    def test_generate_monthly_trend_report(self):
        """Test generating monthly trend report."""
        # Mock recent snapshots
        snapshots = [
            {
                'snapshot_date': f'2025-11-{str(i).zfill(2)}',
                'total_monthly_cost': 12000 + (i * 10),
                'instance_count': 50 + i
            }
            for i in range(1, 11)  # 10 days of data
        ]
        
        self.reporter._get_recent_snapshots = Mock(return_value=snapshots)
        self.reporter.calculate_cost_trends = Mock(return_value={
            'current_cost': 12100,
            'month_over_month': {
                'cost_change': 100,
                'cost_change_percentage': 0.8,
                'trend': 'increasing'
            }
        })
        
        # Execute
        trend_report = self.reporter.generate_monthly_trend_report()
        
        # Verify
        self.assertIn('report_type', trend_report)
        self.assertEqual(trend_report['report_type'], 'monthly_trend')
        self.assertIn('statistics', trend_report)
        self.assertIn('daily_costs', trend_report)
        self.assertEqual(len(trend_report['daily_costs']), 10)
        
        # Verify statistics
        stats = trend_report['statistics']
        self.assertIn('average_cost', stats)
        self.assertIn('minimum_cost', stats)
        self.assertIn('maximum_cost', stats)
    
    def test_save_trend_report_to_s3(self):
        """Test saving trend report to S3."""
        trend_report = {
            'report_type': 'monthly_trend',
            'generated_at': '2025-11-13T00:00:00Z',
            'period_days': 30,
            'statistics': {
                'average_cost': 12000.00,
                'minimum_cost': 11500.00,
                'maximum_cost': 12500.00
            }
        }
        
        # Execute
        s3_key = self.reporter.save_trend_report_to_s3(trend_report)
        
        # Verify S3 put_object was called
        self.mock_s3.put_object.assert_called_once()
        call_args = self.mock_s3.put_object.call_args
        
        # Verify bucket and key
        self.assertEqual(call_args[1]['Bucket'], 'test-bucket')
        self.assertIn('cost_trend_', call_args[1]['Key'])
        self.assertIn('cost-reports/', call_args[1]['Key'])
        
        # Verify content type and encryption
        self.assertEqual(call_args[1]['ContentType'], 'application/json')
        self.assertEqual(call_args[1]['ServerSideEncryption'], 'AES256')
    
    def test_convert_to_dynamodb_item(self):
        """Test converting Python dict to DynamoDB item format."""
        data = {
            'snapshot_date': '2025-11-13',
            'total_monthly_cost': 12450.75,
            'instance_count': 52,
            'cost_by_account': {'123456789012': 8500.50}
        }
        
        # Execute
        dynamodb_item = self.reporter._convert_to_dynamodb_item(data)
        
        # Verify structure
        self.assertIn('snapshot_date', dynamodb_item)
        self.assertIn('S', dynamodb_item['snapshot_date'])
        self.assertIn('total_monthly_cost', dynamodb_item)
        self.assertIn('N', dynamodb_item['total_monthly_cost'])
    
    def test_convert_from_dynamodb_item(self):
        """Test converting DynamoDB item to Python dict."""
        dynamodb_item = {
            'snapshot_date': {'S': '2025-11-13'},
            'total_monthly_cost': {'N': '12450.75'},
            'instance_count': {'N': '52'}
        }
        
        # Execute
        data = self.reporter._convert_from_dynamodb_item(dynamodb_item)
        
        # Verify
        self.assertEqual(data['snapshot_date'], '2025-11-13')
        self.assertEqual(data['total_monthly_cost'], Decimal('12450.75'))
        self.assertEqual(data['instance_count'], 52)


class TestCostTrendEdgeCases(unittest.TestCase):
    """Test edge cases for cost trend tracking."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.config = {
            's3_bucket': 'test-bucket',
            'cost_snapshots_table': 'test-cost-snapshots'
        }
        
        with patch('reporting.get_s3_client'), \
             patch('reporting.get_dynamodb_client'), \
             patch('reporting.get_cloudwatch_client'):
            self.reporter = CostReporter(self.config)
    
    def test_zero_cost_trend(self):
        """Test trend calculation when previous cost is zero."""
        current_snapshot = {'total_monthly_cost': 1000.00}
        previous_snapshot = {'total_monthly_cost': 0}
        
        def mock_get_snapshot(date):
            if date == datetime.utcnow().strftime('%Y-%m-%d'):
                return current_snapshot
            elif date == (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d'):
                return previous_snapshot
            return None
        
        self.reporter._get_snapshot_by_date = Mock(side_effect=mock_get_snapshot)
        
        # Execute
        trends = self.reporter.calculate_cost_trends()
        
        # Verify - should handle division by zero
        mom = trends.get('month_over_month', {})
        self.assertEqual(mom.get('cost_change_percentage', 0), 0)
    
    def test_empty_cost_aggregations(self):
        """Test publishing metrics with empty aggregations."""
        total_cost = Decimal('0')
        cost_aggregations = {
            'by_account': {},
            'by_region': {},
            'by_engine': {},
            'by_instance_family': {}
        }
        
        # Should not raise exception
        try:
            self.reporter.publish_cost_metrics(total_cost, cost_aggregations)
        except Exception as e:
            self.fail(f"publish_cost_metrics raised exception: {e}")


if __name__ == '__main__':
    unittest.main()
