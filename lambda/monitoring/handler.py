"""
Monitoring Dashboard Lambda Handler

Main entry point for the real-time monitoring dashboard system.
Provides API endpoints for dashboard data, metrics, and real-time updates.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-3.1, 3.2, 3.3 → DESIGN-MonitoringDashboard → TASK-3",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
import os
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime

# Import shared modules
import sys
sys.path.append('/opt/python')
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dashboard_components import get_dashboard_manager
from metrics_collector import get_metrics_collector

# Import shared modules with proper path handling
try:
    from shared.error_handler import handle_lambda_error
    from shared.cors_helper import add_cors_headers
except ImportError:
    # Fallback for testing environment - use standard logging
    def handle_lambda_error(func):
        return func
    def add_cors_headers(response):
        return response

logger = logging.getLogger(__name__)


@handle_lambda_error
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for monitoring dashboard operations.
    
    Supported operations:
    - GET /dashboard: Get complete dashboard data
    - GET /dashboard/widgets/{widget_id}: Get specific widget data
    - GET /metrics/real-time: Get real-time metrics
    - GET /metrics/trends: Get trend data
    - GET /health: Health check
    
    Args:
        event: Lambda event object
        context: Lambda context object
    
    Returns:
        HTTP response with CORS headers
    """
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    logger.info(f"Processing {http_method} {path}")
    
    # Route to appropriate handler
    if http_method == 'GET' and path.endswith('/dashboard'):
        response = handle_get_dashboard(event)
    elif http_method == 'GET' and '/dashboard/widgets/' in path:
        response = handle_get_widget(event)
    elif http_method == 'GET' and path.endswith('/metrics/real-time'):
        response = handle_get_real_time_metrics(event)
    elif http_method == 'GET' and path.endswith('/metrics/trends'):
        response = handle_get_trends(event)
    elif http_method == 'GET' and path.endswith('/health'):
        response = handle_health_check(event)
    else:
        response = {
            'statusCode': 404,
            'body': json.dumps({
                'error': 'NotFound',
                'message': f'Endpoint {http_method} {path} not found'
            })
        }
    
    # Add CORS headers
    return add_cors_headers(response)


def handle_get_dashboard(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle request for complete dashboard data.
    
    Query parameters:
    - widgets: Comma-separated list of widget IDs (optional)
    """
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        widgets_param = query_params.get('widgets')
        
        widget_ids = None
        if widgets_param:
            widget_ids = [w.strip() for w in widgets_param.split(',')]
        
        # Get dashboard manager and data
        dashboard_manager = get_dashboard_manager()
        dashboard_data = dashboard_manager.get_dashboard_data(widget_ids)
        
        return {
            'statusCode': 200,
            'body': json.dumps(dashboard_data)
        }
        
    except Exception as e:
        logger.error(f"Error in get_dashboard: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve dashboard data'
            })
        }


def handle_get_widget(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle request for specific widget data.
    
    Path parameters:
    - widget_id: ID of the widget to retrieve
    """
    try:
        # Extract widget ID from path
        path = event.get('path', '')
        path_parts = path.split('/')
        
        if len(path_parts) < 2 or 'widgets' not in path_parts:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Invalid path format. Expected: /dashboard/widgets/{widget_id}'
                })
            }
        
        widget_id = path_parts[-1]  # Last part of the path
        
        # Get dashboard manager and widget data
        dashboard_manager = get_dashboard_manager()
        widget_data = dashboard_manager.get_widget_data(widget_id)
        
        if not widget_data:
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'NotFound',
                    'message': f'Widget {widget_id} not found'
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(widget_data)
        }
        
    except Exception as e:
        logger.error(f"Error in get_widget: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve widget data'
            })
        }


