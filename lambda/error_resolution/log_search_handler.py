"""
Log Search and Analysis API Handler

Provides REST API endpoints for searching, analyzing, and exporting logs
and audit trails from the comprehensive logging system.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-15T15:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.3 → DESIGN-LogSearch → TASK-5",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
import os
import logging
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional
from urllib.parse import parse_qs

# Import shared modules
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

try:
    from .logging_system import get_comprehensive_logger, LogLevel, LogCategory
    from .audit_system import get_audit_trail, AuditEventType, AuditSeverity, ComplianceReporter
except ImportError:
    # Fallback for direct imports
    from logging_system import get_comprehensive_logger, LogLevel, LogCategory
    from audit_system import get_audit_trail, AuditEventType, AuditSeverity, ComplianceReporter

# Import shared modules with proper path handling
try:
    from shared.error_handler import handle_lambda_error
    from shared.cors_helper import add_cors_headers
except ImportError:
    # Fallback for testing environment
    def handle_lambda_error(func):
        return func
    def add_cors_headers(response):
        return response

logger = logging.getLogger(__name__)


@handle_lambda_error
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for log search and analysis operations.
    
    Supported operations:
    - GET /logs/search: Search logs with query and filters
    - GET /logs/statistics: Get logging statistics and insights
    - GET /logs/export: Export logs in various formats
    - GET /audit/search: Search audit events
    - GET /audit/statistics: Get audit trail statistics
    - GET /audit/export: Export audit trail
    - GET /audit/compliance: Generate compliance reports
    - GET /logs/analyze/errors: Analyze error patterns
    - GET /logs/analyze/performance: Analyze performance trends
    - GET /logs/analyze/anomalies: Detect anomalies
    
    Args:
        event: Lambda event object
        context: Lambda context object
    
    Returns:
        HTTP response with CORS headers
    """
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    query_params = event.get('queryStringParameters') or {}
    
    logger.info(f"Processing {http_method} {path}")
    
    # Route to appropriate handler
    if http_method == 'GET':
        if path.endswith('/logs/search'):
            response = handle_search_logs(query_params)
        elif path.endswith('/logs/statistics'):
            response = handle_get_log_statistics()
        elif path.endswith('/logs/export'):
            response = handle_export_logs(query_params)
        elif path.endswith('/audit/search'):
            response = handle_search_audit(query_params)
        elif path.endswith('/audit/statistics'):
            response = handle_get_audit_statistics()
        elif path.endswith('/audit/export'):
            response = handle_export_audit(query_params)
        elif path.endswith('/audit/compliance'):
            response = handle_generate_compliance_report(query_params)
        elif path.endswith('/logs/analyze/errors'):
            response = handle_analyze_errors(query_params)
        elif path.endswith('/logs/analyze/performance'):
            response = handle_analyze_performance(query_params)
        elif path.endswith('/logs/analyze/anomalies'):
            response = handle_detect_anomalies(query_params)
        elif path.endswith('/health'):
            response = handle_health_check()
        else:
            response = {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'NotFound',
                    'message': f'Endpoint {http_method} {path} not found'
                })
            }
    else:
        response = {
            'statusCode': 405,
            'body': json.dumps({
                'error': 'MethodNotAllowed',
                'message': f'Method {http_method} not allowed'
            })
        }
    
    # Add CORS headers
    return add_cors_headers(response)


def handle_search_logs(query_params: Dict[str, str]) -> Dict[str, Any]:
    """
    Handle log search request.
    
    Query parameters:
    - q: Search query string
    - level: Log level filter (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    - category: Category filter (system, security, performance, business, audit, error, resolution, monitoring)
    - start_time: Start time filter (ISO format)
    - end_time: End time filter (ISO format)
    - limit: Maximum number of results (default: 100)
    """
    try:
        logger_instance = get_comprehensive_logger()
        
        # Parse query parameters
        query = query_params.get('q', '')
        level_str = query_params.get('level')
        category_str = query_params.get('category')
        start_time_str = query_params.get('start_time')
        end_time_str = query_params.get('end_time')
        limit_str = query_params.get('limit', '100')
        
        # Parse filters
        filters = {}
        
        if level_str:
            try:
                filters['level'] = LogLevel(level_str.upper())
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid log level: {level_str}'
                    })
                }
        
        if category_str:
            try:
                filters['category'] = LogCategory(category_str.lower())
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid category: {category_str}'
                    })
                }
        
        if start_time_str:
            try:
                filters['start_time'] = datetime.fromisoformat(start_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid start_time format: {start_time_str}'
                    })
                }
        
        if end_time_str:
            try:
                filters['end_time'] = datetime.fromisoformat(end_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid end_time format: {end_time_str}'
                    })
                }
        
        try:
            filters['limit'] = int(limit_str)
            if filters['limit'] > 1000:
                filters['limit'] = 1000  # Cap at 1000 results
        except ValueError:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'InvalidParameter',
                    'message': f'Invalid limit: {limit_str}'
                })
            }
        
        # Search logs
        log_entries = logger_instance.search_logs(query, **filters)
        
        # Convert to response format
        results = [entry.to_dict() for entry in log_entries]
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'query': query,
                'filters': {k: str(v) for k, v in filters.items()},
                'total_results': len(results),
                'results': results,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in search_logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to search logs'
            })
        }


