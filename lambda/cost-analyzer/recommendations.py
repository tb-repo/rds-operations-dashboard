#!/usr/bin/env python3
"""
Recommendation Engine

Generates cost optimization recommendations based on utilization patterns
and pricing data.
"""

import os
import sys
from typing import Dict, List, Any, Optional
from decimal import Decimal

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger
from pricing import RDSPricingCalculator

logger = get_logger(__name__)


class RecommendationEngine:
    """Generate cost optimization recommendations."""
    
    # Instance class families for right-sizing
    INSTANCE_FAMILIES = {
        't3': ['db.t3.micro', 'db.t3.small', 'db.t3.medium', 'db.t3.large', 'db.t3.xlarge', 'db.t3.2xlarge'],
        'r6g': ['db.r6g.large', 'db.r6g.xlarge', 'db.r6g.2xlarge', 'db.r6g.4xlarge', 'db.r6g.8xlarge'],
        'r5': ['db.r5.large', 'db.r5.xlarge', 'db.r5.2xlarge', 'db.r5.4xlarge', 'db.r5.8xlarge'],
        'm5': ['db.m5.large', 'db.m5.xlarge', 'db.m5.2xlarge', 'db.m5.4xlarge', 'db.m5.8xlarge'],
    }
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize recommendation engine.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.pricing_calculator = RDSPricingCalculator(config)
    
    def generate_recommendations(
        self,
        instances: List[Dict[str, Any]],
        instance_costs: List[Dict[str, Any]],
        utilization_data: Dict[str, Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """
        Generate optimization recommendations for all instances.
        
        Args:
            instances: List of RDS instances
            instance_costs: List of cost data
            utilization_data: Utilization analysis results
            
        Returns:
            list: List of recommendations
        """
        recommendations = []
        
        # Create lookup dicts
        cost_lookup = {c['instance_id']: c for c in instance_costs}
        instance_lookup = {i['instance_id']: i for i in instances}
        
        for instance_id, utilization in utilization_data.items():
            instance = instance_lookup.get(instance_id)
            cost_data = cost_lookup.get(instance_id)
            
            if not instance or not cost_data:
                continue
            
            # Generate right-sizing recommendations
            if utilization['is_underutilized'] or utilization['is_oversized']:
                rec = self._generate_rightsizing_recommendation(
                    instance,
                    cost_data,
                    utilization
                )
                if rec:
                    recommendations.append(rec)
            
            # Generate reserved instance recommendations
            if self._should_recommend_reserved_instance(instance, utilization):
                rec = self._generate_reserved_instance_recommendation(
                    instance,
                    cost_data
                )
                if rec:
                    recommendations.append(rec)
            
            # Generate storage optimization recommendations
            if self._should_optimize_storage(instance, utilization):
                rec = self._generate_storage_optimization_recommendation(
                    instance,
                    cost_data
                )
                if rec:
                    recommendations.append(rec)
        
        logger.info(f"Generated {len(recommendations)} recommendations")
        return recommendations
    
    def _generate_rightsizing_recommendation(
        self,
        instance: Dict[str, Any],
        cost_data: Dict[str, Any],
        utilization: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Generate right-sizing recommendation.
        
        Args:
            instance: RDS instance data
            cost_data: Cost data
            utilization: Utilization analysis
            
        Returns:
            dict: Recommendation, or None
        """
        instance_id = instance['instance_id']
        current_class = instance['instance_class']
        current_cost = cost_data['monthly_cost']
        
        # Determine target instance class
        target_class = self._suggest_instance_class(current_class, utilization)
        
        if not target_class or target_class == current_class:
            return None
        
        # Calculate cost savings
        target_instance = instance.copy()
        target_instance['instance_class'] = target_class
        target_cost_data = self.pricing_calculator.calculate_instance_cost(target_instance)
        target_cost = target_cost_data['monthly_cost']
        
        savings = current_cost - target_cost
        savings_pct = (savings / current_cost * 100) if current_cost > 0 else 0
        
        if savings <= 0:
            return None
        
        recommendation = {
            'instance_id': instance_id,
            'type': 'rightsizing',
            'priority': 'high' if savings > 100 else 'medium',
            'current_instance_class': current_class,
            'recommended_instance_class': target_class,
            'current_monthly_cost': current_cost,
            'estimated_monthly_cost': target_cost,
            'estimated_monthly_savings': round(savings, 2),
            'savings_percentage': round(savings_pct, 1),
            'rationale': self._build_rightsizing_rationale(utilization),
            'risk_level': 'low',
            'implementation_effort': 'medium',
            'downtime_required': True,
            'estimated_downtime_minutes': 5
        }
        
        logger.info(f"Right-sizing recommendation for {instance_id}: {current_class} → {target_class} (save ${savings:.2f}/month)")
        
        return recommendation
    
    def _suggest_instance_class(
        self,
        current_class: str,
        utilization: Dict[str, Any]
    ) -> Optional[str]:
        """
        Suggest target instance class based on utilization.
        
        Args:
            current_class: Current instance class
            utilization: Utilization data
            
        Returns:
            str: Suggested instance class, or None
        """
        # Determine instance family
        family = current_class.split('.')[1] if '.' in current_class else None
        if not family or family not in self.INSTANCE_FAMILIES:
            return None
        
        family_classes = self.INSTANCE_FAMILIES[family]
        current_index = family_classes.index(current_class) if current_class in family_classes else -1
        
        if current_index == -1:
            return None
        
        # If underutilized, suggest one size smaller
        if utilization['is_underutilized'] and current_index > 0:
            return family_classes[current_index - 1]
        
        # If oversized (low connections), suggest two sizes smaller
        if utilization['is_oversized'] and current_index > 1:
            return family_classes[current_index - 2]
        
        # If memory pressure, suggest one size larger
        if utilization['has_memory_pressure'] and current_index < len(family_classes) - 1:
            return family_classes[current_index + 1]
        
        return None
    
    def _build_rightsizing_rationale(self, utilization: Dict[str, Any]) -> str:
        """
        Build rationale text for right-sizing recommendation.
        
        Args:
            utilization: Utilization data
            
        Returns:
            str: Rationale text
        """
        reasons = []
        
        if utilization['is_underutilized']:
            reasons.append(f"Average CPU utilization is {utilization['avg_cpu']:.1f}% (below 20% threshold)")
        
        if utilization['is_oversized']:
            reasons.append(f"Average database connections is {utilization['avg_connections']:.0f} (below 10 threshold)")
        
        if utilization['has_memory_pressure']:
            reasons.append(f"Average free memory is {utilization['avg_free_memory_pct']:.1f}% (below 20% threshold)")
        
        return ". ".join(reasons) + "."
    
    def _should_recommend_reserved_instance(
        self,
        instance: Dict[str, Any],
        utilization: Dict[str, Any]
    ) -> bool:
        """
        Determine if reserved instance should be recommended.
        
        Args:
            instance: RDS instance data
            utilization: Utilization data
            
        Returns:
            bool: True if RI should be recommended
        """
        # Recommend RI for production instances with good utilization
        is_production = instance.get('tags', {}).get('Environment', '').lower() == 'production'
        is_well_utilized = utilization['utilization_score'] > 50
        
        return is_production and is_well_utilized
    
    def _generate_reserved_instance_recommendation(
        self,
        instance: Dict[str, Any],
        cost_data: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Generate reserved instance recommendation.
        
        Args:
            instance: RDS instance data
            cost_data: Cost data
            
        Returns:
            dict: Recommendation, or None
        """
        instance_id = instance['instance_id']
        instance_class = instance['instance_class']
        region = instance['region']
        current_cost = cost_data['monthly_cost']
        
        # Get RI pricing (1-year term)
        ri_cost = self.pricing_calculator.get_reserved_instance_pricing(
            instance_class,
            region,
            term_years=1
        )
        
        if not ri_cost:
            return None
        
        savings = current_cost - ri_cost
        savings_pct = (savings / current_cost * 100) if current_cost > 0 else 0
        
        if savings <= 0:
            return None
        
        recommendation = {
            'instance_id': instance_id,
            'type': 'reserved_instance',
            'priority': 'medium',
            'current_monthly_cost': current_cost,
            'estimated_monthly_cost': ri_cost,
            'estimated_monthly_savings': round(savings, 2),
            'savings_percentage': round(savings_pct, 1),
            'ri_term': '1-year',
            'payment_option': 'No Upfront',
            'rationale': f"Production instance with consistent usage. Reserved Instance can save ${savings:.2f}/month ({savings_pct:.0f}%).",
            'risk_level': 'low',
            'implementation_effort': 'low',
            'downtime_required': False
        }
        
        logger.info(f"Reserved Instance recommendation for {instance_id}: save ${savings:.2f}/month")
        
        return recommendation
    
    def _should_optimize_storage(
        self,
        instance: Dict[str, Any],
        utilization: Dict[str, Any]
    ) -> bool:
        """
        Determine if storage optimization should be recommended.
        
        Args:
            instance: RDS instance data
            utilization: Utilization data
            
        Returns:
            bool: True if storage optimization recommended
        """
        storage_type = instance.get('storage_type', 'gp2')
        
        # Recommend gp3 upgrade for gp2 volumes (cost savings + better performance)
        return storage_type == 'gp2'
    
    def _generate_storage_optimization_recommendation(
        self,
        instance: Dict[str, Any],
        cost_data: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Generate storage optimization recommendation.
        
        Args:
            instance: RDS instance data
            cost_data: Cost data
            
        Returns:
            dict: Recommendation, or None
        """
        instance_id = instance['instance_id']
        current_storage_type = instance.get('storage_type', 'gp2')
        
        if current_storage_type != 'gp2':
            return None
        
        # Calculate savings from gp2 → gp3
        allocated_storage = instance.get('allocated_storage', 100)
        gp2_cost = allocated_storage * 0.115
        gp3_cost = allocated_storage * 0.08
        savings = gp2_cost - gp3_cost
        savings_pct = (savings / gp2_cost * 100) if gp2_cost > 0 else 0
        
        recommendation = {
            'instance_id': instance_id,
            'type': 'storage_optimization',
            'priority': 'low',
            'current_storage_type': 'gp2',
            'recommended_storage_type': 'gp3',
            'estimated_monthly_savings': round(savings, 2),
            'savings_percentage': round(savings_pct, 1),
            'rationale': f"Upgrade from gp2 to gp3 for better performance and ${savings:.2f}/month savings.",
            'risk_level': 'low',
            'implementation_effort': 'low',
            'downtime_required': False
        }
        
        logger.info(f"Storage optimization recommendation for {instance_id}: gp2 → gp3 (save ${savings:.2f}/month)")
        
        return recommendation
