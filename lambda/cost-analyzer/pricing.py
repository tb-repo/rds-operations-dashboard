#!/usr/bin/env python3
"""
RDS Pricing Calculator

Calculates monthly costs for RDS instances based on AWS Pricing API data.
Includes compute, storage, IOPS, and backup costs.
"""

import os
import sys
import json
from decimal import Decimal
from typing import Dict, Any, Optional
import boto3

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger

logger = get_logger(__name__)


class RDSPricingCalculator:
    """Calculate RDS instance costs using AWS Pricing API."""
    
    # Simplified pricing data (USD per month)
    # In production, this would query AWS Pricing API
    PRICING_DATA = {
        # Compute pricing per hour by instance class (approximate)
        'compute': {
            'db.t3.micro': 0.017,
            'db.t3.small': 0.034,
            'db.t3.medium': 0.068,
            'db.t3.large': 0.136,
            'db.t3.xlarge': 0.272,
            'db.t3.2xlarge': 0.544,
            'db.r6g.large': 0.24,
            'db.r6g.xlarge': 0.48,
            'db.r6g.2xlarge': 0.96,
            'db.r6g.4xlarge': 1.92,
            'db.r6g.8xlarge': 3.84,
            'db.r6g.12xlarge': 5.76,
            'db.r6g.16xlarge': 7.68,
            'db.r5.large': 0.25,
            'db.r5.xlarge': 0.50,
            'db.r5.2xlarge': 1.00,
            'db.r5.4xlarge': 2.00,
            'db.r5.8xlarge': 4.00,
            'db.r5.12xlarge': 6.00,
            'db.r5.16xlarge': 8.00,
            'db.m5.large': 0.192,
            'db.m5.xlarge': 0.384,
            'db.m5.2xlarge': 0.768,
            'db.m5.4xlarge': 1.536,
            'db.m5.8xlarge': 3.072,
        },
        # Storage pricing per GB-month
        'storage': {
            'gp2': 0.115,  # General Purpose SSD
            'gp3': 0.08,   # General Purpose SSD (gp3)
            'io1': 0.125,  # Provisioned IOPS SSD
            'io2': 0.125,  # Provisioned IOPS SSD (io2)
            'standard': 0.10,  # Magnetic
        },
        # IOPS pricing per IOPS-month (for io1/io2)
        'iops': 0.10,
        # Backup storage pricing per GB-month (beyond free tier)
        'backup': 0.095,
        # Multi-AZ multiplier
        'multi_az_multiplier': 2.0,
        # Regional pricing adjustments (Singapore is baseline)
        'regional_multiplier': {
            'ap-southeast-1': 1.0,    # Singapore (baseline)
            'eu-west-2': 1.05,        # London
            'ap-south-1': 0.95,       # Mumbai
            'us-east-1': 0.90,        # US East
            'us-west-2': 0.95,        # US West
        }
    }
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize pricing calculator.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.hours_per_month = 730  # Average hours per month
    
    def calculate_instance_cost(self, instance: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculate monthly cost for an RDS instance.
        
        Args:
            instance: RDS instance data from inventory
            
        Returns:
            dict: Cost breakdown with monthly total
        """
        instance_id = instance.get('instance_id', 'unknown')
        instance_class = instance.get('instance_class', 'db.t3.micro')
        storage_type = instance.get('storage_type', 'gp2')
        allocated_storage = instance.get('allocated_storage', 100)
        iops = instance.get('iops', 0)
        multi_az = instance.get('multi_az', False)
        region = instance.get('region', 'ap-southeast-1')
        engine = instance.get('engine', 'postgres')
        backup_retention = instance.get('backup_retention_period', 7)
        
        # Get regional multiplier
        regional_multiplier = self.PRICING_DATA['regional_multiplier'].get(region, 1.0)
        
        # Calculate compute cost
        compute_hourly = self.PRICING_DATA['compute'].get(instance_class, 0.10)
        compute_monthly = compute_hourly * self.hours_per_month * regional_multiplier
        
        # Apply Multi-AZ multiplier to compute
        if multi_az:
            compute_monthly *= self.PRICING_DATA['multi_az_multiplier']
        
        # Calculate storage cost
        storage_rate = self.PRICING_DATA['storage'].get(storage_type, 0.115)
        storage_monthly = allocated_storage * storage_rate * regional_multiplier
        
        # Apply Multi-AZ multiplier to storage
        if multi_az:
            storage_monthly *= self.PRICING_DATA['multi_az_multiplier']
        
        # Calculate IOPS cost (for io1/io2 only)
        iops_monthly = 0
        if storage_type in ['io1', 'io2'] and iops > 0:
            iops_monthly = iops * self.PRICING_DATA['iops'] * regional_multiplier
            if multi_az:
                iops_monthly *= self.PRICING_DATA['multi_az_multiplier']
        
        # Calculate backup cost (simplified - assumes backup size = allocated storage)
        # First 100% of DB size is free, additional backups charged
        backup_storage_gb = allocated_storage * max(0, backup_retention - 1) / 7
        backup_monthly = backup_storage_gb * self.PRICING_DATA['backup'] * regional_multiplier
        
        # Total monthly cost
        monthly_cost = compute_monthly + storage_monthly + iops_monthly + backup_monthly
        
        cost_data = {
            'instance_id': instance_id,
            'account_id': instance.get('account_id', 'unknown'),
            'region': region,
            'engine': engine,
            'instance_class': instance_class,
            'storage_type': storage_type,
            'allocated_storage': allocated_storage,
            'multi_az': multi_az,
            'monthly_cost': round(monthly_cost, 2),
            'cost_breakdown': {
                'compute': round(compute_monthly, 2),
                'storage': round(storage_monthly, 2),
                'iops': round(iops_monthly, 2),
                'backup': round(backup_monthly, 2)
            },
            'regional_multiplier': regional_multiplier,
            'calculated_at': instance.get('last_discovered', '')
        }
        
        logger.debug(f"Calculated cost for {instance_id}: ${monthly_cost:.2f}/month")
        
        return cost_data
    
    def get_reserved_instance_pricing(
        self,
        instance_class: str,
        region: str,
        term_years: int = 1
    ) -> Optional[float]:
        """
        Get reserved instance pricing (simplified).
        
        In production, this would query AWS Pricing API for RI pricing.
        
        Args:
            instance_class: RDS instance class
            region: AWS region
            term_years: RI term (1 or 3 years)
            
        Returns:
            float: Monthly RI cost, or None if not available
        """
        # Simplified: RI typically saves 30-40% vs on-demand
        on_demand_hourly = self.PRICING_DATA['compute'].get(instance_class)
        if not on_demand_hourly:
            return None
        
        discount = 0.35 if term_years == 1 else 0.50  # 35% for 1yr, 50% for 3yr
        ri_hourly = on_demand_hourly * (1 - discount)
        ri_monthly = ri_hourly * self.hours_per_month
        
        regional_multiplier = self.PRICING_DATA['regional_multiplier'].get(region, 1.0)
        return round(ri_monthly * regional_multiplier, 2)
