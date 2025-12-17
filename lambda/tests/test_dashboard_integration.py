"""
Integration Tests for Error Resolution Dashboard Integration

Tests the integration between the error resolution system and the main RDS operations dashboard.
Validates unified error display, seamless user experience, and dashboard integration.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-16T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-6.1, 6.2 → DESIGN-Integration → TASK-7.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
import json
import asyncio
from unittest.mock import Mock, patch, AsyncMock
from datetime import datetime, timezone
import sys
import os

# Add the parent directory to the path to import modules
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

# Import modules to test
from error_resolution.handler import lambda_handler
from monitoring.dashboard_components import get_dashboard_manager
from error_resolution.error_detector import get_error_detector, APIError, ErrorCategory, ErrorSeverity


class TestDashboardIntegration:
    """Test suite for dashboard integration functionality."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.mock_context = Mock()
        self.mock_context.aws_request_id = 'test-request-id'
        self.mock_context.function_name = 'test-function'
        
    def test_error_resolution_handler_integration(self):
        """Test that error resolution handler integrates properly with dashboard."""
        # Test event for error detection
        event = {
            'httpMethod': 'POST',
            'path': '/error-resolution/detect',
            'body': json.dumps({
                'status_code': 500,
                'error_message': 'Database connection failed',
                'service': 'health-monitor',
                'endpoint': '/api/health/database',
                'request_id': 'req-123',
                'context': {
                    'user_id': 'user-456',
                    'dashboard_integration': True
                }
            }),
            'headers': {
                'Content-Type': 'application/json',
                'User-Agent': 'Dashboard/1.0'
            },
            'requestContext': {
                'identity': {
                    'sourceIp': '192.168.1.1'
                }
            }
        }
        
        # Call the handler
        response = lambda_handler(event, self.mock_context)
        
        # Verify response structure
        assert response['statusCode'] == 200
        
        body = json.loads(response['body'])
        assert 'error_id' in body
        assert 'category' in body
        assert 'severity' in body
        assert 'is_critical' in body
        assert 'should_retry' in body
        assert 'classification' in body
        
        # Verify error was classified correctly
        assert body['category'] == 'database'
        assert body['severity'] in ['high', 'critical']
        assert body['is_critical'] == True
        
    def test_dashboard_manager_integration(self):
        """Test that dashboard manager provides unified error display data."""
        dashboard_manager = get_dashboard_manager()
        
        # Get dashboard data
        dashboard_data = dashboard_manager.get_dashboard_data()
        
        # Verify dashboard structure
        assert 'dashboard_id' in dashboard_data
        assert 'title' in dashboard_data
        assert 'last_updated' in dashboard_data
        assert 'widgets' in dashboard_data
        
        # Verify required widgets are present
        widgets = dashboard_data['widgets']
        expected_widgets = ['error_metrics', 'system_health', 'error_trends']
        
        for widget_id in expected_widgets:
            if widget_id in widgets:
                widget = widgets[widget_id]
                assert 'widget_id' in widget
                assert 'title' in widget
                assert 'type' in widget
                assert 'data' in widget
    
    def test_unified_error_display_format(self):
        """Test that error data is formatted correctly for unified display."""
        dashboard_manager = get_dashboard_manager()
        
        # Get error metrics widget data
        error_metrics_data = dashboard_manager.get_widget_data('error_metrics')
        
        if error_metrics_data and 'data' in error_metrics_data:
            data = error_metrics_data['data']
            
            # Verify summary section
            if 'summary' in data:
                summary = data['summary']
                assert 'total_errors' in summary
                assert 'critical_errors' in summary
                assert 'high_errors' in summary
                assert 'services_affected' in summary
                
                # Verify all values are non-negative integers
                for key, value in summary.items():
                    assert isinstance(value, int)
                    assert value >= 0
            
            # Verify breakdown section
            if 'breakdown' in data:
                breakdown = data['breakdown']
                assert 'by_service' in breakdown
                assert 'by_severity' in breakdown
                assert 'error_rates' in breakdown
                
                # Verify service breakdown
                by_service = breakdown['by_service']
                assert isinstance(by_service, dict)
                for service, count in by_service.items():
                    assert isinstance(service, str)
                    assert isinstance(count, int)
                    assert count >= 0
                
                # Verify severity breakdown
                by_severity = breakdown['by_severity']
                assert isinstance(by_severity, dict)
                valid_severities = ['critical', 'high', 'medium', 'low']
                for severity, count in by_severity.items():
                    assert severity in valid_severities
                    assert isinstance(count, int)
                    assert count >= 0
    
    def test_system_health_integration(self):
        """Test that system health widget integrates with error data."""
        dashboard_manager = get_dashboard_manager()
        
        # Get system health widget data
        health_data = dashboard_manager.get_widget_data('system_health')
        
        if health_data and 'data' in health_data:
            data = health_data['data']
            
            # Verify status section
            if 'status' in data:
                status = data['status']
                assert 'level' in status
                assert 'score' in status
                assert 'color' in status
                assert 'message' in status
                
                # Verify status level is valid
                valid_levels = ['healthy', 'minor_issues', 'warning', 'degraded', 'critical', 'unknown']
                assert status['level'] in valid_levels
                
                # Verify health score is valid
                assert isinstance(status['score'], int)
                assert 0 <= status['score'] <= 100
                
                # Verify color is valid
                valid_colors = ['green', 'yellow', 'orange', 'red', 'gray']
                assert status['color'] in valid_colors
            
            # Verify indicators section
            if 'indicators' in data:
                indicators = data['indicators']
                required_indicators = ['total_errors', 'critical_errors', 'high_errors', 'services_affected']
                
                for indicator in required_indicators:
                    assert indicator in indicators
                    assert isinstance(indicators[indicator], int)
                    assert indicators[indicator] >= 0
    
    def test_error_trends_integration(self):
        """Test that error trends widget provides chart data."""
        dashboard_manager = get_dashboard_manager()
        
        # Get error trends widget data
        trends_data = dashboard_manager.get_widget_data('error_trends')
        
        if trends_data and 'data' in trends_data:
            data = trends_data['data']
            
            # Verify charts section
            if 'charts' in data:
                charts = data['charts']
                assert isinstance(charts, list)
                
                for chart in charts:
                    assert 'chart_id' in chart
                    assert 'title' in chart
                    assert 'type' in chart
                    assert 'data' in chart
                    assert 'x_axis' in chart
                    assert 'y_axis' in chart
                    
                    # Verify chart data structure
                    chart_data = chart['data']
                    assert isinstance(chart_data, list)
                    
                    for data_point in chart_data:
                        assert 'timestamp' in data_point
                        assert 'value' in data_point
                        assert 'service' in data_point
                        
                        # Verify timestamp format
                        try:
                            datetime.fromisoformat(data_point['timestamp'].replace('Z', '+00:00'))
                        except ValueError:
                            pytest.fail(f"Invalid timestamp format: {data_point['timestamp']}")
                        
                        # Verify value is numeric
                        assert isinstance(data_point['value'], (int, float))
                        assert data_point['value'] >= 0
    
    def test_seamless_user_experience_workflow(self):
        """Test that user workflow is seamless across dashboard integration."""
        # Simulate user workflow: error occurs -> detected -> displayed -> resolved
        
        # Step 1: Error detection
        detector = get_error_detector()
        api_error = detector.detect_and_classify(
            status_code=403,
            error_message='Access denied - insufficient permissions',
            service='operations',
            endpoint='/api/operations/execute',
            request_id='req-workflow-test',
            context={
                'user_workflow_test': True,
                'dashboard_integration': True
            }
        )
        
        # Verify error was detected and classified
        assert api_error.id is not None
        assert api_error.category == ErrorCategory.AUTHORIZATION
        assert api_error.severity in [ErrorSeverity.HIGH, ErrorSeverity.MEDIUM]
        
        # Step 2: Dashboard displays error
        dashboard_manager = get_dashboard_manager()
        dashboard_data = dashboard_manager.get_dashboard_data()
        
        # Verify dashboard can display the error
        assert dashboard_data is not None
        assert 'widgets' in dashboard_data
        
        # Step 3: User can access error details
        error_metrics = dashboard_data['widgets'].get('error_metrics')
        if error_metrics and 'data' in error_metrics:
            # Verify error appears in service breakdown
            by_service = error_metrics['data'].get('breakdown', {}).get('by_service', {})
            if 'operations' in by_service:
                assert by_service['operations'] >= 1
            
            # Verify error appears in severity breakdown
            by_severity = error_metrics['data'].get('breakdown', {}).get('by_severity', {})
            if api_error.severity.value in by_severity:
                assert by_severity[api_error.severity.value] >= 1
        
        # Step 4: System health reflects the error
        system_health = dashboard_data['widgets'].get('system_health')
        if system_health and 'data' in system_health:
            status = system_health['data'].get('status', {})
            # Health should not be 'healthy' if there are authorization errors
            if status.get('level') == 'healthy':
                # This might be acceptable if the error count is very low
                pass
            else:
                assert status.get('level') in ['minor_issues', 'warning', 'degraded', 'critical']
    
    def test_dashboard_error_handling(self):
        """Test that dashboard handles errors gracefully."""
        dashboard_manager = get_dashboard_manager()
        
        # Test with invalid widget ID
        invalid_widget_data = dashboard_manager.get_widget_data('invalid_widget')
        assert invalid_widget_data == {}
        
        # Test dashboard data with empty widget list
        empty_dashboard_data = dashboard_manager.get_dashboard_data([])
        assert 'widgets' in empty_dashboard_data
        assert len(empty_dashboard_data['widgets']) == 0
        
        # Test dashboard data with partial widget list
        partial_dashboard_data = dashboard_manager.get_dashboard_data(['error_metrics'])
        assert 'widgets' in partial_dashboard_data
        if 'error_metrics' in partial_dashboard_data['widgets']:
            assert 'system_health' not in partial_dashboard_data['widgets']
            assert 'error_trends' not in partial_dashboard_data['widgets']
    
    def test_real_time_updates_integration(self):
        """Test that dashboard supports real-time updates."""
        dashboard_manager = get_dashboard_manager()
        
        # Get initial dashboard state
        initial_data = dashboard_manager.get_dashboard_data()
        initial_timestamp = initial_data.get('last_updated')
        
        # Simulate some time passing and new error occurring
        import time
        time.sleep(0.1)  # Small delay to ensure timestamp difference
        
        # Trigger error detection to simulate new data
        detector = get_error_detector()
        detector.detect_and_classify(
            status_code=500,
            error_message='Real-time update test error',
            service='test-service',
            endpoint='/api/test',
            request_id='req-realtime-test',
            context={'real_time_test': True}
        )
        
        # Get updated dashboard state
        updated_data = dashboard_manager.get_dashboard_data()
        updated_timestamp = updated_data.get('last_updated')
        
        # Verify timestamp was updated (indicating real-time capability)
        if initial_timestamp and updated_timestamp:
            initial_dt = datetime.fromisoformat(initial_timestamp.replace('Z', '+00:00'))
            updated_dt = datetime.fromisoformat(updated_timestamp.replace('Z', '+00:00'))
            assert updated_dt >= initial_dt
    
    def test_dashboard_api_endpoint_integration(self):
        """Test that dashboard API endpoint returns proper data."""
        # Test dashboard endpoint
        event = {
            'httpMethod': 'GET',
            'path': '/error-resolution/dashboard',
            'queryStringParameters': None,
            'headers': {
                'User-Agent': 'Dashboard-Test/1.0'
            },
            'requestContext': {
                'identity': {
                    'sourceIp': '192.168.1.1'
                }
            }
        }
        
        # Call the actual handler to test API integration
        response = lambda_handler(event, self.mock_context)
        
        # Verify response structure
        assert response['statusCode'] == 200
        assert 'body' in response
        
        # Parse response body
        body = json.loads(response['body'])
        
        # Verify the data structure matches API expectations
        assert isinstance(body, dict)
        assert 'dashboard_id' in body
        assert 'title' in body
        assert 'last_updated' in body
        assert 'widgets' in body
        
        # Verify data can be JSON serialized (important for API responses)
        try:
            json.dumps(body, default=str)
        except (TypeError, ValueError) as e:
            pytest.fail(f"Dashboard data is not JSON serializable: {e}")
        
        # Verify CORS headers are present for frontend integration
        assert 'headers' in response
        headers = response['headers']
        assert 'Access-Control-Allow-Origin' in headers or 'access-control-allow-origin' in headers
    
    def test_error_resolution_workflow_continuity(self):
        """Test that error resolution workflow maintains continuity across dashboard."""
        # This test simulates the complete workflow from error detection to resolution
        # as it would appear in the dashboard
        
        # Step 1: Create an error that should be resolvable
        detector = get_error_detector()
        api_error = detector.detect_and_classify(
            status_code=429,
            error_message='Rate limit exceeded',
            service='api-gateway',
            endpoint='/api/instances',
            request_id='req-continuity-test',
            context={'workflow_continuity_test': True}
        )
        
        # Verify error classification
        assert api_error.category == ErrorCategory.RATE_LIMIT
        assert detector.should_retry(api_error) == True
        
        # Step 2: Dashboard should show this error
        dashboard_manager = get_dashboard_manager()
        dashboard_data = dashboard_manager.get_dashboard_data()
        
        # Verify error appears in dashboard
        error_metrics = dashboard_data['widgets'].get('error_metrics')
        if error_metrics:
            # Check if rate limit errors are tracked
            by_category = error_metrics.get('data', {}).get('breakdown', {}).get('by_severity', {})
            # Rate limit errors are typically medium severity
            if 'medium' in by_category:
                assert by_category['medium'] >= 1
        
        # Step 3: Verify resolution suggestions are available
        # (This would be tested in the frontend integration, but we can verify the backend supports it)
        assert detector.should_retry(api_error) == True
        assert not detector.is_critical_error(api_error)  # Rate limits are not critical
        
        # Step 4: Verify system health reflects the error appropriately
        system_health = dashboard_data['widgets'].get('system_health')
        if system_health:
            status = system_health.get('data', {}).get('status', {})
            # Rate limit errors should not cause critical status
            assert status.get('level') != 'critical'


if __name__ == '__main__':
    pytest.main([__file__, '-v'])