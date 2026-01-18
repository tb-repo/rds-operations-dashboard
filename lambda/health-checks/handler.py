"""
Health Check Handler for API Gateway Stage Elimination
Provides comprehensive health checks for all backend services
"""

import json
import logging
import time
import asyncio
from typing import Dict, List, Any, Optional
import boto3
import requests
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class HealthCheckService:
    """Comprehensive health check service for all backend components"""
    
    def __init__(self):
        self.lambda_client = boto3.client('lambda')
        self.apigateway_client = boto3.client('apigateway')
        self.timeout = 10
        
    def check_lambda_function(self, function_name: str) -> Dict[str, Any]:
        """Check health of a Lambda function"""
        try:
            response = self.lambda_client.get_function(FunctionName=function_name)
            
            # Test function invocation with health check payload
            test_payload = {
                "httpMethod": "GET",
                "path": "/health",
                "headers": {},
                "queryStringParameters": None,
                "body": None
            }
            
            invoke_response = self.lambda_client.invoke(
                FunctionName=function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps(test_payload)
            )
            
            status_code = invoke_response.get('StatusCode', 500)
            
            return {
                "service": function_name,
                "status": "healthy" if status_code == 200 else "unhealthy",
                "response_time_ms": None,
                "last_modified": response['Configuration']['LastModified'],
                "runtime": response['Configuration']['Runtime'],
                "status_code": status_code,
                "error": None
            }
            
        except Exception as e:
            logger.error(f"Health check failed for Lambda {function_name}: {str(e)}")
            return {
                "service": function_name,
                "status": "unhealthy",
                "response_time_ms": None,
                "last_modified": None,
                "runtime": None,
                "status_code": 500,
                "error": str(e)
            }
    
    def check_api_gateway_endpoint(self, base_url: str, endpoint: str, method: str = "GET") -> Dict[str, Any]:
        """Check health of an API Gateway endpoint"""
        url = f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        
        # Ensure URL is clean (no stage prefixes)
        if '/prod/' in url or '/staging/' in url or '/dev/' in url:
            return {
                "service": f"API Gateway {endpoint}",
                "status": "unhealthy",
                "response_time_ms": None,
                "url": url,
                "status_code": None,
                "error": "URL contains stage prefix - not clean"
            }
        
        start_time = time.time()
        
        try:
            response = requests.request(
                method=method,
                url=url,
                timeout=self.timeout,
                headers={'User-Agent': 'HealthCheck/1.0'}
            )
            
            response_time = (time.time() - start_time) * 1000
            
            return {
                "service": f"API Gateway {endpoint}",
                "status": "healthy" if response.status_code < 400 else "unhealthy",
                "response_time_ms": round(response_time, 2),
                "url": url,
                "status_code": response.status_code,
                "error": None
            }
            
        except requests.exceptions.Timeout:
            response_time = (time.time() - start_time) * 1000
            return {
                "service": f"API Gateway {endpoint}",
                "status": "unhealthy",
                "response_time_ms": round(response_time, 2),
                "url": url,
                "status_code": None,
                "error": "Request timeout"
            }
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return {
                "service": f"API Gateway {endpoint}",
                "status": "unhealthy",
                "response_time_ms": round(response_time, 2),
                "url": url,
                "status_code": None,
                "error": str(e)
            }
    
    def check_service_discovery(self, internal_api_url: str) -> Dict[str, Any]:
        """Check that service discovery is working correctly"""
        try:
            # Test that internal API URL is clean
            if '/prod' in internal_api_url or '/staging' in internal_api_url or '/dev' in internal_api_url:
                return {
                    "service": "Service Discovery",
                    "status": "unhealthy",
                    "error": "Internal API URL contains stage prefix",
                    "internal_api_url": internal_api_url
                }
            
            # Test service endpoints
            services = ['instances', 'operations', 'discovery', 'monitoring', 'compliance', 'costs']
            service_results = []
            
            for service in services:
                endpoint_url = f"{internal_api_url.rstrip('/')}/{service}"
                result = self.check_api_gateway_endpoint(internal_api_url, service, "GET")
                service_results.append(result)
            
            healthy_services = [r for r in service_results if r['status'] == 'healthy']
            
            return {
                "service": "Service Discovery",
                "status": "healthy" if len(healthy_services) >= len(services) * 0.8 else "unhealthy",
                "total_services": len(services),
                "healthy_services": len(healthy_services),
                "service_results": service_results,
                "internal_api_url": internal_api_url
            }
            
        except Exception as e:
            return {
                "service": "Service Discovery",
                "status": "unhealthy",
                "error": str(e),
                "internal_api_url": internal_api_url
            }
    
    def check_cors_configuration(self, api_url: str) -> Dict[str, Any]:
        """Check CORS configuration with clean URLs"""
        try:
            cors_url = f"{api_url.rstrip('/')}/cors-config"
            
            # Ensure CORS URL is clean
            if '/prod/' in cors_url or '/staging/' in cors_url or '/dev/' in cors_url:
                return {
                    "service": "CORS Configuration",
                    "status": "unhealthy",
                    "error": "CORS URL contains stage prefix",
                    "url": cors_url
                }
            
            response = requests.get(cors_url, timeout=self.timeout)
            
            if response.status_code == 200:
                cors_data = response.json()
                
                # Validate CORS configuration
                has_allowed_origins = 'allowedOrigins' in cors_data
                cors_enabled = cors_data.get('corsEnabled', False)
                
                return {
                    "service": "CORS Configuration",
                    "status": "healthy" if has_allowed_origins and cors_enabled else "unhealthy",
                    "url": cors_url,
                    "cors_enabled": cors_enabled,
                    "allowed_origins": cors_data.get('allowedOrigins', []),
                    "status_code": response.status_code
                }
            else:
                return {
                    "service": "CORS Configuration",
                    "status": "unhealthy",
                    "url": cors_url,
                    "status_code": response.status_code,
                    "error": f"HTTP {response.status_code}"
                }
                
        except Exception as e:
            return {
                "service": "CORS Configuration",
                "status": "unhealthy",
                "url": cors_url if 'cors_url' in locals() else None,
                "error": str(e)
            }
    
    def comprehensive_health_check(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Perform comprehensive health check of all services"""
        start_time = datetime.now(timezone.utc)
        results = []
        
        # Check BFF API Gateway endpoints
        bff_api_url = config.get('bff_api_url', 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com')
        bff_endpoints = ['/health', '/cors-config', '/api/health']
        
        for endpoint in bff_endpoints:
            result = self.check_api_gateway_endpoint(bff_api_url, endpoint)
            results.append(result)
        
        # Check Internal API Gateway endpoints
        internal_api_url = config.get('internal_api_url', 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com')
        internal_endpoints = ['/instances', '/operations', '/discovery', '/monitoring', '/compliance', '/costs']
        
        for endpoint in internal_endpoints:
            result = self.check_api_gateway_endpoint(internal_api_url, endpoint)
            results.append(result)
        
        # Check Lambda functions
        lambda_functions = config.get('lambda_functions', [
            'rds-discovery-prod',
            'rds-operations-prod',
            'rds-monitoring-prod',
            'rds-compliance-prod',
            'rds-costs-prod'
        ])
        
        for function_name in lambda_functions:
            result = self.check_lambda_function(function_name)
            results.append(result)
        
        # Check service discovery
        service_discovery_result = self.check_service_discovery(internal_api_url)
        results.append(service_discovery_result)
        
        # Check CORS configuration
        cors_result = self.check_cors_configuration(bff_api_url)
        results.append(cors_result)
        
        # Calculate overall health
        healthy_services = [r for r in results if r['status'] == 'healthy']
        total_services = len(results)
        health_percentage = (len(healthy_services) / total_services) * 100 if total_services > 0 else 0
        
        overall_status = "healthy" if health_percentage >= 80 else "degraded" if health_percentage >= 50 else "unhealthy"
        
        end_time = datetime.now(timezone.utc)
        duration = (end_time - start_time).total_seconds()
        
        return {
            "overall_status": overall_status,
            "health_percentage": round(health_percentage, 2),
            "total_services": total_services,
            "healthy_services": len(healthy_services),
            "unhealthy_services": total_services - len(healthy_services),
            "check_duration_seconds": round(duration, 2),
            "timestamp": start_time.isoformat(),
            "clean_urls_validated": True,
            "stage_elimination_complete": all('/prod/' not in str(r.get('url', '')) for r in results if 'url' in r),
            "services": results
        }

def lambda_handler(event, context):
    """Lambda handler for health checks"""
    try:
        # Extract configuration from event or environment
        config = event.get('config', {})
        
        # Default configuration
        default_config = {
            'bff_api_url': 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'internal_api_url': 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com',
            'lambda_functions': [
                'rds-discovery-prod',
                'rds-operations-prod',
                'rds-monitoring-prod',
                'rds-compliance-prod',
                'rds-costs-prod'
            ]
        }
        
        # Merge configurations
        final_config = {**default_config, **config}
        
        # Perform health check
        health_service = HealthCheckService()
        health_result = health_service.comprehensive_health_check(final_config)
        
        # Return appropriate HTTP status based on health
        status_code = 200 if health_result['overall_status'] == 'healthy' else 503
        
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps(health_result, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Health check handler error: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'overall_status': 'unhealthy',
                'error': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }

# For testing purposes
if __name__ == "__main__":
    # Test the health check service
    test_event = {
        'config': {
            'bff_api_url': 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'internal_api_url': 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
        }
    }
    
    result = lambda_handler(test_event, None)
    print(json.dumps(json.loads(result['body']), indent=2))