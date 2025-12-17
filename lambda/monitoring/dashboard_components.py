"""
Real-time Monitoring Dashboard Components

Provides dashboard components for displaying error metrics, trends, and system health.
Implements real-time updates and visualization components for the monitoring dashboard.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-3.2, 3.3 → DESIGN-MonitoringDashboard → TASK-3.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from enum import Enum
import logging

# Import shared modules
import sys
import os

# Import metrics collector for MetricType
from metrics_collector import MetricType
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

try:
    from shared.structured_logger import get_logger
    from metrics_collector import get_metrics_collector, MetricType
except ImportError:
    # Fallback for testing
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    def get_logger(name):
        return logger

logger = get_logger(__name__)


class DashboardUpdateFrequency(Enum):
    """Dashboard update frequencies."""
    REAL_TIME = "real_time"  # Every 5 seconds
    FAST = "fast"           # Every 30 seconds
    NORMAL = "normal"       # Every 2 minutes
    SLOW = "slow"          # Every 5 minutes


@dataclass
class MetricDisplayConfig:
    """Configuration for metric display."""
    title: str
    metric_type: MetricType
    unit: str
    format_string: str = "{:.2f}"
    threshold_warning: Optional[float] = None
    threshold_critical: Optional[float] = None
    show_trend: bool = True


@dataclass
class DashboardWidget:
    """Represents a dashboard widget."""
    widget_id: str
    title: str
    widget_type: str
    data: Dict[str, Any]
    last_updated: datetime
    update_frequency: DashboardUpdateFrequency
    config: Optional[Dict[str, Any]] = None


class ErrorMetricsWidget:
    """Widget for displaying error metrics and trends."""
    
    def __init__(self, widget_id: str = "error-metrics"):
        """
        Initialize error metrics widget.
        
        Args:
            widget_id: Unique identifier for the widget
        """
        self.widget_id = widget_id
        self.metrics_collector = get_metrics_collector()
        
    def get_current_metrics(self) -> Dict[str, Any]:
        """
        Get current error metrics for display.
        
        Returns:
            Dictionary containing current error metrics
        """
        try:
            # Get real-time metrics from collector
            real_time_metrics = self.metrics_collector.get_real_time_metrics()
            
            # Calculate additional derived metrics
            total_errors = real_time_metrics.get('total_errors', 0)
            errors_by_service = real_time_metrics.get('errors_by_service', {})
            errors_by_severity = real_time_metrics.get('errors_by_severity', {})
            
            # Calculate error rate trends (simplified)
            error_rates = {}
            for service in errors_by_service.keys():
                error_rates[service] = self.metrics_collector.get_error_rate(service, 5)
            
            return {
                'total_errors': total_errors,
                'errors_by_service': errors_by_service,
                'errors_by_severity': errors_by_severity,
                'error_rates': error_rates,
                'timestamp': real_time_metrics.get('timestamp'),
                'time_window_minutes': real_time_metrics.get('time_window_minutes', 5)
            }
            
        except Exception as e:
            logger.error(f"Failed to get current metrics: {str(e)}")
            return {
                'total_errors': 0,
                'errors_by_service': {},
                'errors_by_severity': {},
                'error_rates': {},
                'timestamp': datetime.utcnow().isoformat(),
                'time_window_minutes': 5,
                'error': str(e)
            }
    
    def format_for_display(self, metrics: Dict[str, Any]) -> Dict[str, Any]:
        """
        Format metrics for dashboard display.
        
        Args:
            metrics: Raw metrics data
            
        Returns:
            Formatted metrics for display
        """
        formatted = {
            'widget_id': self.widget_id,
            'title': 'Error Metrics',
            'type': 'error_metrics',
            'data': {
                'summary': {
                    'total_errors': metrics.get('total_errors', 0),
                    'critical_errors': metrics.get('errors_by_severity', {}).get('critical', 0),
                    'high_errors': metrics.get('errors_by_severity', {}).get('high', 0),
                    'services_affected': len(metrics.get('errors_by_service', {}))
                },
                'breakdown': {
                    'by_service': metrics.get('errors_by_service', {}),
                    'by_severity': metrics.get('errors_by_severity', {}),
                    'error_rates': metrics.get('error_rates', {})
                },
                'metadata': {
                    'last_updated': metrics.get('timestamp'),
                    'time_window': f"{metrics.get('time_window_minutes', 5)} minutes"
                }
            }
        }
        
        # Add status indicators
        total_errors = metrics.get('total_errors', 0)
        critical_errors = metrics.get('errors_by_severity', {}).get('critical', 0)
        
        if critical_errors > 0:
            formatted['status'] = 'critical'
            formatted['status_message'] = f"{critical_errors} critical errors detected"
        elif total_errors > 10:
            formatted['status'] = 'warning'
            formatted['status_message'] = f"{total_errors} errors in last 5 minutes"
        else:
            formatted['status'] = 'healthy'
            formatted['status_message'] = "System operating normally"
        
        return formatted


class TrendVisualizationWidget:
    """Widget for displaying error trends and visualizations."""
    
    def __init__(self, widget_id: str = "error-trends"):
        """
        Initialize trend visualization widget.
        
        Args:
            widget_id: Unique identifier for the widget
        """
        self.widget_id = widget_id
        self.metrics_collector = get_metrics_collector()
        
    def get_trend_data(self, time_window_hours: int = 1) -> Dict[str, Any]:
        """
        Get trend data for visualization.
        
        Args:
            time_window_hours: Time window in hours for trend analysis
            
        Returns:
            Dictionary containing trend data
        """
        try:
            # Get aggregated metrics for trend analysis
            metric_types = [MetricType.ERROR_COUNT, MetricType.ERROR_RATE]
            aggregated_metrics = self.metrics_collector.get_aggregated_metrics(
                metric_types=metric_types,
                time_window_minutes=time_window_hours * 60,
                group_by_service=True
            )
            
            # Process metrics into trend format
            trends = {
                'error_count_trend': [],
                'error_rate_trend': [],
                'service_trends': {}
            }
            
            for metric in aggregated_metrics:
                if metric.metric_type == MetricType.ERROR_COUNT:
                    trends['error_count_trend'].append({
                        'timestamp': metric.timestamp.isoformat(),
                        'value': metric.value,
                        'service': metric.dimensions.get('Service', 'unknown')
                    })
                elif metric.metric_type == MetricType.ERROR_RATE:
                    trends['error_rate_trend'].append({
                        'timestamp': metric.timestamp.isoformat(),
                        'value': metric.value,
                        'service': metric.dimensions.get('Service', 'unknown')
                    })
            
            return trends
            
        except Exception as e:
            logger.error(f"Failed to get trend data: {str(e)}")
            return {
                'error_count_trend': [],
                'error_rate_trend': [],
                'service_trends': {},
                'error': str(e)
            }
    
    def format_for_chart(self, trend_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Format trend data for chart visualization.
        
        Args:
            trend_data: Raw trend data
            
        Returns:
            Formatted data for chart display
        """
        return {
            'widget_id': self.widget_id,
            'title': 'Error Trends',
            'type': 'trend_chart',
            'data': {
                'charts': [
                    {
                        'chart_id': 'error_count',
                        'title': 'Error Count Over Time',
                        'type': 'line',
                        'data': trend_data.get('error_count_trend', []),
                        'x_axis': 'timestamp',
                        'y_axis': 'value',
                        'group_by': 'service'
                    },
                    {
                        'chart_id': 'error_rate',
                        'title': 'Error Rate Over Time',
                        'type': 'line',
                        'data': trend_data.get('error_rate_trend', []),
                        'x_axis': 'timestamp',
                        'y_axis': 'value',
                        'group_by': 'service',
                        'unit': '%'
                    }
                ],
                'metadata': {
                    'last_updated': datetime.utcnow().isoformat(),
                    'data_points': len(trend_data.get('error_count_trend', [])) + len(trend_data.get('error_rate_trend', []))
                }
            }
        }


