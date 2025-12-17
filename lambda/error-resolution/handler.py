"""
Error Resolution Lambda Handler

Main entry point for the error resolution and monitoring system.
Provides API endpoints for error detection, classification, and resolution.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-11T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.1 → DESIGN-ErrorResolution → TASK-1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
import os
import logging
from typing import Dict, Any
from datetime import datetime

# Import shared modules
import sys
sys.path.append('/opt/python')
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from error_detector import detect_api_error, get_error_detector
from resolution_engine import get_resolution_engine, ResolutionStrategy
from logging_system import get_comprehensive_logger, LogLevel, LogCategory
from audit_system import AuditEventType, AuditSeverity, create_audit_event

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
comprehensive_logger = get_comprehensive_logger('error-resolution')


@handle_lambda_error
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for error resolution operations.
    
    Supported operations:
    - POST /detect: Detect and classify an error
    - GET /statistics: Get error detection statistics
    - POST /resolve: Attempt to resolve an error
    
    Args:
        event: Lambda event object
        context: Lambda context object
    
    Returns:
        HTTP response with CORS headers
    """
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Log request with comprehensive logging
    comprehensive_logger.info(
        f"Processing {http_method} {path}",
        category=LogCategory.SYSTEM,
        details={
            'http_method': http_method,
            'path': path,
            'query_params': event.get('queryStringParameters'),
            'user_agent': event.get('headers', {}).get('User-Agent'),
            'source_ip': event.get('requestContext', {}).get('identity', {}).get('sourceIp')
        },
        create_audit=True,
        audit_action=f"API request {http_method} {path}",
        audit_resource=f"error-resolution-api{path}",
        audit_outcome="started"
    )
    
    # Route to appropriate handler
    if http_method == 'POST' and path.endswith('/detect'):
        response = handle_detect_error(event)
    elif http_method == 'GET' and path.endswith('/statistics'):
        response = handle_get_statistics(event)
    elif http_method == 'POST' and path.endswith('/resolve'):
        response = handle_resolve_error(event)
    elif http_method == 'POST' and path.endswith('/rollback'):
        response = handle_rollback_resolution(event)
    elif http_method == 'GET' and '/attempts/' in path:
        response = handle_get_resolution_attempt(event)
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
        
        # Log 404 error
        comprehensive_logger.warning(
            f"Endpoint not found: {http_method} {path}",
            category=LogCategory.ERROR,
            details={'status_code': 404, 'endpoint': f"{http_method} {path}"},
            create_audit=True,
            audit_action=f"API request {http_method} {path}",
            audit_resource=f"error-resolution-api{path}",
            audit_outcome="not_found"
        )
    
    # Add CORS headers
    return add_cors_headers(response)


def handle_detect_error(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle error detection and classification request.
    
    Expected payload:
    {
        "status_code": 500,
        "error_message": "Internal server error",
        "service": "health-monitor",
        "endpoint": "/api/health/database",
        "request_id": "req-123",
        "context": {...},
        "user_id": "user-456",
        "stack_trace": "..."
    }
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        required_fields = ['status_code', 'error_message', 'service', 'endpoint', 'request_id']
        for field in required_fields:
            if field not in body:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'ValidationError',
                        'message': f'Missing required field: {field}'
                    })
                }
        
        # Detect and classify error
        api_error = detect_api_error(
            status_code=body['status_code'],
            error_message=body['error_message'],
            service=body['service'],
            endpoint=body['endpoint'],
            request_id=body['request_id'],
            context=body.get('context', {}),
            user_id=body.get('user_id'),
            stack_trace=body.get('stack_trace')
        )
        
        # Log error detection with comprehensive logging
        comprehensive_logger.info(
            f"Error detected and classified: {api_error.id}",
            category=LogCategory.ERROR,
            details={
                'error_id': api_error.id,
                'status_code': api_error.status_code,
                'category': api_error.category.value,
                'severity': api_error.severity.value,
                'service': api_error.service,
                'endpoint': api_error.endpoint,
                'is_critical': get_error_detector().is_critical_error(api_error),
                'should_retry': get_error_detector().should_retry(api_error)
            },
            create_audit=True,
            audit_action="error_detection",
            audit_resource=f"error:{api_error.id}",
            audit_outcome="success"
        )
        
        # Return classification result
        return {
            'statusCode': 200,
            'body': json.dumps({
                'error_id': api_error.id,
                'category': api_error.category.value,
                'severity': api_error.severity.value,
                'timestamp': api_error.timestamp.isoformat(),
                'is_critical': get_error_detector().is_critical_error(api_error),
                'should_retry': get_error_detector().should_retry(api_error),
                'classification': api_error.to_dict()
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'InvalidJSON',
                'message': 'Request body must be valid JSON'
            })
        }
    except Exception as e:
        logger.error(f"Error in detect_error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to detect and classify error'
            })
        }