def handle_get_log_statistics() -> Dict[str, Any]:
    """Handle request for logging statistics."""
    try:
        logger_instance = get_comprehensive_logger()
        stats = logger_instance.get_log_statistics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'statistics': stats,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in get_log_statistics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve log statistics'
            })
        }


def handle_export_logs(query_params: Dict[str, str]) -> Dict[str, Any]:
    """
    Handle log export request.
    
    Query parameters:
    - format: Export format (json, csv)
    - level: Log level filter
    - category: Category filter
    - start_time: Start time filter
    - end_time: End time filter
    """
    try:
        logger_instance = get_comprehensive_logger()
        
        # Parse parameters
        format_type = query_params.get('format', 'json').lower()
        level_str = query_params.get('level')
        category_str = query_params.get('category')
        start_time_str = query_params.get('start_time')
        end_time_str = query_params.get('end_time')
        
        # Parse filters
        level = None
        if level_str:
            try:
                level = LogLevel(level_str.upper())
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid log level: {level_str}'
                    })
                }
        
        category = None
        if category_str:
            try:
                category = LogCategory(category_str.lower())
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid category: {category_str}'
                    })
                }
        
        start_time = None
        if start_time_str:
            try:
                start_time = datetime.fromisoformat(start_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid start_time format: {start_time_str}'
                    })
                }
        
        end_time = None
        if end_time_str:
            try:
                end_time = datetime.fromisoformat(end_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid end_time format: {end_time_str}'
                    })
                }
        
        # Export logs
        exported_data = logger_instance.export_logs(
            format_type=format_type,
            start_time=start_time,
            end_time=end_time,
            level=level,
            category=category
        )
        
        # Set appropriate content type
        content_type = 'application/json' if format_type == 'json' else 'text/csv'
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': content_type,
                'Content-Disposition': f'attachment; filename="logs.{format_type}"'
            },
            'body': exported_data
        }
        
    except Exception as e:
        logger.error(f"Error in export_logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to export logs'
            })
        }


def handle_search_audit(query_params: Dict[str, str]) -> Dict[str, Any]:
    """
    Handle audit event search request.
    
    Query parameters:
    - event_type: Event type filter
    - correlation_id: Correlation ID filter
    - user_id: User ID filter
    - start_time: Start time filter
    - end_time: End time filter
    - limit: Maximum number of results
    """
    try:
        audit_trail = get_audit_trail()
        
        # Parse query parameters
        event_type_str = query_params.get('event_type')
        correlation_id = query_params.get('correlation_id')
        user_id = query_params.get('user_id')
        start_time_str = query_params.get('start_time')
        end_time_str = query_params.get('end_time')
        limit_str = query_params.get('limit', '100')
        
        # Parse filters
        event_type = None
        if event_type_str:
            try:
                event_type = AuditEventType(event_type_str.lower())
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid event_type: {event_type_str}'
                    })
                }
        
        start_time = None
        if start_time_str:
            try:
                start_time = datetime.fromisoformat(start_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid start_time format: {start_time_str}'
                    })
                }
        
        end_time = None
        if end_time_str:
            try:
                end_time = datetime.fromisoformat(end_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid end_time format: {end_time_str}'
                    })
                }
        
        try:
            limit = int(limit_str)
            if limit > 1000:
                limit = 1000  # Cap at 1000 results
        except ValueError:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'InvalidParameter',
                    'message': f'Invalid limit: {limit_str}'
                })
            }
        
        # Search audit events
        audit_events = audit_trail.get_audit_events(
            event_type=event_type,
            correlation_id=correlation_id,
            user_id=user_id,
            start_time=start_time,
            end_time=end_time,
            limit=limit
        )
        
        # Convert to response format
        results = [event.to_dict() for event in audit_events]
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'filters': {
                    'event_type': event_type_str,
                    'correlation_id': correlation_id,
                    'user_id': user_id,
                    'start_time': start_time_str,
                    'end_time': end_time_str,
                    'limit': limit
                },
                'total_results': len(results),
                'results': results,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in search_audit: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to search audit events'
            })
        }