class SystemHealthWidget:
    """Widget for displaying overall system health status."""
    
    def __init__(self, widget_id: str = "system-health"):
        """
        Initialize system health widget.
        
        Args:
            widget_id: Unique identifier for the widget
        """
        self.widget_id = widget_id
        self.metrics_collector = get_metrics_collector()
        
    def get_health_status(self) -> Dict[str, Any]:
        """
        Get overall system health status.
        
        Returns:
            Dictionary containing system health information
        """
        try:
            # Get current metrics
            real_time_metrics = self.metrics_collector.get_real_time_metrics()
            
            # Calculate health indicators
            total_errors = real_time_metrics.get('total_errors', 0)
            critical_errors = real_time_metrics.get('errors_by_severity', {}).get('critical', 0)
            high_errors = real_time_metrics.get('errors_by_severity', {}).get('high', 0)
            services_with_errors = len(real_time_metrics.get('errors_by_service', {}))
            
            # Determine overall health status
            if critical_errors > 0:
                health_status = 'critical'
                health_score = 0
            elif high_errors > 5:
                health_status = 'degraded'
                health_score = 25
            elif total_errors > 20:
                health_status = 'warning'
                health_score = 50
            elif total_errors > 0:
                health_status = 'minor_issues'
                health_score = 75
            else:
                health_status = 'healthy'
                health_score = 100
            
            return {
                'overall_status': health_status,
                'health_score': health_score,
                'indicators': {
                    'total_errors': total_errors,
                    'critical_errors': critical_errors,
                    'high_errors': high_errors,
                    'services_affected': services_with_errors
                },
                'timestamp': real_time_metrics.get('timestamp')
            }
            
        except Exception as e:
            logger.error(f"Failed to get health status: {str(e)}")
            return {
                'overall_status': 'unknown',
                'health_score': 0,
                'indicators': {
                    'total_errors': 0,
                    'critical_errors': 0,
                    'high_errors': 0,
                    'services_affected': 0
                },
                'timestamp': datetime.utcnow().isoformat(),
                'error': str(e)
            }
    
    def format_for_display(self, health_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Format health data for dashboard display.
        
        Args:
            health_data: Raw health data
            
        Returns:
            Formatted health data for display
        """
        status = health_data.get('overall_status', 'unknown')
        score = health_data.get('health_score', 0)
        
        # Status colors and messages
        status_config = {
            'healthy': {'color': 'green', 'message': 'All systems operational'},
            'minor_issues': {'color': 'yellow', 'message': 'Minor issues detected'},
            'warning': {'color': 'orange', 'message': 'Warning: Multiple errors detected'},
            'degraded': {'color': 'red', 'message': 'System performance degraded'},
            'critical': {'color': 'red', 'message': 'Critical errors - immediate attention required'},
            'unknown': {'color': 'gray', 'message': 'Health status unknown'}
        }
        
        config = status_config.get(status, status_config['unknown'])
        
        return {
            'widget_id': self.widget_id,
            'title': 'System Health',
            'type': 'health_status',
            'data': {
                'status': {
                    'level': status,
                    'score': score,
                    'color': config['color'],
                    'message': config['message']
                },
                'indicators': health_data.get('indicators', {}),
                'metadata': {
                    'last_updated': health_data.get('timestamp'),
                    'update_frequency': 'real_time'
                }
            }
        }


class DashboardManager:
    """Manages dashboard widgets and real-time updates."""
    
    def __init__(self):
        """Initialize dashboard manager."""
        self.widgets = {
            'error_metrics': ErrorMetricsWidget(),
            'error_trends': TrendVisualizationWidget(),
            'system_health': SystemHealthWidget()
        }
        
    def get_dashboard_data(self, widget_ids: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Get complete dashboard data.
        
        Args:
            widget_ids: List of widget IDs to include (None for all)
            
        Returns:
            Complete dashboard data
        """
        if widget_ids is None:
            widget_ids = list(self.widgets.keys())
        
        dashboard_data = {
            'dashboard_id': 'error_monitoring',
            'title': 'Error Monitoring Dashboard',
            'last_updated': datetime.utcnow().isoformat(),
            'widgets': {}
        }
        
        for widget_id in widget_ids:
            if widget_id in self.widgets:
                try:
                    widget = self.widgets[widget_id]
                    
                    if widget_id == 'error_metrics':
                        metrics = widget.get_current_metrics()
                        dashboard_data['widgets'][widget_id] = widget.format_for_display(metrics)
                    elif widget_id == 'error_trends':
                        trends = widget.get_trend_data()
                        dashboard_data['widgets'][widget_id] = widget.format_for_chart(trends)
                    elif widget_id == 'system_health':
                        health = widget.get_health_status()
                        dashboard_data['widgets'][widget_id] = widget.format_for_display(health)
                        
                except Exception as e:
                    logger.error(f"Failed to get data for widget {widget_id}: {str(e)}")
                    dashboard_data['widgets'][widget_id] = {
                        'widget_id': widget_id,
                        'error': str(e),
                        'status': 'error'
                    }
        
        return dashboard_data
    
    def get_widget_data(self, widget_id: str) -> Dict[str, Any]:
        """
        Get data for a specific widget.
        
        Args:
            widget_id: ID of the widget to get data for
            
        Returns:
            Widget data
        """
        dashboard_data = self.get_dashboard_data([widget_id])
        return dashboard_data.get('widgets', {}).get(widget_id, {})


def get_dashboard_manager() -> DashboardManager:
    """Get singleton dashboard manager instance."""
    if not hasattr(get_dashboard_manager, '_instance'):
        get_dashboard_manager._instance = DashboardManager()
    return get_dashboard_manager._instance