def handle_get_real_time_metrics(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle request for real-time metrics.
    
    Query parameters:
    - service: Filter by service name (optional)
    """
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        service_filter = query_params.get('service')
        
        # Get metrics collector
        metrics_collector = get_metrics_collector()
        real_time_metrics = metrics_collector.get_real_time_metrics()
        
        # Apply service filter if specified
        if service_filter:
            filtered_metrics = {
                'total_errors': real_time_metrics.get('errors_by_service', {}).get(service_filter, 0),
                'errors_by_service': {service_filter: real_time_metrics.get('errors_by_service', {}).get(service_filter, 0)},
                'errors_by_severity': {},  # Would need more complex filtering logic
                'timestamp': real_time_metrics.get('timestamp'),
                'time_window_minutes': real_time_metrics.get('time_window_minutes'),
                'service_filter': service_filter
            }
            
            # Calculate error rate for the specific service
            error_rate = metrics_collector.get_error_rate(service_filter, 5)
            filtered_metrics['error_rate'] = error_rate
            
            return {
                'statusCode': 200,
                'body': json.dumps(filtered_metrics)
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(real_time_metrics)
        }
        
    except Exception as e:
        logger.error(f"Error in get_real_time_metrics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve real-time metrics'
            })
        }


def handle_get_trends(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle request for trend data.
    
    Query parameters:
    - hours: Time window in hours (default: 1)
    - service: Filter by service name (optional)
    """
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        hours = int(query_params.get('hours', 1))
        service_filter = query_params.get('service')
        
        # Validate hours parameter
        if hours < 1 or hours > 24:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Hours parameter must be between 1 and 24'
                })
            }
        
        # Get dashboard manager and trend data
        dashboard_manager = get_dashboard_manager()
        trend_widget = dashboard_manager.widgets['error_trends']
        trend_data = trend_widget.get_trend_data(hours)
        
        # Apply service filter if specified
        if service_filter:
            filtered_trend_data = {
                'error_count_trend': [
                    point for point in trend_data.get('error_count_trend', [])
                    if point.get('service') == service_filter
                ],
                'error_rate_trend': [
                    point for point in trend_data.get('error_rate_trend', [])
                    if point.get('service') == service_filter
                ],
                'service_trends': {
                    service_filter: trend_data.get('service_trends', {}).get(service_filter, {})
                },
                'service_filter': service_filter,
                'time_window_hours': hours
            }
            
            return {
                'statusCode': 200,
                'body': json.dumps(filtered_trend_data)
            }
        
        # Add metadata
        trend_data['time_window_hours'] = hours
        trend_data['timestamp'] = datetime.utcnow().isoformat()
        
        return {
            'statusCode': 200,
            'body': json.dumps(trend_data)
        }
        
    except ValueError:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'ValidationError',
                'message': 'Invalid hours parameter. Must be a number.'
            })
        }
    except Exception as e:
        logger.error(f"Error in get_trends: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve trend data'
            })
        }


def handle_health_check(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle health check request.
    """
    try:
        # Get dashboard manager and health status
        dashboard_manager = get_dashboard_manager()
        health_widget = dashboard_manager.widgets['system_health']
        health_status = health_widget.get_health_status()
        
        # Get metrics collector status
        metrics_collector = get_metrics_collector()
        real_time_metrics = metrics_collector.get_real_time_metrics()
        
        # Determine overall service health
        service_healthy = 'error' not in health_status and 'error' not in real_time_metrics
        
        return {
            'statusCode': 200 if service_healthy else 503,
            'body': json.dumps({
                'status': 'healthy' if service_healthy else 'unhealthy',
                'service': 'monitoring-dashboard',
                'version': '1.0.0',
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'components': {
                    'dashboard_manager': 'healthy' if 'error' not in health_status else 'unhealthy',
                    'metrics_collector': 'healthy' if 'error' not in real_time_metrics else 'unhealthy'
                },
                'system_health': health_status,
                'current_metrics': {
                    'total_errors': real_time_metrics.get('total_errors', 0),
                    'services_monitored': len(real_time_metrics.get('errors_by_service', {}))
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in health_check: {str(e)}")
        return {
            'statusCode': 503,
            'body': json.dumps({
                'status': 'unhealthy',
                'service': 'monitoring-dashboard',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }