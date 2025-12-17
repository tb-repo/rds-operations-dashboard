"""
Unit Tests for Dashboard Components

Tests the dashboard components for metrics display accuracy,
real-time updates, and visualization components.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-3.1, 3.2, 3.3 → DESIGN-MonitoringDashboard → TASK-3.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime, timedelta
import json
import sys
import os

# Add the monitoring module to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'monitoring'))
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dashboard_components import (
    ErrorMetricsWidget, TrendVisualizationWidget, SystemHealthWidget,
    DashboardManager, DashboardUpdateFrequency, MetricDisplayConfig
)
from metrics_collector import MetricType, AggregatedMetric


class TestErrorMetricsWidget:
    """Unit tests for ErrorMetricsWidget."""
    
    def setup_method(self):
        """Set up test environment."""
        self.mock_collector = Mock()
        
        # Mock the get_metrics_collector function
        with patch('dashboard_components.get_metrics_collector', return_value=self.mock_collector):
            self.widget = ErrorMetricsWidget("test-error-metrics")
    
    def test_get_current_metrics_success(self):
        """Test successful retrieval of current metrics."""
        # Arrange
        mock_real_time_metrics = {
            'total_errors': 15,
            'errors_by_service': {'service-a': 10, 'service-b': 5},
            'errors_by_severity': {'critical': 2, 'high': 5, 'medium': 8},
            'timestamp': '2025-12-13T14:30:00Z',
            'time_window_minutes': 5
        }
        
        self.mock_collector.get_real_time_metrics.return_value = mock_real_time_metrics
        self.mock_collector.get_error_rate.side_effect = lambda service, window: 2.5 if service == 'service-a' else 1.0
        
        # Act
        result = self.widget.get_current_metrics()
        
        # Assert
        assert result['total_errors'] == 15
        assert result['errors_by_service'] == {'service-a': 10, 'service-b': 5}
        assert result['errors_by_severity'] == {'critical': 2, 'high': 5, 'medium': 8}
        assert result['error_rates'] == {'service-a': 2.5, 'service-b': 1.0}
        assert result['timestamp'] == '2025-12-13T14:30:00Z'
        assert result['time_window_minutes'] == 5
        
        # Verify collector methods were called
        self.mock_collector.get_real_time_metrics.assert_called_once()
        assert self.mock_collector.get_error_rate.call_count == 2
    
    def test_get_current_metrics_error_handling(self):
        """Test error handling in get_current_metrics."""
        # Arrange
        self.mock_collector.get_real_time_metrics.side_effect = Exception("Database connection failed")
        
        # Act
        result = self.widget.get_current_metrics()
        
        # Assert
        assert result['total_errors'] == 0
        assert result['errors_by_service'] == {}
        assert result['errors_by_severity'] == {}
        assert result['error_rates'] == {}
        assert 'error' in result
        assert result['error'] == "Database connection failed"
    
    def test_format_for_display_healthy_status(self):
        """Test formatting metrics for display with healthy status."""
        # Arrange
        metrics = {
            'total_errors': 5,
            'errors_by_service': {'service-a': 3, 'service-b': 2},
            'errors_by_severity': {'low': 3, 'medium': 2},
            'error_rates': {'service-a': 1.5, 'service-b': 1.0},
            'timestamp': '2025-12-13T14:30:00Z',
            'time_window_minutes': 5
        }
        
        # Act
        result = self.widget.format_for_display(metrics)
        
        # Assert
        assert result['widget_id'] == 'test-error-metrics'
        assert result['title'] == 'Error Metrics'
        assert result['type'] == 'error_metrics'
        assert result['status'] == 'healthy'
        assert result['status_message'] == "System operating normally"
        
        # Check data structure
        assert result['data']['summary']['total_errors'] == 5
        assert result['data']['summary']['critical_errors'] == 0
        assert result['data']['summary']['services_affected'] == 2
        assert result['data']['breakdown']['by_service'] == {'service-a': 3, 'service-b': 2}
    
    def test_format_for_display_critical_status(self):
        """Test formatting metrics for display with critical status."""
        # Arrange
        metrics = {
            'total_errors': 25,
            'errors_by_service': {'service-a': 15, 'service-b': 10},
            'errors_by_severity': {'critical': 5, 'high': 10, 'medium': 10},
            'error_rates': {'service-a': 5.0, 'service-b': 3.0},
            'timestamp': '2025-12-13T14:30:00Z',
            'time_window_minutes': 5
        }
        
        # Act
        result = self.widget.format_for_display(metrics)
        
        # Assert
        assert result['status'] == 'critical'
        assert result['status_message'] == "5 critical errors detected"
        assert result['data']['summary']['critical_errors'] == 5
        assert result['data']['summary']['high_errors'] == 10
    
    def test_format_for_display_warning_status(self):
        """Test formatting metrics for display with warning status."""
        # Arrange
        metrics = {
            'total_errors': 15,
            'errors_by_service': {'service-a': 10, 'service-b': 5},
            'errors_by_severity': {'high': 5, 'medium': 10},
            'error_rates': {'service-a': 3.0, 'service-b': 2.0},
            'timestamp': '2025-12-13T14:30:00Z',
            'time_window_minutes': 5
        }
        
        # Act
        result = self.widget.format_for_display(metrics)
        
        # Assert
        assert result['status'] == 'warning'
        assert result['status_message'] == "15 errors in last 5 minutes"


class TestTrendVisualizationWidget:
    """Unit tests for TrendVisualizationWidget."""
    
    def setup_method(self):
        """Set up test environment."""
        self.mock_collector = Mock()
        
        with patch('dashboard_components.get_metrics_collector', return_value=self.mock_collector):
            self.widget = TrendVisualizationWidget("test-trends")
    
    def test_get_trend_data_success(self):
        """Test successful retrieval of trend data."""
        # Arrange
        mock_aggregated_metrics = [
            AggregatedMetric(
                metric_type=MetricType.ERROR_COUNT,
                timestamp=datetime(2025, 12, 13, 14, 30),
                value=10.0,
                dimensions={'Service': 'service-a'},
                unit='Count'
            ),
            AggregatedMetric(
                metric_type=MetricType.ERROR_RATE,
                timestamp=datetime(2025, 12, 13, 14, 30),
                value=2.5,
                dimensions={'Service': 'service-a'},
                unit='Percent'
            )
        ]
        
        self.mock_collector.get_aggregated_metrics.return_value = mock_aggregated_metrics
        
        # Act
        result = self.widget.get_trend_data(1)
        
        # Assert
        assert len(result['error_count_trend']) == 1
        assert len(result['error_rate_trend']) == 1
        
        error_count_point = result['error_count_trend'][0]
        assert error_count_point['value'] == 10.0
        assert error_count_point['service'] == 'service-a'
        assert 'timestamp' in error_count_point
        
        error_rate_point = result['error_rate_trend'][0]
        assert error_rate_point['value'] == 2.5
        assert error_rate_point['service'] == 'service-a'
        
        # Verify collector was called with correct parameters
        self.mock_collector.get_aggregated_metrics.assert_called_once_with(
            metric_types=[MetricType.ERROR_COUNT, MetricType.ERROR_RATE],
            time_window_minutes=60,
            group_by_service=True
        )
    
    def test_get_trend_data_error_handling(self):
        """Test error handling in get_trend_data."""
        # Arrange
        self.mock_collector.get_aggregated_metrics.side_effect = Exception("Query failed")
        
        # Act
        result = self.widget.get_trend_data(1)
        
        # Assert
        assert result['error_count_trend'] == []
        assert result['error_rate_trend'] == []
        assert result['service_trends'] == {}
        assert 'error' in result
        assert result['error'] == "Query failed"
    
    def test_format_for_chart(self):
        """Test formatting trend data for chart display."""
        # Arrange
        trend_data = {
            'error_count_trend': [
                {'timestamp': '2025-12-13T14:30:00', 'value': 10.0, 'service': 'service-a'},
                {'timestamp': '2025-12-13T14:35:00', 'value': 8.0, 'service': 'service-a'}
            ],
            'error_rate_trend': [
                {'timestamp': '2025-12-13T14:30:00', 'value': 2.5, 'service': 'service-a'},
                {'timestamp': '2025-12-13T14:35:00', 'value': 2.0, 'service': 'service-a'}
            ]
        }
        
        # Act
        result = self.widget.format_for_chart(trend_data)
        
        # Assert
        assert result['widget_id'] == 'test-trends'
        assert result['title'] == 'Error Trends'
        assert result['type'] == 'trend_chart'
        
        charts = result['data']['charts']
        assert len(charts) == 2
        
        # Check error count chart
        error_count_chart = charts[0]
        assert error_count_chart['chart_id'] == 'error_count'
        assert error_count_chart['title'] == 'Error Count Over Time'
        assert error_count_chart['type'] == 'line'
        assert len(error_count_chart['data']) == 2
        
        # Check error rate chart
        error_rate_chart = charts[1]
        assert error_rate_chart['chart_id'] == 'error_rate'
        assert error_rate_chart['title'] == 'Error Rate Over Time'
        assert error_rate_chart['unit'] == '%'
        
        # Check metadata
        assert 'last_updated' in result['data']['metadata']
        assert result['data']['metadata']['data_points'] == 4


class TestSystemHealthWidget:
    """Unit tests for SystemHealthWidget."""
    
    def setup_method(self):
        """Set up test environment."""
        self.mock_collector = Mock()
        
        with patch('dashboard_components.get_metrics_collector', return_value=self.mock_collector):
            self.widget = SystemHealthWidget("test-health")
    
    def test_get_health_status_healthy(self):
        """Test health status calculation for healthy system."""
        # Arrange
        mock_real_time_metrics = {
            'total_errors': 0,
            'errors_by_service': {},
            'errors_by_severity': {},
            'timestamp': '2025-12-13T14:30:00Z'
        }
        
        self.mock_collector.get_real_time_metrics.return_value = mock_real_time_metrics
        
        # Act
        result = self.widget.get_health_status()
        
        # Assert
        assert result['overall_status'] == 'healthy'
        assert result['health_score'] == 100
        assert result['indicators']['total_errors'] == 0
        assert result['indicators']['critical_errors'] == 0
        assert result['indicators']['services_affected'] == 0
    
    def test_get_health_status_critical(self):
        """Test health status calculation for critical system."""
        # Arrange
        mock_real_time_metrics = {
            'total_errors': 30,
            'errors_by_service': {'service-a': 20, 'service-b': 10},
            'errors_by_severity': {'critical': 5, 'high': 15, 'medium': 10},
            'timestamp': '2025-12-13T14:30:00Z'
        }
        
        self.mock_collector.get_real_time_metrics.return_value = mock_real_time_metrics
        
        # Act
        result = self.widget.get_health_status()
        
        # Assert
        assert result['overall_status'] == 'critical'
        assert result['health_score'] == 0
        assert result['indicators']['total_errors'] == 30
        assert result['indicators']['critical_errors'] == 5
        assert result['indicators']['services_affected'] == 2
    
    def test_get_health_status_degraded(self):
        """Test health status calculation for degraded system."""
        # Arrange
        mock_real_time_metrics = {
            'total_errors': 15,
            'errors_by_service': {'service-a': 10, 'service-b': 5},
            'errors_by_severity': {'high': 10, 'medium': 5},
            'timestamp': '2025-12-13T14:30:00Z'
        }
        
        self.mock_collector.get_real_time_metrics.return_value = mock_real_time_metrics
        
        # Act
        result = self.widget.get_health_status()
        
        # Assert
        assert result['overall_status'] == 'degraded'
        assert result['health_score'] == 25
        assert result['indicators']['high_errors'] == 10
    
    def test_format_for_display_healthy(self):
        """Test formatting health data for healthy status."""
        # Arrange
        health_data = {
            'overall_status': 'healthy',
            'health_score': 100,
            'indicators': {
                'total_errors': 0,
                'critical_errors': 0,
                'high_errors': 0,
                'services_affected': 0
            },
            'timestamp': '2025-12-13T14:30:00Z'
        }
        
        # Act
        result = self.widget.format_for_display(health_data)
        
        # Assert
        assert result['widget_id'] == 'test-health'
        assert result['title'] == 'System Health'
        assert result['type'] == 'health_status'
        
        status = result['data']['status']
        assert status['level'] == 'healthy'
        assert status['score'] == 100
        assert status['color'] == 'green'
        assert status['message'] == 'All systems operational'
    
    def test_format_for_display_critical(self):
        """Test formatting health data for critical status."""
        # Arrange
        health_data = {
            'overall_status': 'critical',
            'health_score': 0,
            'indicators': {
                'total_errors': 30,
                'critical_errors': 5,
                'high_errors': 15,
                'services_affected': 2
            },
            'timestamp': '2025-12-13T14:30:00Z'
        }
        
        # Act
        result = self.widget.format_for_display(health_data)
        
        # Assert
        status = result['data']['status']
        assert status['level'] == 'critical'
        assert status['score'] == 0
        assert status['color'] == 'red'
        assert status['message'] == 'Critical errors - immediate attention required'


class TestDashboardManager:
    """Unit tests for DashboardManager."""
    
    def setup_method(self):
        """Set up test environment."""
        # Mock all widget classes
        self.mock_error_widget = Mock()
        self.mock_trend_widget = Mock()
        self.mock_health_widget = Mock()
        
        with patch('dashboard_components.ErrorMetricsWidget', return_value=self.mock_error_widget), \
             patch('dashboard_components.TrendVisualizationWidget', return_value=self.mock_trend_widget), \
             patch('dashboard_components.SystemHealthWidget', return_value=self.mock_health_widget):
            self.manager = DashboardManager()
    
    def test_get_dashboard_data_all_widgets(self):
        """Test getting complete dashboard data for all widgets."""
        # Arrange
        self.mock_error_widget.get_current_metrics.return_value = {'total_errors': 10}
        self.mock_error_widget.format_for_display.return_value = {'widget_id': 'error_metrics', 'data': 'mock_error_data'}
        
        self.mock_trend_widget.get_trend_data.return_value = {'error_count_trend': []}
        self.mock_trend_widget.format_for_chart.return_value = {'widget_id': 'error_trends', 'data': 'mock_trend_data'}
        
        self.mock_health_widget.get_health_status.return_value = {'overall_status': 'healthy'}
        self.mock_health_widget.format_for_display.return_value = {'widget_id': 'system_health', 'data': 'mock_health_data'}
        
        # Act
        result = self.manager.get_dashboard_data()
        
        # Assert
        assert result['dashboard_id'] == 'error_monitoring'
        assert result['title'] == 'Error Monitoring Dashboard'
        assert 'last_updated' in result
        assert len(result['widgets']) == 3
        
        assert 'error_metrics' in result['widgets']
        assert 'error_trends' in result['widgets']
        assert 'system_health' in result['widgets']
        
        # Verify widget methods were called
        self.mock_error_widget.get_current_metrics.assert_called_once()
        self.mock_error_widget.format_for_display.assert_called_once()
        self.mock_trend_widget.get_trend_data.assert_called_once()
        self.mock_trend_widget.format_for_chart.assert_called_once()
        self.mock_health_widget.get_health_status.assert_called_once()
        self.mock_health_widget.format_for_display.assert_called_once()
    
    def test_get_dashboard_data_specific_widgets(self):
        """Test getting dashboard data for specific widgets only."""
        # Arrange
        self.mock_error_widget.get_current_metrics.return_value = {'total_errors': 10}
        self.mock_error_widget.format_for_display.return_value = {'widget_id': 'error_metrics', 'data': 'mock_error_data'}
        
        # Act
        result = self.manager.get_dashboard_data(['error_metrics'])
        
        # Assert
        assert len(result['widgets']) == 1
        assert 'error_metrics' in result['widgets']
        assert 'error_trends' not in result['widgets']
        assert 'system_health' not in result['widgets']
        
        # Verify only error widget methods were called
        self.mock_error_widget.get_current_metrics.assert_called_once()
        self.mock_trend_widget.get_trend_data.assert_not_called()
        self.mock_health_widget.get_health_status.assert_not_called()
    
    def test_get_dashboard_data_widget_error_handling(self):
        """Test error handling when widget fails."""
        # Arrange
        self.mock_error_widget.get_current_metrics.side_effect = Exception("Widget failed")
        
        # Act
        result = self.manager.get_dashboard_data(['error_metrics'])
        
        # Assert
        assert 'error_metrics' in result['widgets']
        error_widget_data = result['widgets']['error_metrics']
        assert error_widget_data['widget_id'] == 'error_metrics'
        assert error_widget_data['status'] == 'error'
        assert error_widget_data['error'] == "Widget failed"
    
    def test_get_widget_data(self):
        """Test getting data for a specific widget."""
        # Arrange
        self.mock_error_widget.get_current_metrics.return_value = {'total_errors': 10}
        self.mock_error_widget.format_for_display.return_value = {'widget_id': 'error_metrics', 'data': 'mock_error_data'}
        
        # Act
        result = self.manager.get_widget_data('error_metrics')
        
        # Assert
        assert result['widget_id'] == 'error_metrics'
        assert result['data'] == 'mock_error_data'
        
        # Verify only the requested widget was processed
        self.mock_error_widget.get_current_metrics.assert_called_once()
        self.mock_trend_widget.get_trend_data.assert_not_called()
        self.mock_health_widget.get_health_status.assert_not_called()
    
    def test_get_widget_data_nonexistent_widget(self):
        """Test getting data for a non-existent widget."""
        # Act
        result = self.manager.get_widget_data('nonexistent_widget')
        
        # Assert
        assert result == {}


if __name__ == "__main__":
    pytest.main([__file__, "-v"])