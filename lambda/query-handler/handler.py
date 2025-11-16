#!/usr/bin/env python3
"""
Query Handler Lambda

Unified query handler for API Gateway GET endpoints.
Handles filtering, pagination, and data retrieval from DynamoDB.

Requirements: REQ-3.1, REQ-3.2, REQ-3.3, REQ-10.1
"""

import json
import os
from typing import Dict, Any, List, Optional
from decimal import Decimal

# Import shared utilities
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from shared.logger import get_logger
from shared.aws_clients import get_dynamodb_client
from shared.config import get_config

# Initialize logger
logger = None  # Will be initialized in handler with Lambda context


class DecimalEncoder(json.JSONEncoder):
    """JSON encoder for Decimal types from DynamoDB."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


class QueryHandler:
    """Handle API Gateway query requests."""
    
    def __init__(self):
        """Initialize query handler."""
        self.config = get_config()
        self.dynamodb = get_dynamodb_client()
        
        # Table names
        self.inventory_table = self.config.get('inventory_table', 'rds_inventory')
        self.metrics_cache_table = self.config.get('metrics_cache_table', 'rds_metrics_cache')
        self.health_alerts_table = self.config.get('health_alerts_table', 'rds_health_alerts')
        self.cost_analysis_table = self.config.get('cost_analysis_table', 'rds_cost_analysis')
        self.compliance_table = self.config.get('compliance_table', 'rds_compliance')
        self.audit_log_table = self.config.get('audit_log_table', 'rds_audit_log')
    
    def handle_request(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle API Gateway request.
        
        Args:
            event: API Gateway event
            
        Returns:
            dict: API Gateway response
        """
        try:
            # Extract action from event
            action = event.get('action')
            if not action:
                # Try to extract from body for proxy integration
                body = json.loads(event.get('body', '{}'))
                action = body.get('action')
            
            if not action:
                return self._error_response(400, 'Missing action parameter')
            
            # Route to appropriate handler
            if action == 'list_instances':
                return self._list_instances(event)
            elif action == 'get_instance':
                return self._get_instance(event)
            elif action == 'get_metrics':
                return self._get_metrics(event)
            elif action == 'get_health':
                return self._get_health(event)
            elif action == 'get_alerts':
                return self._get_alerts(event)
            elif action == 'get_costs':
                return self._get_costs(event)
            elif action == 'get_cost_trends':
                return self._get_cost_trends(event)
            elif action == 'get_recommendations':
                return self._get_recommendations(event)
            elif action == 'get_compliance':
                return self._get_compliance(event)
            elif action == 'get_violations':
                return self._get_violations(event)
            elif action == 'get_operations_history':
                return self._get_operations_history(event)
            else:
                return self._error_response(400, f'Unknown action: {action}')
                
        except Exception as e:
            logger.error('Error handling request', error=str(e), action=action)
            return self._error_response(500, f'Internal error: {str(e)}')
    
    def _list_instances(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        List all RDS instances with optional filtering.
        
        Query parameters:
        - account: Filter by account ID
        - region: Filter by region
        - engine: Filter by engine type
        - status: Filter by status
        - environment: Filter by environment
        - limit: Max results (default 100)
        - offset: Pagination offset (default 0)
        """
        try:
            # Extract query parameters
            params = event.get('queryStringParameters', {}) or {}
            
            account = params.get('account')
            region = params.get('region')
            engine = params.get('engine')
            status = params.get('status')
            environment = params.get('environment')
            limit = int(params.get('limit', 100))
            offset = int(params.get('offset', 0))
            
            # Query DynamoDB
            table = self.dynamodb.Table(self.inventory_table)
            
            # Build filter expression
            filter_expressions = []
            expression_values = {}
            
            if account:
                filter_expressions.append('account_id = :account')
                expression_values[':account'] = account
            
            if region:
                filter_expressions.append('region = :region')
                expression_values[':region'] = region
            
            if engine:
                filter_expressions.append('begins_with(engine, :engine)')
                expression_values[':engine'] = engine
            
            if status:
                filter_expressions.append('instance_status = :status')
                expression_values[':status'] = status
            
            if environment:
                filter_expressions.append('environment = :environment')
                expression_values[':environment'] = environment
            
            # Scan with filters
            scan_kwargs = {}
            if filter_expressions:
                scan_kwargs['FilterExpression'] = ' AND '.join(filter_expressions)
                scan_kwargs['ExpressionAttributeValues'] = expression_values
            
            response = table.scan(**scan_kwargs)
            items = response.get('Items', [])
            
            # Apply pagination
            total = len(items)
            paginated_items = items[offset:offset + limit]
            
            logger.info('Listed instances',
                total=total,
                returned=len(paginated_items),
                filters={'account': account, 'region': region, 'engine': engine}
            )
            
            return self._success_response({
                'instances': paginated_items,
                'total': total,
                'limit': limit,
                'offset': offset,
                'has_more': offset + limit < total
            })
            
        except Exception as e:
            logger.error('Error listing instances', error=str(e))
            return self._error_response(500, f'Error listing instances: {str(e)}')
    
    def _get_instance(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get details for a specific instance."""
        try:
            instance_id = event.get('instanceId') or event.get('pathParameters', {}).get('instanceId')
            
            if not instance_id:
                return self._error_response(400, 'Missing instance_id')
            
            table = self.dynamodb.Table(self.inventory_table)
            response = table.get_item(Key={'instance_id': instance_id})
            
            item = response.get('Item')
            if not item:
                return self._error_response(404, f'Instance {instance_id} not found')
            
            logger.info('Retrieved instance', instance_id=instance_id)
            
            return self._success_response({'instance': item})
            
        except Exception as e:
            logger.error('Error getting instance', error=str(e), instance_id=instance_id)
            return self._error_response(500, f'Error getting instance: {str(e)}')
    
    def _get_metrics(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get metrics for a specific instance."""
        try:
            instance_id = event.get('instanceId') or event.get('pathParameters', {}).get('instanceId')
            params = event.get('queryStringParameters', {}) or {}
            
            period = params.get('period', '1h')  # 1h, 6h, 24h, 7d
            
            if not instance_id:
                return self._error_response(400, 'Missing instance_id')
            
            # Query metrics cache
            table = self.dynamodb.Table(self.metrics_cache_table)
            response = table.query(
                KeyConditionExpression='instance_id = :id',
                ExpressionAttributeValues={':id': instance_id},
                ScanIndexForward=False,  # Most recent first
                Limit=100
            )
            
            metrics = response.get('Items', [])
            
            logger.info('Retrieved metrics',
                instance_id=instance_id,
                period=period,
                count=len(metrics)
            )
            
            return self._success_response({
                'instance_id': instance_id,
                'period': period,
                'metrics': metrics
            })
            
        except Exception as e:
            logger.error('Error getting metrics', error=str(e), instance_id=instance_id)
            return self._error_response(500, f'Error getting metrics: {str(e)}')
    
    def _get_health(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get health status for all instances."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            severity = params.get('severity')  # critical, warning
            limit = int(params.get('limit', 100))
            
            table = self.dynamodb.Table(self.health_alerts_table)
            
            # Scan for active alerts
            scan_kwargs = {
                'FilterExpression': 'alert_status = :status',
                'ExpressionAttributeValues': {':status': 'active'},
                'Limit': limit
            }
            
            if severity:
                scan_kwargs['FilterExpression'] += ' AND severity = :severity'
                scan_kwargs['ExpressionAttributeValues'][':severity'] = severity
            
            response = table.scan(**scan_kwargs)
            alerts = response.get('Items', [])
            
            logger.info('Retrieved health status', alert_count=len(alerts), severity=severity)
            
            return self._success_response({
                'alerts': alerts,
                'total': len(alerts)
            })
            
        except Exception as e:
            logger.error('Error getting health status', error=str(e))
            return self._error_response(500, f'Error getting health status: {str(e)}')
    
    def _get_alerts(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get active alerts."""
        return self._get_health(event)  # Same implementation
    
    def _get_costs(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get cost analysis."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            group_by = params.get('groupBy', 'account')  # account, region, engine
            
            table = self.dynamodb.Table(self.cost_analysis_table)
            response = table.scan()
            
            items = response.get('Items', [])
            
            # Group costs
            grouped_costs = {}
            total_cost = 0
            
            for item in items:
                key = item.get(group_by, 'unknown')
                cost = float(item.get('monthly_cost', 0))
                
                if key not in grouped_costs:
                    grouped_costs[key] = 0
                grouped_costs[key] += cost
                total_cost += cost
            
            logger.info('Retrieved costs', group_by=group_by, total_cost=total_cost)
            
            return self._success_response({
                'total_cost': total_cost,
                'group_by': group_by,
                'costs': grouped_costs
            })
            
        except Exception as e:
            logger.error('Error getting costs', error=str(e))
            return self._error_response(500, f'Error getting costs: {str(e)}')
    
    def _get_cost_trends(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get cost trends over time."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            days = int(params.get('days', 30))
            
            # Query cost snapshots from DynamoDB
            # Implementation depends on how cost trends are stored
            
            logger.info('Retrieved cost trends', days=days)
            
            return self._success_response({
                'days': days,
                'trends': []  # Placeholder
            })
            
        except Exception as e:
            logger.error('Error getting cost trends', error=str(e))
            return self._error_response(500, f'Error getting cost trends: {str(e)}')
    
    def _get_recommendations(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get cost optimization recommendations."""
        try:
            table = self.dynamodb.Table(self.cost_analysis_table)
            response = table.scan(
                FilterExpression='attribute_exists(recommendations)'
            )
            
            items = response.get('Items', [])
            recommendations = []
            
            for item in items:
                if 'recommendations' in item and item['recommendations']:
                    recommendations.extend(item['recommendations'])
            
            logger.info('Retrieved recommendations', count=len(recommendations))
            
            return self._success_response({
                'recommendations': recommendations,
                'total': len(recommendations)
            })
            
        except Exception as e:
            logger.error('Error getting recommendations', error=str(e))
            return self._error_response(500, f'Error getting recommendations: {str(e)}')
    
    def _get_compliance(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get compliance status."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            severity = params.get('severity')
            
            table = self.dynamodb.Table(self.compliance_table)
            response = table.scan()
            
            items = response.get('Items', [])
            
            # Calculate compliance score
            total_instances = len(items)
            compliant_instances = sum(1 for item in items if item.get('compliant', False))
            compliance_score = (compliant_instances / total_instances * 100) if total_instances > 0 else 0
            
            logger.info('Retrieved compliance status',
                total=total_instances,
                compliant=compliant_instances,
                score=compliance_score
            )
            
            return self._success_response({
                'total_instances': total_instances,
                'compliant_instances': compliant_instances,
                'compliance_score': compliance_score,
                'instances': items
            })
            
        except Exception as e:
            logger.error('Error getting compliance', error=str(e))
            return self._error_response(500, f'Error getting compliance: {str(e)}')
    
    def _get_violations(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get compliance violations."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            severity = params.get('severity')
            limit = int(params.get('limit', 100))
            
            table = self.dynamodb.Table(self.compliance_table)
            
            scan_kwargs = {
                'FilterExpression': 'compliant = :false',
                'ExpressionAttributeValues': {':false': False},
                'Limit': limit
            }
            
            if severity:
                scan_kwargs['FilterExpression'] += ' AND contains(violations, :severity)'
                scan_kwargs['ExpressionAttributeValues'][':severity'] = severity
            
            response = table.scan(**scan_kwargs)
            violations = response.get('Items', [])
            
            logger.info('Retrieved violations', count=len(violations), severity=severity)
            
            return self._success_response({
                'violations': violations,
                'total': len(violations)
            })
            
        except Exception as e:
            logger.error('Error getting violations', error=str(e))
            return self._error_response(500, f'Error getting violations: {str(e)}')
    
    def _get_operations_history(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Get operations history from audit log."""
        try:
            params = event.get('queryStringParameters', {}) or {}
            instance_id = params.get('instance_id')
            operation = params.get('operation')
            limit = int(params.get('limit', 50))
            
            table = self.dynamodb.Table(self.audit_log_table)
            
            if instance_id:
                # Query by instance_id
                response = table.query(
                    IndexName='instance_id-index',  # Assumes GSI exists
                    KeyConditionExpression='instance_id = :id',
                    ExpressionAttributeValues={':id': instance_id},
                    ScanIndexForward=False,
                    Limit=limit
                )
            else:
                # Scan all
                response = table.scan(Limit=limit)
            
            items = response.get('Items', [])
            
            # Filter by operation if specified
            if operation:
                items = [item for item in items if item.get('operation') == operation]
            
            logger.info('Retrieved operations history',
                instance_id=instance_id,
                operation=operation,
                count=len(items)
            )
            
            return self._success_response({
                'operations': items,
                'total': len(items)
            })
            
        except Exception as e:
            logger.error('Error getting operations history', error=str(e))
            return self._error_response(500, f'Error getting operations history: {str(e)}')
    
    def _success_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create success response."""
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(data, cls=DecimalEncoder)
        }
    
    def _error_response(self, status_code: int, message: str) -> Dict[str, Any]:
        """Create error response."""
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps({'error': message})
        }


def lambda_handler(event, context):
    """
    Lambda handler for query requests.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        dict: API Gateway response
    """
    global logger
    logger = get_logger('query-handler', lambda_context=context)
    
    logger.info('Query request received',
        action=event.get('action'),
        path=event.get('path'),
        method=event.get('httpMethod')
    )
    
    handler = QueryHandler()
    return handler.handle_request(event)