def handle_get_statistics(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle request for error detection statistics.
    """
    try:
        detector = get_error_detector()
        stats = detector.get_error_statistics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'statistics': stats,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in get_statistics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve statistics'
            })
        }


def handle_resolve_error(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle error resolution request.
    
    Expected payload:
    {
        "error_id": "err_123456789_1",
        "resolution_strategy": "retry_with_backoff",
        "api_error": {
            "status_code": 500,
            "message": "Database connection failed",
            "service": "health-monitor",
            "endpoint": "/api/health/database",
            "category": "database",
            "severity": "critical"
        }
    }
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if 'error_id' not in body:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Missing required field: error_id'
                })
            }
        
        if 'api_error' not in body:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Missing required field: api_error'
                })
            }
        
        error_id = body['error_id']
        strategy_name = body.get('resolution_strategy')
        api_error_data = body['api_error']
        
        # Reconstruct APIError object (simplified for demo)
        from error_detector import APIError, ErrorCategory, ErrorSeverity
        
        api_error = APIError(
            id=error_id,
            timestamp=datetime.utcnow(),
            status_code=api_error_data['status_code'],
            message=api_error_data['message'],
            service=api_error_data['service'],
            endpoint=api_error_data['endpoint'],
            request_id=api_error_data.get('request_id', 'unknown'),
            user_id=api_error_data.get('user_id'),
            category=ErrorCategory(api_error_data['category']),
            severity=ErrorSeverity(api_error_data['severity']),
            context=api_error_data.get('context', {})
        )
        
        # Parse strategy if provided
        strategy = None
        if strategy_name:
            try:
                strategy = ResolutionStrategy(strategy_name)
            except ValueError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'ValidationError',
                        'message': f'Invalid resolution strategy: {strategy_name}'
                    })
                }
        
        # Get resolution engine and attempt resolution
        engine = get_resolution_engine()
        
        # Since we can't use async in Lambda handler directly, we'll simulate it
        # In a real implementation, you'd use asyncio.run() or make this handler async
        import asyncio
        
        try:
            # Run the async resolution
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            attempt = loop.run_until_complete(
                engine.resolve_error(api_error, strategy, body.get('context'))
            )
            loop.close()
        except Exception as e:
            logger.error(f"Resolution execution failed: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'ResolutionError',
                    'message': f'Resolution execution failed: {str(e)}'
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'attempt_id': attempt.id,
                'error_id': error_id,
                'strategy': attempt.strategy.value,
                'status': attempt.status.value,
                'success': attempt.success,
                'message': attempt.error_message or 'Resolution completed',
                'started_at': attempt.started_at.isoformat(),
                'completed_at': attempt.completed_at.isoformat() if attempt.completed_at else None
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'InvalidJSON',
                'message': 'Request body must be valid JSON'
            })
        }
    except Exception as e:
        logger.error(f"Error in resolve_error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to process resolution request'
            })
        }


def handle_rollback_resolution(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle resolution rollback request.
    
    Expected payload:
    {
        "attempt_id": "res_123456789_1"
    }
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if 'attempt_id' not in body:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Missing required field: attempt_id'
                })
            }
        
        attempt_id = body['attempt_id']
        
        # Get resolution engine and attempt rollback
        engine = get_resolution_engine()
        
        # Run the async rollback
        import asyncio
        
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            success = loop.run_until_complete(engine.rollback_resolution(attempt_id))
            loop.close()
        except Exception as e:
            logger.error(f"Rollback execution failed: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'RollbackError',
                    'message': f'Rollback execution failed: {str(e)}'
                })
            }
        
        # Get updated attempt status
        attempt = engine.get_resolution_attempt(attempt_id)
        if not attempt:
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'NotFound',
                    'message': f'Resolution attempt {attempt_id} not found'
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'attempt_id': attempt_id,
                'rollback_success': success,
                'status': attempt.status.value,
                'message': 'Rollback completed' if success else 'Rollback failed'
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'InvalidJSON',
                'message': 'Request body must be valid JSON'
            })
        }
    except Exception as e:
        logger.error(f"Error in rollback_resolution: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to process rollback request'
            })
        }


def handle_get_resolution_attempt(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle get resolution attempt request.
    
    Expected path: /attempts/{attempt_id}
    """
    try:
        # Extract attempt ID from path
        path = event.get('path', '')
        path_parts = path.split('/')
        
        if len(path_parts) < 2 or 'attempts' not in path_parts:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': 'Invalid path format. Expected: /attempts/{attempt_id}'
                })
            }
        
        attempt_id = path_parts[-1]  # Last part of the path
        
        # Get resolution engine and attempt
        engine = get_resolution_engine()
        attempt = engine.get_resolution_attempt(attempt_id)
        
        if not attempt:
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'NotFound',
                    'message': f'Resolution attempt {attempt_id} not found'
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'attempt': attempt.to_dict()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in get_resolution_attempt: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalError',
                'message': 'Failed to retrieve resolution attempt'
            })
        }


def handle_health_check(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle health check request.
    """
    try:
        detector = get_error_detector()
        detector_stats = detector.get_error_statistics()
        
        engine = get_resolution_engine()
        engine_stats = engine.get_statistics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'healthy',
                'service': 'error-resolution',
                'version': '1.0.0',
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'statistics': {
                    'detector': detector_stats,
                    'resolution_engine': engine_stats
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in health_check: {str(e)}")
        return {
            'statusCode': 503,
            'body': json.dumps({
                'status': 'unhealthy',
                'service': 'error-resolution',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
        }