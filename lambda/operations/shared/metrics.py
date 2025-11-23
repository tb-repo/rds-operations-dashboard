#!/usr/bin/env python3
"""
CloudWatch Metrics Publisher

Centralized module for publishing custom metrics to CloudWatch.
All Lambda functions use this to publish business metrics.
"""

import boto3
from typing import Dict, List, Any, Optional
from datetime import datetime
from .logger import get_logger

logger = get_logger(__name__)


class MetricsPublisher:
    """Publish custom metrics to CloudWatch."""
    
    NAMESPACE = 'RDS/Operations'
    
    def __init__(self):
        """Initialize metrics publisher."""
        self.cloudwatch = boto3.client('cloudwatch')
        self.metrics_buffer: List[Dict[str, Any]] = []
        self.max_buffer_size = 20  # CloudWatch limit
    
    def put_metric(
        self,
        metric_name: str,
        value: float,
        unit: str = 'None',
        dimensions: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Add a metric to the buffer.
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            unit: Unit of measurement
            dimensions: Metric dimensions (optional)
        """
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': unit,
            'Timestamp': datetime.utcnow(),
        }
        
        if dimensions:
            metric_data['Dimensions'] = [
                {'Name': k, 'Value': v} for k, v in dimensions.items()
            ]
        
        self.metrics_buffer.append(metric_data)
        
        # Flush if buffer is full
        if len(self.metrics_buffer) >= self.max_buffer_size:
            self.flush()
    
    def put_count(
        self,
        metric_name: str,
        count: int,
        dimensions: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Publish a count metric.
        
        Args:
            metric_name: Name of the metric
            count: Count value
            dimensions: Metric dimensions (optional)
        """
        self.put_metric(metric_name, float(count), 'Count', dimensions)
    
    def put_percentage(
        self,
        metric_name: str,
        percentage: float,
        dimensions: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Publish a percentage metric.
        
        Args:
            metric_name: Name of the metric
            percentage: Percentage value (0-100)
            dimensions: Metric dimensions (optional)
        """
        self.put_metric(metric_name, percentage, 'Percent', dimensions)
    
    def put_duration(
        self,
        metric_name: str,
        milliseconds: float,
        dimensions: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Publish a duration metric.
        
        Args:
            metric_name: Name of the metric
            milliseconds: Duration in milliseconds
            dimensions: Metric dimensions (optional)
        """
        self.put_metric(metric_name, milliseconds, 'Milliseconds', dimensions)
    
    def put_bytes(
        self,
        metric_name: str,
        bytes_value: float,
        dimensions: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Publish a bytes metric.
        
        Args:
            metric_name: Name of the metric
            bytes_value: Size in bytes
            dimensions: Metric dimensions (optional)
        """
        self.put_metric(metric_name, bytes_value, 'Bytes', dimensions)
    
    def flush(self) -> None:
        """Flush metrics buffer to CloudWatch."""
        if not self.metrics_buffer:
            return
        
        try:
            self.cloudwatch.put_metric_data(
                Namespace=self.NAMESPACE,
                MetricData=self.metrics_buffer
            )
            
            logger.info(f"Published {len(self.metrics_buffer)} metrics to CloudWatch")
            self.metrics_buffer = []
            
        except Exception as e:
            logger.error(f"Error publishing metrics: {str(e)}")
            # Clear buffer to prevent memory buildup
            self.metrics_buffer = []
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - flush remaining metrics."""
        self.flush()


# Convenience functions for common metrics

def publish_discovery_metrics(
    total_instances: int,
    new_instances: int,
    updated_instances: int,
    deleted_instances: int,
    duration_ms: float
) -> None:
    """
    Publish discovery service metrics.
    
    Args:
        total_instances: Total number of instances discovered
        new_instances: Number of new instances
        updated_instances: Number of updated instances
        deleted_instances: Number of deleted instances
        duration_ms: Discovery duration in milliseconds
    """
    with MetricsPublisher() as metrics:
        metrics.put_count('TotalInstances', total_instances)
        metrics.put_count('NewInstances', new_instances)
        metrics.put_count('UpdatedInstances', updated_instances)
        metrics.put_count('DeletedInstances', deleted_instances)
        metrics.put_duration('DiscoveryDuration', duration_ms)


def publish_health_metrics(
    instances_checked: int,
    critical_alerts: int,
    warning_alerts: int,
    cache_hits: int,
    cache_misses: int,
    duration_ms: float
) -> None:
    """
    Publish health monitor metrics.
    
    Args:
        instances_checked: Number of instances checked
        critical_alerts: Number of critical alerts
        warning_alerts: Number of warning alerts
        cache_hits: Number of cache hits
        cache_misses: Number of cache misses
        duration_ms: Health check duration in milliseconds
    """
    with MetricsPublisher() as metrics:
        metrics.put_count('InstancesChecked', instances_checked)
        metrics.put_count('CriticalAlerts', critical_alerts)
        metrics.put_count('WarningAlerts', warning_alerts)
        metrics.put_count('CacheHits', cache_hits)
        metrics.put_count('CacheMisses', cache_misses)
        
        # Calculate cache hit rate
        total_requests = cache_hits + cache_misses
        if total_requests > 0:
            cache_hit_rate = (cache_hits / total_requests) * 100
            metrics.put_percentage('CacheHitRate', cache_hit_rate)
        
        metrics.put_duration('HealthCheckDuration', duration_ms)


def publish_cost_metrics(
    total_cost: float,
    instance_count: int,
    recommendations_count: int,
    potential_savings: float,
    duration_ms: float
) -> None:
    """
    Publish cost analyzer metrics.
    
    Args:
        total_cost: Total monthly cost
        instance_count: Number of instances analyzed
        recommendations_count: Number of optimization recommendations
        potential_savings: Potential monthly savings
        duration_ms: Analysis duration in milliseconds
    """
    with MetricsPublisher() as metrics:
        metrics.put_metric('TotalMonthlyCost', total_cost, 'None')
        metrics.put_count('InstancesAnalyzed', instance_count)
        metrics.put_count('OptimizationRecommendations', recommendations_count)
        metrics.put_metric('PotentialSavings', potential_savings, 'None')
        metrics.put_duration('CostAnalysisDuration', duration_ms)


def publish_compliance_metrics(
    total_instances: int,
    compliant_instances: int,
    critical_violations: int,
    high_violations: int,
    medium_violations: int,
    low_violations: int,
    duration_ms: float
) -> None:
    """
    Publish compliance checker metrics.
    
    Args:
        total_instances: Total number of instances checked
        compliant_instances: Number of compliant instances
        critical_violations: Number of critical violations
        high_violations: Number of high severity violations
        medium_violations: Number of medium severity violations
        low_violations: Number of low severity violations
        duration_ms: Compliance check duration in milliseconds
    """
    with MetricsPublisher() as metrics:
        metrics.put_count('InstancesChecked', total_instances)
        metrics.put_count('CompliantInstances', compliant_instances)
        metrics.put_count('CriticalViolations', critical_violations)
        metrics.put_count('HighViolations', high_violations)
        metrics.put_count('MediumViolations', medium_violations)
        metrics.put_count('LowViolations', low_violations)
        
        # Calculate compliance score
        if total_instances > 0:
            compliance_score = (compliant_instances / total_instances) * 100
            metrics.put_percentage('ComplianceScore', compliance_score)
        
        metrics.put_duration('ComplianceCheckDuration', duration_ms)


def publish_operation_metrics(
    operation_type: str,
    success: bool,
    duration_ms: float,
    environment: str
) -> None:
    """
    Publish operations service metrics.
    
    Args:
        operation_type: Type of operation (snapshot, reboot, etc.)
        success: Whether operation succeeded
        duration_ms: Operation duration in milliseconds
        environment: Instance environment
    """
    with MetricsPublisher() as metrics:
        dimensions = {
            'OperationType': operation_type,
            'Environment': environment
        }
        
        metrics.put_count('OperationsExecuted', 1, dimensions)
        
        if success:
            metrics.put_count('OperationsSucceeded', 1, dimensions)
        else:
            metrics.put_count('OperationsFailed', 1, dimensions)
        
        metrics.put_duration('OperationDuration', duration_ms, dimensions)


def publish_operation_success_rate(
    total_operations: int,
    successful_operations: int
) -> None:
    """
    Publish operation success rate metric.
    
    Args:
        total_operations: Total number of operations
        successful_operations: Number of successful operations
    """
    if total_operations > 0:
        success_rate = (successful_operations / total_operations) * 100
        with MetricsPublisher() as metrics:
            metrics.put_percentage('OperationSuccessRate', success_rate)
