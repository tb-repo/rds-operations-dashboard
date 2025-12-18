#!/usr/bin/env python3
"""
Cost Reporter

Generates cost analysis reports and saves them to S3.
"""

import os
import sys
import json
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, List, Any, Optional

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger
from shared.aws_clients import AWSClients

logger = get_logger(__name__)


class CostReporter:
    """Generate and save cost analysis reports."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize cost reporter.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.s3 = AWSClients.get_s3_client()
        self.dynamodb = AWSClients.get_dynamodb_client()
        self.cloudwatch = AWSClients.get_cloudwatch_client()
        self.cost_snapshots_table = config.get('cost_snapshots_table', 'cost-snapshots-prod')
    
    def generate_report(
        self,
        instance_costs: List[Dict[str, Any]],
        cost_aggregations: Dict[str, Dict[str, Decimal]],
        recommendations: List[Dict[str, Any]],
        total_cost: Decimal
    ) -> Dict[str, Any]:
        """
        Generate comprehensive cost analysis report.
        
        Args:
            instance_costs: List of instance cost data
            cost_aggregations: Aggregated costs
            recommendations: List of recommendations
            total_cost: Total monthly cost
            
        Returns:
            dict: Complete cost report
        """
        report_date = datetime.utcnow().strftime('%Y-%m-%d')
        
        # Calculate total potential savings
        total_savings = sum(
            rec.get('estimated_monthly_savings', 0)
            for rec in recommendations
        )
        
        # Group recommendations by priority
        high_priority = [r for r in recommendations if r.get('priority') == 'high']
        medium_priority = [r for r in recommendations if r.get('priority') == 'medium']
        low_priority = [r for r in recommendations if r.get('priority') == 'low']
        
        report = {
            'report_date': report_date,
            'generated_at': datetime.utcnow().isoformat() + 'Z',
            'summary': {
                'total_instances': len(instance_costs),
                'total_monthly_cost': float(total_cost),
                'total_potential_savings': round(total_savings, 2),
                'savings_percentage': round((total_savings / float(total_cost) * 100) if total_cost > 0 else 0, 1),
                'recommendations_count': len(recommendations),
                'high_priority_recommendations': len(high_priority),
                'medium_priority_recommendations': len(medium_priority),
                'low_priority_recommendations': len(low_priority)
            },
            'cost_by_account': {
                k: float(v) for k, v in cost_aggregations['by_account'].items()
            },
            'cost_by_region': {
                k: float(v) for k, v in cost_aggregations['by_region'].items()
            },
            'cost_by_engine': {
                k: float(v) for k, v in cost_aggregations['by_engine'].items()
            },
            'cost_by_instance_family': {
                k: float(v) for k, v in cost_aggregations['by_instance_family'].items()
            },
            'top_10_most_expensive': self._get_top_expensive_instances(instance_costs, 10),
            'recommendations': {
                'high_priority': high_priority,
                'medium_priority': medium_priority,
                'low_priority': low_priority
            },
            'detailed_costs': instance_costs
        }
        
        logger.info(f"Generated cost report: {len(instance_costs)} instances, ${float(total_cost):.2f} total, ${total_savings:.2f} potential savings")
        
        return report
    
    def save_report_to_s3(self, report: Dict[str, Any]) -> str:
        """
        Save cost report to S3.
        
        Args:
            report: Cost report data
            
        Returns:
            str: S3 key where report was saved
        """
        bucket_name = self.config.get('s3_bucket', 'rds-dashboard-data')
        report_date = report['report_date']
        year, month, day = report_date.split('-')
        
        # S3 key: cost-reports/YYYY/MM/cost_analysis_YYYY-MM-DD.json
        s3_key = f"cost-reports/{year}/{month}/cost_analysis_{report_date}.json"
        
        try:
            # Convert Decimal to float for JSON serialization
            report_json = json.dumps(report, indent=2, default=str)
            
            self.s3.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=report_json.encode('utf-8'),
                ContentType='application/json',
                ServerSideEncryption='AES256',
                Metadata={
                    'report-date': report_date,
                    'generated-by': 'cost-analyzer',
                    'version': '1.0.0'
                }
            )
            
            logger.info(f"Saved cost report to s3://{bucket_name}/{s3_key}")
            return s3_key
            
        except Exception as e:
            logger.error(f"Failed to save report to S3: {str(e)}")
            raise
    
    def _get_top_expensive_instances(
        self,
        instance_costs: List[Dict[str, Any]],
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Get top N most expensive instances.
        
        Args:
            instance_costs: List of instance cost data
            limit: Number of instances to return
            
        Returns:
            list: Top expensive instances
        """
        sorted_costs = sorted(
            instance_costs,
            key=lambda x: x['monthly_cost'],
            reverse=True
        )
        
        return sorted_costs[:limit]
    
    def store_cost_snapshot(
        self,
        total_cost: Decimal,
        cost_aggregations: Dict[str, Dict[str, Decimal]],
        instance_count: int
    ) -> None:
        """
        Store daily cost snapshot in DynamoDB for trend tracking.
        
        Args:
            total_cost: Total monthly cost
            cost_aggregations: Aggregated costs by account, region, engine
            instance_count: Number of instances analyzed
        """
        snapshot_date = datetime.utcnow().strftime('%Y-%m-%d')
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        try:
            # Create snapshot item
            snapshot_item = {
                'snapshot_date': snapshot_date,
                'timestamp': timestamp,
                'total_monthly_cost': float(total_cost),
                'instance_count': instance_count,
                'cost_by_account': {k: float(v) for k, v in cost_aggregations['by_account'].items()},
                'cost_by_region': {k: float(v) for k, v in cost_aggregations['by_region'].items()},
                'cost_by_engine': {k: float(v) for k, v in cost_aggregations['by_engine'].items()},
                'cost_by_instance_family': {k: float(v) for k, v in cost_aggregations['by_instance_family'].items()}
            }
            
            # Store in DynamoDB
            self.dynamodb.put_item(
                TableName=self.cost_snapshots_table,
                Item=self._convert_to_dynamodb_item(snapshot_item)
            )
            
            logger.info(f"Stored cost snapshot for {snapshot_date}: ${float(total_cost):.2f}")
            
        except Exception as e:
            logger.error(f"Failed to store cost snapshot: {str(e)}")
            raise
    
    def calculate_cost_trends(self) -> Dict[str, Any]:
        """
        Calculate cost trends by comparing current snapshot with previous periods.
        
        Returns:
            dict: Cost trend analysis including month-over-month changes
        """
        try:
            today = datetime.utcnow().strftime('%Y-%m-%d')
            
            # Get current snapshot
            current_snapshot = self._get_snapshot_by_date(today)
            if not current_snapshot:
                logger.warn("No current snapshot found for trend analysis")
                return {}
            
            # Get snapshot from 30 days ago (previous month)
            previous_month_date = (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d')
            previous_snapshot = self._get_snapshot_by_date(previous_month_date)
            
            # Get snapshot from 7 days ago (previous week)
            previous_week_date = (datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%d')
            previous_week_snapshot = self._get_snapshot_by_date(previous_week_date)
            
            trends = {
                'current_date': today,
                'current_cost': current_snapshot.get('total_monthly_cost', 0),
                'current_instance_count': current_snapshot.get('instance_count', 0)
            }
            
            # Calculate month-over-month change
            if previous_snapshot:
                prev_cost = previous_snapshot.get('total_monthly_cost', 0)
                cost_change = trends['current_cost'] - prev_cost
                cost_change_pct = (cost_change / prev_cost * 100) if prev_cost > 0 else 0
                
                trends['month_over_month'] = {
                    'previous_date': previous_month_date,
                    'previous_cost': prev_cost,
                    'cost_change': round(cost_change, 2),
                    'cost_change_percentage': round(cost_change_pct, 1),
                    'trend': 'increasing' if cost_change > 0 else 'decreasing' if cost_change < 0 else 'stable'
                }
                
                logger.info(f"Month-over-month cost change: ${cost_change:.2f} ({cost_change_pct:.1f}%)")
            
            # Calculate week-over-week change
            if previous_week_snapshot:
                prev_week_cost = previous_week_snapshot.get('total_monthly_cost', 0)
                week_cost_change = trends['current_cost'] - prev_week_cost
                week_cost_change_pct = (week_cost_change / prev_week_cost * 100) if prev_week_cost > 0 else 0
                
                trends['week_over_week'] = {
                    'previous_date': previous_week_date,
                    'previous_cost': prev_week_cost,
                    'cost_change': round(week_cost_change, 2),
                    'cost_change_percentage': round(week_cost_change_pct, 1),
                    'trend': 'increasing' if week_cost_change > 0 else 'decreasing' if week_cost_change < 0 else 'stable'
                }
            
            return trends
            
        except Exception as e:
            logger.error(f"Failed to calculate cost trends: {str(e)}")
            return {}
    
    def publish_cost_metrics(
        self,
        total_cost: Decimal,
        cost_aggregations: Dict[str, Dict[str, Decimal]]
    ) -> None:
        """
        Publish cost metrics to CloudWatch for monitoring and alerting.
        
        Args:
            total_cost: Total monthly cost
            cost_aggregations: Aggregated costs by account, region, engine
        """
        try:
            namespace = 'RDSDashboard'
            timestamp = datetime.utcnow()
            
            # Publish total cost metric
            self.cloudwatch.put_metric_data(
                Namespace=namespace,
                MetricData=[
                    {
                        'MetricName': 'TotalMonthlyCost',
                        'Value': float(total_cost),
                        'Unit': 'None',
                        'Timestamp': timestamp
                    }
                ]
            )
            
            # Publish cost per account
            account_metrics = []
            for account_id, cost in cost_aggregations['by_account'].items():
                account_metrics.append({
                    'MetricName': 'CostPerAccount',
                    'Value': float(cost),
                    'Unit': 'None',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'AccountId', 'Value': account_id}
                    ]
                })
            
            if account_metrics:
                # CloudWatch allows max 20 metrics per call
                for i in range(0, len(account_metrics), 20):
                    batch = account_metrics[i:i+20]
                    self.cloudwatch.put_metric_data(
                        Namespace=namespace,
                        MetricData=batch
                    )
            
            # Publish cost per region
            region_metrics = []
            for region, cost in cost_aggregations['by_region'].items():
                region_metrics.append({
                    'MetricName': 'CostPerRegion',
                    'Value': float(cost),
                    'Unit': 'None',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Region', 'Value': region}
                    ]
                })
            
            if region_metrics:
                for i in range(0, len(region_metrics), 20):
                    batch = region_metrics[i:i+20]
                    self.cloudwatch.put_metric_data(
                        Namespace=namespace,
                        MetricData=batch
                    )
            
            logger.info(f"Published cost metrics to CloudWatch: ${float(total_cost):.2f} total")
            
        except Exception as e:
            logger.error(f"Failed to publish cost metrics: {str(e)}")
            # Don't raise - metrics publishing failure shouldn't stop the analysis
    
    def generate_monthly_trend_report(self) -> Dict[str, Any]:
        """
        Generate monthly cost trend report with historical data.
        
        Returns:
            dict: Monthly trend report with 30-day history
        """
        try:
            # Get last 30 days of snapshots
            snapshots = self._get_recent_snapshots(days=30)
            
            if not snapshots:
                logger.warn("No historical snapshots found for trend report")
                return {}
            
            # Calculate daily costs
            daily_costs = [
                {
                    'date': s['snapshot_date'],
                    'cost': s.get('total_monthly_cost', 0),
                    'instance_count': s.get('instance_count', 0)
                }
                for s in snapshots
            ]
            
            # Sort by date
            daily_costs.sort(key=lambda x: x['date'])
            
            # Calculate statistics
            costs = [d['cost'] for d in daily_costs]
            avg_cost = sum(costs) / len(costs) if costs else 0
            min_cost = min(costs) if costs else 0
            max_cost = max(costs) if costs else 0
            
            trend_report = {
                'report_type': 'monthly_trend',
                'generated_at': datetime.utcnow().isoformat() + 'Z',
                'period_days': len(daily_costs),
                'start_date': daily_costs[0]['date'] if daily_costs else None,
                'end_date': daily_costs[-1]['date'] if daily_costs else None,
                'statistics': {
                    'average_cost': round(avg_cost, 2),
                    'minimum_cost': round(min_cost, 2),
                    'maximum_cost': round(max_cost, 2),
                    'cost_variance': round(max_cost - min_cost, 2)
                },
                'daily_costs': daily_costs,
                'cost_trends': self.calculate_cost_trends()
            }
            
            logger.info(f"Generated monthly trend report: {len(daily_costs)} days, avg ${avg_cost:.2f}")
            
            return trend_report
            
        except Exception as e:
            logger.error(f"Failed to generate monthly trend report: {str(e)}")
            return {}
    
    def save_trend_report_to_s3(self, trend_report: Dict[str, Any]) -> str:
        """
        Save monthly trend report to S3.
        
        Args:
            trend_report: Monthly trend report data
            
        Returns:
            str: S3 key where report was saved
        """
        bucket_name = self.config.get('s3_bucket', 'rds-dashboard-data')
        report_date = datetime.utcnow().strftime('%Y-%m-%d')
        year, month, day = report_date.split('-')
        
        # S3 key: cost-reports/YYYY/MM/cost_trend_YYYY-MM-DD.json
        s3_key = f"cost-reports/{year}/{month}/cost_trend_{report_date}.json"
        
        try:
            report_json = json.dumps(trend_report, indent=2, default=str)
            
            self.s3.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=report_json.encode('utf-8'),
                ContentType='application/json',
                ServerSideEncryption='AES256',
                Metadata={
                    'report-date': report_date,
                    'report-type': 'monthly-trend',
                    'generated-by': 'cost-analyzer',
                    'version': '1.0.0'
                }
            )
            
            logger.info(f"Saved trend report to s3://{bucket_name}/{s3_key}")
            return s3_key
            
        except Exception as e:
            logger.error(f"Failed to save trend report to S3: {str(e)}")
            raise
    
    def _get_snapshot_by_date(self, snapshot_date: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve cost snapshot for a specific date.
        
        Args:
            snapshot_date: Date in YYYY-MM-DD format
            
        Returns:
            dict: Snapshot data or None if not found
        """
        try:
            response = self.dynamodb.get_item(
                TableName=self.cost_snapshots_table,
                Key={'snapshot_date': {'S': snapshot_date}}
            )
            
            if 'Item' in response:
                return self._convert_from_dynamodb_item(response['Item'])
            return None
            
        except Exception as e:
            logger.warn(f"Failed to get snapshot for {snapshot_date}: {str(e)}")
            return None
    
    def _get_recent_snapshots(self, days: int = 30) -> List[Dict[str, Any]]:
        """
        Retrieve recent cost snapshots.
        
        Args:
            days: Number of days to retrieve
            
        Returns:
            list: List of snapshot data
        """
        try:
            # Calculate date range
            end_date = datetime.utcnow()
            start_date = end_date - timedelta(days=days)
            
            # Query snapshots (assuming we have a GSI or scan)
            # For simplicity, we'll scan with a filter
            response = self.dynamodb.scan(
                TableName=self.cost_snapshots_table,
                FilterExpression='snapshot_date >= :start_date',
                ExpressionAttributeValues={
                    ':start_date': {'S': start_date.strftime('%Y-%m-%d')}
                }
            )
            
            snapshots = []
            if 'Items' in response:
                for item in response['Items']:
                    snapshots.append(self._convert_from_dynamodb_item(item))
            
            return snapshots
            
        except Exception as e:
            logger.error(f"Failed to get recent snapshots: {str(e)}")
            return []
    
    def _convert_to_dynamodb_item(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert Python dict to DynamoDB item format."""
        from boto3.dynamodb.types import TypeSerializer
        serializer = TypeSerializer()
        return {k: serializer.serialize(v) for k, v in data.items()}
    
    def _convert_from_dynamodb_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """Convert DynamoDB item to Python dict."""
        from boto3.dynamodb.types import TypeDeserializer
        deserializer = TypeDeserializer()
        return {k: deserializer.deserialize(v) for k, v in item.items()}
