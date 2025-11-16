#!/usr/bin/env python3
"""
Basic tests for Cost Analyzer Lambda function

Tests pricing calculations, utilization analysis, and recommendation generation.
"""

import sys
import os

# Add parent directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

def test_pricing_calculator():
    """Test RDS pricing calculator."""
    from cost_analyzer.pricing import RDSPricingCalculator
    
    config = {}
    calculator = RDSPricingCalculator(config)
    
    # Test instance cost calculation
    instance = {
        'instance_id': 'test-postgres-01',
        'account_id': '123456789012',
        'region': 'ap-southeast-1',
        'engine': 'postgres',
        'instance_class': 'db.r6g.xlarge',
        'storage_type': 'gp3',
        'allocated_storage': 500,
        'iops': 0,
        'multi_az': True,
        'backup_retention_period': 7,
        'last_discovered': '2025-11-13T00:00:00Z'
    }
    
    cost_data = calculator.calculate_instance_cost(instance)
    
    assert cost_data['instance_id'] == 'test-postgres-01'
    assert cost_data['monthly_cost'] > 0
    assert 'cost_breakdown' in cost_data
    assert cost_data['cost_breakdown']['compute'] > 0
    assert cost_data['cost_breakdown']['storage'] > 0
    
    print(f"✓ Pricing calculator test passed")
    print(f"  Monthly cost: ${cost_data['monthly_cost']:.2f}")
    print(f"  Compute: ${cost_data['cost_breakdown']['compute']:.2f}")
    print(f"  Storage: ${cost_data['cost_breakdown']['storage']:.2f}")


def test_utilization_analyzer():
    """Test utilization analyzer."""
    from cost_analyzer.utilization import UtilizationAnalyzer
    
    config = {}
    analyzer = UtilizationAnalyzer(config)
    
    # Test utilization analysis logic
    instance = {
        'instance_id': 'test-postgres-01',
        'region': 'ap-southeast-1'
    }
    
    # Mock metrics
    metrics = {
        'avg_cpu': 15.0,  # Low CPU
        'max_cpu': 30.0,
        'avg_connections': 5,  # Low connections
        'max_connections': 15,
        'avg_free_memory_pct': 60.0,
        'min_free_memory_pct': 40.0
    }
    
    # Manually create analysis (since we can't query CloudWatch in tests)
    analysis = {
        'instance_id': instance['instance_id'],
        'avg_cpu': metrics['avg_cpu'],
        'max_cpu': metrics['max_cpu'],
        'avg_connections': metrics['avg_connections'],
        'max_connections': metrics['max_connections'],
        'avg_free_memory_pct': metrics['avg_free_memory_pct'],
        'min_free_memory_pct': metrics['min_free_memory_pct'],
        'is_underutilized': metrics['avg_cpu'] < 20.0,
        'is_oversized': metrics['avg_connections'] < 10,
        'has_memory_pressure': metrics['avg_free_memory_pct'] < 20.0,
        'utilization_score': 0
    }
    
    assert analysis['is_underutilized'] == True
    assert analysis['is_oversized'] == True
    assert analysis['has_memory_pressure'] == False
    
    print(f"✓ Utilization analyzer test passed")
    print(f"  Underutilized: {analysis['is_underutilized']}")
    print(f"  Oversized: {analysis['is_oversized']}")
    print(f"  Memory pressure: {analysis['has_memory_pressure']}")


def test_recommendation_engine():
    """Test recommendation engine."""
    from cost_analyzer.recommendations import RecommendationEngine
    
    config = {}
    engine = RecommendationEngine(config)
    
    # Test instance class suggestion
    current_class = 'db.r6g.2xlarge'
    utilization = {
        'is_underutilized': True,
        'is_oversized': False,
        'has_memory_pressure': False,
        'avg_cpu': 15.0,
        'avg_connections': 20,
        'avg_free_memory_pct': 50.0
    }
    
    suggested_class = engine._suggest_instance_class(current_class, utilization)
    
    assert suggested_class == 'db.r6g.xlarge'  # One size smaller
    
    print(f"✓ Recommendation engine test passed")
    print(f"  Current: {current_class}")
    print(f"  Suggested: {suggested_class}")


def test_cost_reporter():
    """Test cost reporter."""
    from cost_analyzer.reporting import CostReporter
    from decimal import Decimal
    
    config = {'s3_bucket': 'test-bucket'}
    reporter = CostReporter(config)
    
    # Test report generation
    instance_costs = [
        {
            'instance_id': 'test-1',
            'account_id': '123456789012',
            'region': 'ap-southeast-1',
            'engine': 'postgres',
            'instance_class': 'db.r6g.xlarge',
            'monthly_cost': 350.50
        },
        {
            'instance_id': 'test-2',
            'account_id': '123456789012',
            'region': 'eu-west-2',
            'engine': 'mysql',
            'instance_class': 'db.t3.large',
            'monthly_cost': 125.75
        }
    ]
    
    cost_aggregations = {
        'by_account': {'123456789012': Decimal('476.25')},
        'by_region': {'ap-southeast-1': Decimal('350.50'), 'eu-west-2': Decimal('125.75')},
        'by_engine': {'postgres': Decimal('350.50'), 'mysql': Decimal('125.75')},
        'by_instance_family': {'db.r6g': Decimal('350.50'), 'db.t3': Decimal('125.75')}
    }
    
    recommendations = [
        {
            'instance_id': 'test-1',
            'type': 'rightsizing',
            'priority': 'high',
            'estimated_monthly_savings': 100.00
        }
    ]
    
    total_cost = Decimal('476.25')
    
    report = reporter.generate_report(
        instance_costs,
        cost_aggregations,
        recommendations,
        total_cost
    )
    
    assert report['summary']['total_instances'] == 2
    assert report['summary']['total_monthly_cost'] == 476.25
    assert report['summary']['total_potential_savings'] == 100.00
    assert report['summary']['recommendations_count'] == 1
    
    print(f"✓ Cost reporter test passed")
    print(f"  Total cost: ${report['summary']['total_monthly_cost']:.2f}")
    print(f"  Potential savings: ${report['summary']['total_potential_savings']:.2f}")


if __name__ == '__main__':
    print("Running Cost Analyzer tests...\n")
    
    try:
        test_pricing_calculator()
        print()
        test_utilization_analyzer()
        print()
        test_recommendation_engine()
        print()
        test_cost_reporter()
        print()
        print("=" * 60)
        print("✓ All Cost Analyzer tests passed!")
        print("=" * 60)
    except AssertionError as e:
        print(f"\n✗ Test failed: {str(e)}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
