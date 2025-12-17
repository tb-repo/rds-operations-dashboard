"""
Unit Tests for Log Search Handler API

Tests the REST API endpoints for searching, analyzing, and exporting logs
and audit trails from the comprehensive logging system.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-15T16:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.3 → DESIGN-LogSearch → TASK-5.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
import json
from datetime import datetime, timezone, timedelta
from unittest.mock import Mock, patch, MagicMock
import sys
import os

# Add the error-resolution directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error-resolution'))

from log_search_handler import (
    lambda_handler, handle_search_logs, handle_get_log_statistics,
    handle_export_logs, handle_search_audit, handle_get_audit_statistics,
    handle_export_audit, handle_generate_compliance_report,
    handle_analyze_errors, handle_analyze_performance, handle_detect_anomalies,
    handle_health_check
)


class TestLogSearchHandler:
    """Test log search API handler functionality."""
    
    def test_lambda_handler_search_logs(self):
        """Test lambda handler routing to search logs."""
        event = {
            'httpMethod': 'GET',
            'path': '/api/logs/search',
            'queryStringParameters': {
                'q': 'error',
                'level': 'ERROR',
                'limit': '10'
            }
        }
        context = Mock()
        
        with patch('log_search_handler.handle_search_logs') as mock_search:
            mock_search.return_value = {
                'statusCode': 200,
                'body': json.dumps({'results': []})
            }
            
            response = lambda_handler(event, context)
            
            mock_search.assert_called_once_with({
                'q': 'error',
                'level': 'ERROR',
                'limit': '10'
            })
            assert response['statusCode'] == 200
    
    def test_lambda_handler_invalid_method(self):
        """Test lambda handler with invalid HTTP method."""
        event = {
            'httpMethod': 'POST',
            'path': '/api/logs/search',
            'queryStringParameters': {}
        }
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 405
        body = json.loads(response['body'])
        assert body['error'] == 'MethodNotAllowed'
    
    def test_lambda_handler_invalid_path(self):
        """Test lambda handler with invalid path."""
        event = {
            'httpMethod': 'GET',
            'path': '/api/invalid/path',
            'queryStringParameters': {}
        }
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 404
        body = json.loads(response['body'])
        assert body['error'] == 'NotFound'


class TestHandleSearchLogs:
    """Test handle_search_logs functionality."""
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_search_logs_basic(self, mock_get_logger):
        """Test basic log search functionality."""
        # Mock logger and search results
        mock_logger = Mock()
        mock_entry = Mock()
        mock_entry.to_dict.return_value = {
            'id': 'test-1',
            'message': 'Test error message',
            'level': 'ERROR',
            'timestamp': '2023-12-15T10:00:00Z'
        }
        mock_logger.search_logs.return_value = [mock_entry]
        mock_get_logger.return_value = mock_logger
        
        query_params = {
            'q': 'error',
            'level': 'ERROR',
            'limit': '10'
        }
        
        response = handle_search_logs(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['query'] == 'error'
        assert body['total_results'] == 1
        assert len(body['results']) == 1
        assert body['results'][0]['message'] == 'Test error message'
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_search_logs_with_filters(self, mock_get_logger):
        """Test log search with various filters."""
        mock_logger = Mock()
        mock_logger.search_logs.return_value = []
        mock_get_logger.return_value = mock_logger
        
        query_params = {
            'q': 'database',
            'level': 'ERROR',
            'category': 'system',
            'start_time': '2023-12-15T09:00:00Z',
            'end_time': '2023-12-15T10:00:00Z',
            'limit': '50'
        }
        
        response = handle_search_logs(query_params)
        
        assert response['statusCode'] == 200
        
        # Verify search was called with correct filters
        call_args = mock_logger.search_logs.call_args
        assert call_args[0][0] == 'database'  # query
        filters = call_args[1]
        assert filters['limit'] == 50
    
    def test_search_logs_invalid_level(self):
        """Test search logs with invalid level parameter."""
        query_params = {
            'level': 'INVALID_LEVEL'
        }
        
        response = handle_search_logs(query_params)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert body['error'] == 'InvalidParameter'
        assert 'Invalid log level' in body['message']
    
    def test_search_logs_invalid_category(self):
        """Test search logs with invalid category parameter."""
        query_params = {
            'category': 'invalid_category'
        }
        
        response = handle_search_logs(query_params)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert body['error'] == 'InvalidParameter'
        assert 'Invalid category' in body['message']
    
    def test_search_logs_invalid_time_format(self):
        """Test search logs with invalid time format."""
        query_params = {
            'start_time': 'invalid-time-format'
        }
        
        response = handle_search_logs(query_params)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert body['error'] == 'InvalidParameter'
        assert 'Invalid start_time format' in body['message']
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_search_logs_exception_handling(self, mock_get_logger):
        """Test search logs exception handling."""
        mock_get_logger.side_effect = Exception("Database error")
        
        response = handle_search_logs({})
        
        assert response['statusCode'] == 500
        body = json.loads(response['body'])
        assert body['error'] == 'InternalError'


class TestHandleLogStatistics:
    """Test handle_get_log_statistics functionality."""
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_get_log_statistics(self, mock_get_logger):
        """Test getting log statistics."""
        mock_logger = Mock()
        mock_stats = {
            'buffer_statistics': {'current_entries': 100},
            'error_analysis': {'total_errors': 5},
            'logger_version': '1.0.0'
        }
        mock_logger.get_log_statistics.return_value = mock_stats
        mock_get_logger.return_value = mock_logger
        
        response = handle_get_log_statistics()
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'statistics' in body
        assert body['statistics']['logger_version'] == '1.0.0'
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_get_log_statistics_exception(self, mock_get_logger):
        """Test log statistics exception handling."""
        mock_get_logger.side_effect = Exception("Service error")
        
        response = handle_get_log_statistics()
        
        assert response['statusCode'] == 500
        body = json.loads(response['body'])
        assert body['error'] == 'InternalError'


class TestHandleExportLogs:
    """Test handle_export_logs functionality."""
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_export_logs_json(self, mock_get_logger):
        """Test exporting logs in JSON format."""
        mock_logger = Mock()
        mock_logger.export_logs.return_value = '{"logs": []}'
        mock_get_logger.return_value = mock_logger
        
        query_params = {
            'format': 'json',
            'level': 'ERROR'
        }
        
        response = handle_export_logs(query_params)
        
        assert response['statusCode'] == 200
        assert response['headers']['Content-Type'] == 'application/json'
        assert 'logs.json' in response['headers']['Content-Disposition']
        assert response['body'] == '{"logs": []}'
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_export_logs_csv(self, mock_get_logger):
        """Test exporting logs in CSV format."""
        mock_logger = Mock()
        mock_logger.export_logs.return_value = 'id,timestamp,message\n1,2023-12-15,test'
        mock_get_logger.return_value = mock_logger
        
        query_params = {
            'format': 'csv'
        }
        
        response = handle_export_logs(query_params)
        
        assert response['statusCode'] == 200
        assert response['headers']['Content-Type'] == 'text/csv'
        assert 'logs.csv' in response['headers']['Content-Disposition']
        assert 'id,timestamp,message' in response['body']


class TestHandleSearchAudit:
    """Test handle_search_audit functionality."""
    
    @patch('log_search_handler.get_audit_trail')
    def test_search_audit_basic(self, mock_get_audit):
        """Test basic audit search functionality."""
        mock_audit_trail = Mock()
        mock_event = Mock()
        mock_event.to_dict.return_value = {
            'id': 'audit-1',
            'event_type': 'error_detected',
            'action': 'database_connection',
            'outcome': 'failure'
        }
        mock_audit_trail.get_audit_events.return_value = [mock_event]
        mock_get_audit.return_value = mock_audit_trail
        
        query_params = {
            'event_type': 'error_detected',
            'limit': '10'
        }
        
        response = handle_search_audit(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['total_results'] == 1
        assert len(body['results']) == 1
        assert body['results'][0]['event_type'] == 'error_detected'
    
    def test_search_audit_invalid_event_type(self):
        """Test audit search with invalid event type."""
        query_params = {
            'event_type': 'invalid_event_type'
        }
        
        response = handle_search_audit(query_params)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert body['error'] == 'InvalidParameter'
        assert 'Invalid event_type' in body['message']


class TestHandleComplianceReport:
    """Test handle_generate_compliance_report functionality."""
    
    @patch('log_search_handler.get_audit_trail')
    @patch('log_search_handler.ComplianceReporter')
    def test_generate_compliance_report(self, mock_reporter_class, mock_get_audit):
        """Test generating compliance report."""
        mock_audit_trail = Mock()
        mock_get_audit.return_value = mock_audit_trail
        
        mock_reporter = Mock()
        mock_report = {
            'report_id': 'report-123',
            'total_events': 50,
            'summary': {'critical_events': 2}
        }
        mock_reporter.generate_compliance_report.return_value = mock_report
        mock_reporter_class.return_value = mock_reporter
        
        query_params = {
            'type': 'summary',
            'start_time': '2023-12-01T00:00:00Z',
            'end_time': '2023-12-15T23:59:59Z'
        }
        
        response = handle_generate_compliance_report(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'report' in body
        assert body['report']['report_id'] == 'report-123'
        assert body['report']['total_events'] == 50


class TestHandleAnalytics:
    """Test analytics handler functions."""
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_analyze_errors(self, mock_get_logger):
        """Test error pattern analysis."""
        mock_logger = Mock()
        mock_analyzer = Mock()
        mock_analysis = {
            'total_errors': 10,
            'unique_patterns': 3,
            'top_patterns': []
        }
        mock_analyzer.analyze_error_patterns.return_value = mock_analysis
        mock_logger.log_analyzer = mock_analyzer
        mock_get_logger.return_value = mock_logger
        
        query_params = {'hours': '2'}
        
        response = handle_analyze_errors(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'analysis' in body
        assert body['analysis']['total_errors'] == 10
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_analyze_performance(self, mock_get_logger):
        """Test performance trend analysis."""
        mock_logger = Mock()
        mock_analyzer = Mock()
        mock_analysis = {
            'total_performance_entries': 20,
            'response_time_stats': {'average_ms': 150}
        }
        mock_analyzer.analyze_performance_trends.return_value = mock_analysis
        mock_logger.log_analyzer = mock_analyzer
        mock_get_logger.return_value = mock_logger
        
        query_params = {'hours': '1'}
        
        response = handle_analyze_performance(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'analysis' in body
        assert body['analysis']['total_performance_entries'] == 20
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_detect_anomalies(self, mock_get_logger):
        """Test anomaly detection."""
        mock_logger = Mock()
        mock_analyzer = Mock()
        mock_analysis = {
            'total_entries_analyzed': 100,
            'anomalies_detected': 2,
            'anomalies': [
                {'type': 'high_error_rate', 'severity': 'high'}
            ]
        }
        mock_analyzer.detect_anomalies.return_value = mock_analysis
        mock_logger.log_analyzer = mock_analyzer
        mock_get_logger.return_value = mock_logger
        
        query_params = {'hours': '3'}
        
        response = handle_detect_anomalies(query_params)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'analysis' in body
        assert body['analysis']['anomalies_detected'] == 2


class TestHandleHealthCheck:
    """Test health check functionality."""
    
    @patch('log_search_handler.get_comprehensive_logger')
    @patch('log_search_handler.get_audit_trail')
    def test_health_check_healthy(self, mock_get_audit, mock_get_logger):
        """Test health check when service is healthy."""
        mock_logger = Mock()
        mock_logger.get_log_statistics.return_value = {'current_entries': 100}
        mock_get_logger.return_value = mock_logger
        
        mock_audit_trail = Mock()
        mock_audit_trail.get_audit_statistics.return_value = {'total_events': 50}
        mock_get_audit.return_value = mock_audit_trail
        
        response = handle_health_check()
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['status'] == 'healthy'
        assert body['service'] == 'log-search-analysis'
        assert 'statistics' in body
    
    @patch('log_search_handler.get_comprehensive_logger')
    def test_health_check_unhealthy(self, mock_get_logger):
        """Test health check when service is unhealthy."""
        mock_get_logger.side_effect = Exception("Service unavailable")
        
        response = handle_health_check()
        
        assert response['statusCode'] == 503
        body = json.loads(response['body'])
        assert body['status'] == 'unhealthy'
        assert body['service'] == 'log-search-analysis'
        assert 'error' in body


if __name__ == "__main__":
    # Run the unit tests
    pytest.main([__file__, "-v", "--tb=short"])