def handle_get_audit_statistics() -> Dict[str, Any]:
    """Handle request for audit trail statistics."""
    try:
        audit_trail = get_audit_trail()
        stats = audit_trail.get_audit_statistics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'statistics': stats,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in get_audit_statistics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve audit statistics'
            })
        }


def handle_export_audit(query_params: Dict[str, str]) -> Dict[str, Any]:
    """Handle audit trail export request."""
    try:
        audit_trail = get_audit_trail()
        
        # Parse parameters
        format_type = query_params.get('format', 'json').lower()
        start_time_str = query_params.get('start_time')
        end_time_str = query_params.get('end_time')
        
        # Parse time filters
        start_time = None
        if start_time_str:
            try:
                start_time = datetime.fromisoformat(start_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid start_time format: {start_time_str}'
                    })
                }
        
        end_time = None
        if end_time_str:
            try:
                end_time = datetime.fromisoformat(end_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid end_time format: {end_time_str}'
                    })
                }
        
        # Export audit trail
        exported_data = audit_trail.export_audit_trail(
            format_type=format_type,
            start_time=start_time,
            end_time=end_time
        )
        
        # Set appropriate content type
        content_type = 'application/json' if format_type == 'json' else 'text/csv'
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': content_type,
                'Content-Disposition': f'attachment; filename="audit_trail.{format_type}"'
            },
            'body': exported_data
        }
        
    except Exception as e:
        logger.error(f"Error in export_audit: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to export audit trail'
            })
        }


def handle_generate_compliance_report(query_params: Dict[str, str]) -> Dict[str, Any]:
    """Handle compliance report generation request."""
    try:
        audit_trail = get_audit_trail()
        compliance_reporter = ComplianceReporter(audit_trail)
        
        # Parse parameters
        report_type = query_params.get('type', 'summary')
        start_time_str = query_params.get('start_time')
        end_time_str = query_params.get('end_time')
        
        # Default to last 30 days if no time range specified
        if not start_time_str:
            start_time = datetime.now(timezone.utc) - timedelta(days=30)
        else:
            try:
                start_time = datetime.fromisoformat(start_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid start_time format: {start_time_str}'
                    })
                }
        
        if not end_time_str:
            end_time = datetime.now(timezone.utc)
        else:
            try:
                end_time = datetime.fromisoformat(end_time_str.replace('Z', '+00:00'))
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Invalid end_time format: {end_time_str}'
                    })
                }
        
        # Generate compliance report
        report = compliance_reporter.generate_compliance_report(
            start_time=start_time,
            end_time=end_time,
            report_type=report_type
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'report': report,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in generate_compliance_report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to generate compliance report'
            })
        }


def handle_analyze_errors(query_params: Dict[str, str]) -> Dict[str, Any]:
    """Handle error pattern analysis request."""
    try:
        logger_instance = get_comprehensive_logger()
        
        # Parse time window (default to 1 hour)
        hours = int(query_params.get('hours', '1'))
        time_window = timedelta(hours=hours)
        
        # Analyze error patterns
        analysis = logger_instance.log_analyzer.analyze_error_patterns(time_window)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'analysis': analysis,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in analyze_errors: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to analyze error patterns'
            })
        }


def handle_analyze_performance(query_params: Dict[str, str]) -> Dict[str, Any]:
    """Handle performance trend analysis request."""
    try:
        logger_instance = get_comprehensive_logger()
        
        # Parse time window (default to 1 hour)
        hours = int(query_params.get('hours', '1'))
        time_window = timedelta(hours=hours)
        
        # Analyze performance trends
        analysis = logger_instance.log_analyzer.analyze_performance_trends(time_window)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'analysis': analysis,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in analyze_performance: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to analyze performance trends'
            })
        }


def handle_detect_anomalies(query_params: Dict[str, str]) -> Dict[str, Any]:
    """Handle anomaly detection request."""
    try:
        logger_instance = get_comprehensive_logger()
        
        # Parse time window (default to 1 hour)
        hours = int(query_params.get('hours', '1'))
        time_window = timedelta(hours=hours)
        
        # Detect anomalies
        analysis = logger_instance.log_analyzer.detect_anomalies(time_window)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'analysis': analysis,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in detect_anomalies: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to detect anomalies'
            })
        }


def handle_health_check() -> Dict[str, Any]:
    """Handle health check request."""
    try:
        logger_instance = get_comprehensive_logger()
        audit_trail = get_audit_trail()
        
        log_stats = logger_instance.get_log_statistics()
        audit_stats = audit_trail.get_audit_statistics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'healthy',
                'service': 'log-search-analysis',
                'version': '1.0.0',
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'statistics': {
                    'logging': log_stats,
                    'audit': audit_stats
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in health_check: {str(e)}")
        return {
            'statusCode': 503,
            'body': json.dumps({
                'status': 'unhealthy',
                'service': 'log-search-analysis',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }