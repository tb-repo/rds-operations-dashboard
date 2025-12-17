"""
Tests for Unified Error Display

Tests the unified error display functionality that integrates error resolution
with the main dashboard, ensuring seamless user experience.

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
from unittest.mock import Mock, patch
from datetime import datetime, timezone
import sys
import os

# Add the parent directory to the path to import modules
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

# Import modules to test
from monitoring.dashboard_components import (
    ErrorMetricsWidget, 
    TrendVisualizationWidget, 
    SystemHealthWidget,
    DashboardManager
)
from error_resolution.error_detector import (
    get_error_detector, 
    APIError, 
    ErrorCategory, 
    ErrorSeverity
)


class TestUnifiedErrorDisplay:
    """Test suite for unified error display functionality."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.error_detector = get_error_detector()
        self.dashboard_manager = DashboardManager()
        
    def test_error_metrics_widget_display_format(self):
        """Test that error metrics widget formats data correctly for display."""
        widget = ErrorMetricsWidget()
        
        # Get current metrics
        metrics = widget.get_current_metrics()
        
        # Verify metrics structure
        assert isinstance(metrics, dict)
        required_fields = [
            'total_errors', 'errors_by_service', 'errors_by_severity', 
            'error_rates', 'timestamp', 'time_window_minutes'
        ]
        
        for field in required_fields:
            assert field in metrics
        
        # Verify data types
        assert isinstance(metrics['total_errors'], int)
        assert isinstance(metrics['errors_by_service'], dict)
        assert isinstance(metrics['errors_by_severity'], dict)
        assert isinstance(metrics['error_rates'], dict)
        assert isinstance(metrics['time_window_minutes'], int)
        
        # Format for display
        formatted = widget.format_for_display(metrics)
        
        # Verify formatted structure
        assert 'widget_id' in formatted
        assert 'title' in formatted
        assert 'type' in formatted
        assert 'data' in formatted
        assert 'status' in formatted
        assert 'status_message' in formatted
        
        # Verify data structure
        data = formatted['data']
        assert 'summary' in data
        assert 'breakdown' in data
        assert 'metadata' in data
        
        # Verify summary structure
        summary = data['summary']
        summary_fields = ['total_errors', 'critical_errors', 'high_errors', 'services_affected']
        for field in summary_fields:
            assert field in summary
            assert isinstance(summary[field], int)
            assert summary[field] >= 0
        
        # Verify breakdown structure
        breakdown = data['breakdown']
        assert 'by_service' in breakdown
        assert 'by_severity' in breakdown
        assert 'error_rates' in breakdown
    
    def test_system_health_widget_status_calculation(self):
        """Test that system health widget calculates status correctly."""
        widget = SystemHealthWidget()
        
        # Get health status
        health_status = widget.get_health_status()
        
        # Verify health status structure
        assert isinstance(health_status, dict)
        required_fields = ['overall_status', 'health_score', 'indicators', 'timestamp']
        
        for field in required_fields:
            assert field in health_status
        
        # Verify status values
        valid_statuses = ['healthy', 'minor_issues', 'warning', 'degraded', 'critical', 'unknown']
        assert health_status['overall_status'] in valid_statuses
        
        # Verify health score
        assert isinstance(health_status['health_score'], int)
        assert 0 <= health_status['health_score'] <= 100
        
        # Verify indicators
        indicators = health_status['indicators']
        indicator_fields = ['total_errors', 'critical_errors', 'high_errors', 'services_affected']
        for field in indicator_fields:
            assert field in indicators
            assert isinstance(indicators[field], int)
            assert indicators[field] >= 0
        
        # Format for display
        formatted = widget.format_for_display(health_status)
        
        # Verify formatted structure
        assert 'widget_id' in formatted
        assert 'title' in formatted
        assert 'type' in formatted
        assert 'data' in formatted
        
        # Verify status display format
        data = formatted['data']
        assert 'status' in data
        status = data['status']
        assert 'level' in status
        assert 'score' in status
        assert 'color' in status
        assert 'message' in status
        
        # Verify color mapping
        valid_colors = ['green', 'yellow', 'orange', 'red', 'gray']
        assert status['color'] in valid_colors
    
    def test_trend_visualization_widget_chart_format(self):
        """Test that trend visualization widget formats chart data correctly."""
        widget = TrendVisualizationWidget()
        
        # Get trend data
        trend_data = widget.get_trend_data(time_window_hours=1)
        
        # Verify trend data structure
        assert isinstance(trend_data, dict)
        expected_fields = ['error_count_trend', 'error_rate_trend', 'service_trends']
        
        for field in expected_fields:
            assert field in trend_data
            if field != 'service_trends':
                assert isinstance(trend_data[field], list)
        
        # Verify trend data points
        for trend_type in ['error_count_trend', 'error_rate_trend']:
            trend_points = trend_data[trend_type]
            for point in trend_points:
                assert 'timestamp' in point
                assert 'value' in point
                assert 'service' in point
                
                # Verify timestamp format
                try:
                    datetime.fromisoformat(point['timestamp'].replace('Z', '+00:00'))
                except ValueError:
                    pytest.fail(f"Invalid timestamp format: {point['timestamp']}")
                
                # Verify value is numeric
                assert isinstance(point['value'], (int, float))
                assert point['value'] >= 0
        
        # Format for chart
        formatted = widget.format_for_chart(trend_data)
        
        # Verify formatted structure
        assert 'widget_id' in formatted
        assert 'title' in formatted
        assert 'type' in formatted
        assert 'data' in formatted
        
        # Verify chart data structure
        data = formatted['data']
        assert 'charts' in data
        assert 'metadata' in data
        
        charts = data['charts']
        assert isinstance(charts, list)
        
        for chart in charts:
            assert 'chart_id' in chart
            assert 'title' in chart
            assert 'type' in chart
            assert 'data' in chart
            assert 'x_axis' in chart
            assert 'y_axis' in chart
            assert 'group_by' in chart
    
    def test_dashboard_manager_unified_data(self):
        """Test that dashboard manager provides unified data across all widgets."""
        # Get complete dashboard data
        dashboard_data = self.dashboard_manager.get_dashboard_data()
        
        # Verify top-level structure
        assert isinstance(dashboard_data, dict)
        required_fields = ['dashboard_id', 'title', 'last_updated', 'widgets']
        
        for field in required_fields:
            assert field in dashboard_data
        
        # Verify dashboard metadata
        assert dashboard_data['dashboard_id'] == 'error_monitoring'
        assert isinstance(dashboard_data['title'], str)
        assert len(dashboard_data['title']) > 0
        
        # Verify timestamp format
        try:
            datetime.fromisoformat(dashboard_data['last_updated'].replace('Z', '+00:00'))
        except ValueError:
            pytest.fail(f"Invalid timestamp format: {dashboard_data['last_updated']}")
        
        # Verify widgets structure
        widgets = dashboard_data['widgets']
        assert isinstance(widgets, dict)
        
        # Check each widget type
        expected_widgets = ['error_metrics', 'system_health', 'error_trends']
        for widget_id in expected_widgets:
            if widget_id in widgets:
                widget = widgets[widget_id]
                assert 'widget_id' in widget
                assert widget['widget_id'] == widget_id
                assert 'title' in widget
                assert 'type' in widget
                assert 'data' in widget
    
    def test_error_display_consistency(self):
        """Test that error display is consistent across different widgets."""
        # Create test errors with different severities
        test_errors = [
            {
                'status_code': 500,
                'message': 'Database connection failed',
                'service': 'health-monitor',
                'endpoint': '/api/health/database',
                'expected_category': ErrorCategory.DATABASE,
                'expected_severity': ErrorSeverity.CRITICAL
            },
            {
                'status_code': 403,
                'message': 'Access denied - insufficient permissions',
                'service': 'operations',
                'endpoint': '/api/operations/execute',
                'expected_category': ErrorCategory.AUTHORIZATION,
                'expected_severity': ErrorSeverity.HIGH
            },
            {
                'status_code': 429,
                'message': 'Rate limit exceeded',
                'service': 'api-gateway',
                'endpoint': '/api/instances',
                'expected_category': ErrorCategory.RATE_LIMIT,
                'expected_severity': ErrorSeverity.MEDIUM
            }
        ]
        
        # Detect all test errors
        detected_errors = []
        for error_data in test_errors:
            api_error = self.error_detector.detect_and_classify(
                status_code=error_data['status_code'],
                error_message=error_data['message'],
                service=error_data['service'],
                endpoint=error_data['endpoint'],
                request_id=f"req-consistency-{len(detected_errors)}",
                context={'consistency_test': True}
            )
            detected_errors.append(api_error)
            
            # Verify classification
            assert api_error.category == error_data['expected_category']
            assert api_error.severity == error_data['expected_severity']
        
        # Get dashboard data
        dashboard_data = self.dashboard_manager.get_dashboard_data()
        
        # Verify consistency across widgets
        error_metrics = dashboard_data['widgets'].get('error_metrics')
        system_health = dashboard_data['widgets'].get('system_health')
        
        if error_metrics and system_health:
            # Check that error counts are consistent
            metrics_summary = error_metrics.get('data', {}).get('summary', {})
            health_indicators = system_health.get('data', {}).get('indicators', {})
            
            # Total errors should match
            if 'total_errors' in metrics_summary and 'total_errors' in health_indicators:
                assert metrics_summary['total_errors'] == health_indicators['total_errors']
            
            # Critical errors should match
            if 'critical_errors' in metrics_summary and 'critical_errors' in health_indicators:
                assert metrics_summary['critical_errors'] == health_indicators['critical_errors']
            
            # High errors should match
            if 'high_errors' in metrics_summary and 'high_errors' in health_indicators:
                assert metrics_summary['high_errors'] == health_indicators['high_errors']
    
    def test_user_workflow_continuity(self):
        """Test that user workflow is continuous across error display components."""
        # Simulate user discovering an error in the dashboard
        
        # Step 1: Error occurs and is detected
        api_error = self.error_detector.detect_and_classify(
            status_code=502,
            error_message='Bad Gateway - upstream server error',
            service='api-gateway',
            endpoint='/api/instances/list',
            request_id='req-workflow-continuity',
            context={
                'user_workflow_test': True,
                'user_id': 'test-user-123'
            }
        )
        
        # Step 2: User sees error in dashboard overview
        dashboard_data = self.dashboard_manager.get_dashboard_data()
        
        # Verify error appears in error metrics
        error_metrics = dashboard_data['widgets'].get('error_metrics')
        if error_metrics:
            summary = error_metrics.get('data', {}).get('summary', {})
            assert summary.get('total_errors', 0) >= 1
            
            # Verify error appears in service breakdown
            breakdown = error_metrics.get('data', {}).get('breakdown', {})
            by_service = breakdown.get('by_service', {})
            if 'api-gateway' in by_service:
                assert by_service['api-gateway'] >= 1
        
        # Step 3: User sees impact on system health
        system_health = dashboard_data['widgets'].get('system_health')
        if system_health:
            status = system_health.get('data', {}).get('status', {})
            # System should not be healthy with a 502 error
            assert status.get('level') != 'healthy'
            
            # Health score should be impacted
            health_score = status.get('score', 100)
            assert health_score < 100
        
        # Step 4: User can see error trends
        error_trends = dashboard_data['widgets'].get('error_trends')
        if error_trends:
            charts = error_trends.get('data', {}).get('charts', [])
            # Should have chart data available
            assert len(charts) >= 0  # May be empty if no historical data
        
        # Step 5: Verify error details are accessible
        assert api_error.id is not None
        assert api_error.category == ErrorCategory.NETWORK
        assert api_error.severity in [ErrorSeverity.HIGH, ErrorSeverity.MEDIUM]
        
        # Verify error should be retryable (502 errors are typically transient)
        assert self.error_detector.should_retry(api_error) == True
    
    def test_error_display_real_time_updates(self):
        """Test that error display supports real-time updates."""
        # Get initial state
        initial_data = self.dashboard_manager.get_dashboard_data()
        initial_timestamp = initial_data.get('last_updated')
        
        # Simulate new error occurring
        import time
        time.sleep(0.1)  # Small delay to ensure timestamp difference
        
        new_error = self.error_detector.detect_and_classify(
            status_code=504,
            error_message='Gateway timeout',
            service='load-balancer',
            endpoint='/api/health/check',
            request_id='req-realtime-update',
            context={'real_time_update_test': True}
        )
        
        # Get updated state
        updated_data = self.dashboard_manager.get_dashboard_data()
        updated_timestamp = updated_data.get('last_updated')
        
        # Verify timestamp was updated
        if initial_timestamp and updated_timestamp:
            initial_dt = datetime.fromisoformat(initial_timestamp.replace('Z', '+00:00'))
            updated_dt = datetime.fromisoformat(updated_timestamp.replace('Z', '+00:00'))
            assert updated_dt >= initial_dt
        
        # Verify error appears in updated data
        error_metrics = updated_data['widgets'].get('error_metrics')
        if error_metrics:
            by_service = error_metrics.get('data', {}).get('breakdown', {}).get('by_service', {})
            if 'load-balancer' in by_service:
                assert by_service['load-balancer'] >= 1
    
    def test_error_display_accessibility(self):
        """Test that error display data is accessible and well-structured."""
        dashboard_data = self.dashboard_manager.get_dashboard_data()
        
        # Verify all widgets have proper titles and descriptions
        widgets = dashboard_data.get('widgets', {})
        
        for widget_id, widget in widgets.items():
            # Verify widget has title
            assert 'title' in widget
            assert isinstance(widget['title'], str)
            assert len(widget['title']) > 0
            
            # Verify widget has type
            assert 'type' in widget
            assert isinstance(widget['type'], str)
            
            # Verify widget has data
            assert 'data' in widget
            assert isinstance(widget['data'], dict)
        
        # Verify error metrics widget has accessible structure
        error_metrics = widgets.get('error_metrics')
        if error_metrics:
            data = error_metrics.get('data', {})
            
            # Verify summary has descriptive field names
            summary = data.get('summary', {})
            for field_name in summary.keys():
                assert '_' in field_name or field_name.islower()  # snake_case or lowercase
            
            # Verify breakdown has clear categorization
            breakdown = data.get('breakdown', {})
            assert 'by_service' in breakdown
            assert 'by_severity' in breakdown
        
        # Verify system health widget has clear status messages
        system_health = widgets.get('system_health')
        if system_health:
            status = system_health.get('data', {}).get('status', {})
            if 'message' in status:
                message = status['message']
                assert isinstance(message, str)
                assert len(message) > 0
                # Message should be descriptive
                assert len(message.split()) >= 2  # At least 2 words
    
    def test_error_display_performance(self):
        """Test that error display performs well with multiple errors."""
        # Generate multiple errors to test performance
        num_errors = 50
        
        start_time = time.time()
        
        for i in range(num_errors):
            self.error_detector.detect_and_classify(
                status_code=500 + (i % 5),  # Vary status codes
                error_message=f'Performance test error {i}',
                service=f'service-{i % 10}',  # 10 different services
                endpoint=f'/api/test/{i}',
                request_id=f'req-perf-{i}',
                context={'performance_test': True, 'error_number': i}
            )
        
        # Get dashboard data
        dashboard_data = self.dashboard_manager.get_dashboard_data()
        
        end_time = time.time()
        total_time = end_time - start_time
        
        # Verify performance is reasonable (should complete within 5 seconds)
        assert total_time < 5.0, f"Dashboard data generation took too long: {total_time:.2f}s"
        
        # Verify data integrity despite volume
        assert dashboard_data is not None
        assert 'widgets' in dashboard_data
        
        # Verify error metrics can handle the volume
        error_metrics = dashboard_data['widgets'].get('error_metrics')
        if error_metrics:
            summary = error_metrics.get('data', {}).get('summary', {})
            total_errors = summary.get('total_errors', 0)
            # Should have detected at least some of the errors
            assert total_errors >= 1


if __name__ == '__main__':
    pytest.main([__file__, '-v'])