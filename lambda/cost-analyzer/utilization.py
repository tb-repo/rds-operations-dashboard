#!/usr/bin/env python3
"""
Utilization Analyzer

Analyzes RDS instance utilization patterns to identify underutilized or
oversized instances for right-sizing recommendations.
"""

import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from decimal import Decimal

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger
from shared.aws_clients import get_cloudwatch_client, get_dynamodb_client

logger = get_logger(__name__)


class UtilizationAnalyzer:
    """Analyze RDS instance utilization patterns."""
    
    # Thresholds for utilization analysis
    LOW_CPU_THRESHOLD = 20.0  # CPU < 20% for 7 days = underutilized
    LOW_CONNECTIONS_THRESHOLD = 10  # < 10 connections = potentially oversized
    LOW_MEMORY_THRESHOLD = 20.0  # Free memory < 20% = memory pressure
    ANALYSIS_DAYS = 7  # Analyze last 7 days
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize utilization analyzer.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.cloudwatch = get_cloudwatch_client()
        self.dynamodb = get_dynamodb_client()
    
    def analyze_all_instances(self, instances: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
        """
        Analyze utilization for all instances.
        
        Args:
            instances: List of RDS instances
            
        Returns:
            dict: Utilization data keyed by instance_id
        """
        utilization_data = {}
        
        for instance in instances:
            instance_id = instance.get('instance_id')
            if not instance_id:
                continue
            
            try:
                utilization = self.analyze_instance(instance)
                utilization_data[instance_id] = utilization
            except Exception as e:
                logger.error(f"Failed to analyze utilization for {instance_id}: {str(e)}")
                continue
        
        return utilization_data
    
    def analyze_instance(self, instance: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze utilization for a single instance.
        
        Args:
            instance: RDS instance data
            
        Returns:
            dict: Utilization metrics and flags
        """
        instance_id = instance.get('instance_id')
        region = instance.get('region', 'ap-southeast-1')
        
        # Get metrics from cache or CloudWatch
        metrics = self._get_utilization_metrics(instance_id, region)
        
        # Analyze patterns
        analysis = {
            'instance_id': instance_id,
            'avg_cpu': metrics.get('avg_cpu', 0),
            'max_cpu': metrics.get('max_cpu', 0),
            'avg_connections': metrics.get('avg_connections', 0),
            'max_connections': metrics.get('max_connections', 0),
            'avg_free_memory_pct': metrics.get('avg_free_memory_pct', 0),
            'min_free_memory_pct': metrics.get('min_free_memory_pct', 0),
            'is_underutilized': False,
            'is_oversized': False,
            'has_memory_pressure': False,
            'utilization_score': 0  # 0-100, higher = better utilized
        }
        
        # Check if underutilized (low CPU)
        if analysis['avg_cpu'] < self.LOW_CPU_THRESHOLD:
            analysis['is_underutilized'] = True
            logger.info(f"{instance_id} is underutilized: avg CPU {analysis['avg_cpu']:.1f}%")
        
        # Check if oversized (low connections)
        if analysis['avg_connections'] < self.LOW_CONNECTIONS_THRESHOLD:
            analysis['is_oversized'] = True
            logger.info(f"{instance_id} may be oversized: avg connections {analysis['avg_connections']:.0f}")
        
        # Check for memory pressure
        if analysis['avg_free_memory_pct'] < self.LOW_MEMORY_THRESHOLD:
            analysis['has_memory_pressure'] = True
            logger.warning(f"{instance_id} has memory pressure: avg free memory {analysis['avg_free_memory_pct']:.1f}%")
        
        # Calculate utilization score (0-100)
        # Higher score = better utilized
        cpu_score = min(analysis['avg_cpu'] / 70 * 100, 100)  # Target 70% CPU
        conn_score = min(analysis['avg_connections'] / 50 * 100, 100)  # Target 50 connections
        memory_score = 100 - analysis['avg_free_memory_pct']  # Less free memory = better utilized
        
        analysis['utilization_score'] = round((cpu_score + conn_score + memory_score) / 3, 1)
        
        return analysis
    
    def _get_utilization_metrics(self, instance_id: str, region: str) -> Dict[str, float]:
        """
        Get utilization metrics from cache or CloudWatch.
        
        Args:
            instance_id: RDS instance identifier
            region: AWS region
            
        Returns:
            dict: Utilization metrics
        """
        # Try to get from metrics cache first
        cached_metrics = self._get_cached_metrics(instance_id)
        if cached_metrics:
            return cached_metrics
        
        # Query CloudWatch for last 7 days
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=self.ANALYSIS_DAYS)
        
        metrics = {}
        
        try:
            # Get CPU utilization
            cpu_stats = self._query_cloudwatch_metric(
                instance_id,
                'CPUUtilization',
                start_time,
                end_time,
                region
            )
            metrics['avg_cpu'] = cpu_stats.get('Average', 0)
            metrics['max_cpu'] = cpu_stats.get('Maximum', 0)
            
            # Get database connections
            conn_stats = self._query_cloudwatch_metric(
                instance_id,
                'DatabaseConnections',
                start_time,
                end_time,
                region
            )
            metrics['avg_connections'] = conn_stats.get('Average', 0)
            metrics['max_connections'] = conn_stats.get('Maximum', 0)
            
            # Get freeable memory
            memory_stats = self._query_cloudwatch_metric(
                instance_id,
                'FreeableMemory',
                start_time,
                end_time,
                region
            )
            
            # Convert bytes to percentage (need total memory from instance class)
            # Simplified: assume average free memory as percentage
            avg_free_memory_bytes = memory_stats.get('Average', 0)
            # This is a simplification - in production, calculate actual percentage
            metrics['avg_free_memory_pct'] = min(avg_free_memory_bytes / (1024**3) * 10, 100)  # Rough estimate
            metrics['min_free_memory_pct'] = min(memory_stats.get('Minimum', 0) / (1024**3) * 10, 100)
            
        except Exception as e:
            logger.error(f"Failed to query CloudWatch metrics for {instance_id}: {str(e)}")
            # Return default values
            metrics = {
                'avg_cpu': 50.0,
                'max_cpu': 80.0,
                'avg_connections': 20,
                'max_connections': 50,
                'avg_free_memory_pct': 40.0,
                'min_free_memory_pct': 20.0
            }
        
        return metrics
    
    def _get_cached_metrics(self, instance_id: str) -> Optional[Dict[str, float]]:
        """
        Get metrics from DynamoDB cache.
        
        Args:
            instance_id: RDS instance identifier
            
        Returns:
            dict: Cached metrics, or None if not found/expired
        """
        try:
            table_name = self.config.get('dynamodb_tables', {}).get('metrics_cache', 'metrics-cache-prod')
            
            # Query for recent metrics (last 7 days average)
            # This is simplified - in production, aggregate multiple cache entries
            cache_key = f"{instance_id}#CPUUtilization#3600"
            
            response = self.dynamodb.get_item(
                TableName=table_name,
                Key={'cache_key': {'S': cache_key}}
            )
            
            if 'Item' in response:
                # Check if cache is still valid
                cached_at = response['Item'].get('cached_at', {}).get('S', '')
                if cached_at:
                    cached_time = datetime.fromisoformat(cached_at.replace('Z', '+00:00'))
                    if datetime.utcnow() - cached_time < timedelta(hours=1):
                        # Cache is fresh, use it
                        # Extract metrics from datapoints
                        # This is simplified - full implementation would aggregate properly
                        return None  # For now, always query CloudWatch
            
            return None
            
        except Exception as e:
            logger.debug(f"Cache lookup failed for {instance_id}: {str(e)}")
            return None
    
    def _query_cloudwatch_metric(
        self,
        instance_id: str,
        metric_name: str,
        start_time: datetime,
        end_time: datetime,
        region: str
    ) -> Dict[str, float]:
        """
        Query CloudWatch for a specific metric.
        
        Args:
            instance_id: RDS instance identifier
            metric_name: CloudWatch metric name
            start_time: Start of time range
            end_time: End of time range
            region: AWS region
            
        Returns:
            dict: Statistics (Average, Maximum, Minimum)
        """
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/RDS',
                MetricName=metric_name,
                Dimensions=[
                    {'Name': 'DBInstanceIdentifier', 'Value': instance_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,  # 1 hour periods
                Statistics=['Average', 'Maximum', 'Minimum']
            )
            
            datapoints = response.get('Datapoints', [])
            if not datapoints:
                return {'Average': 0, 'Maximum': 0, 'Minimum': 0}
            
            # Calculate overall statistics
            averages = [dp['Average'] for dp in datapoints if 'Average' in dp]
            maximums = [dp['Maximum'] for dp in datapoints if 'Maximum' in dp]
            minimums = [dp['Minimum'] for dp in datapoints if 'Minimum' in dp]
            
            return {
                'Average': sum(averages) / len(averages) if averages else 0,
                'Maximum': max(maximums) if maximums else 0,
                'Minimum': min(minimums) if minimums else 0
            }
            
        except Exception as e:
            logger.error(f"CloudWatch query failed for {instance_id}/{metric_name}: {str(e)}")
            return {'Average': 0, 'Maximum': 0, 'Minimum': 0}
