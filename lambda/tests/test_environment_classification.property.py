#!/usr/bin/env python3
"""
Property-Based Tests for Automatic Environment Classification

Property 6: Automatic Environment Classification
Validates: Requirements 3.3, 3.5

Tests that the system automatically classifies RDS instance environments
correctly based on tags, naming patterns, and account mappings.

Governance Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-01-17T00:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.1.0",
  "traceability": "REQ-3.3, REQ-3.5 → DESIGN-001 → TASK-6.4",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
from hypothesis import given, strategies as st, settings, assume
import re
from typing import Dict, Any, List
import sys
import os

# Add parent directories to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from shared.environment_classifier import EnvironmentClassifier


# Test data generators
@st.composite
def environment_tags(draw):
    """Generate various environment tag configurations."""
    tag_name = draw(st.sampled_from(['Environment', 'Env', 'ENV', 'environment', 'env', 'Stage', 'STAGE']))
    environment = draw(st.sampled_from(['production', 'development', 'test', 'staging', 'poc', 'sandbox']))
    return {tag_name: environment}


@st.composite
def instance_with_naming_pattern(draw):
    """Generate instance names that follow specific naming patterns."""
    environment = draw(st.sampled_from(['production', 'development', 'test', 'staging', 'poc', 'sandbox']))
    
    patterns = {
        'production': ['prod-', 'prd-', 'p-', '-prod', '-prd', '-production'],
        'development': ['dev-', 'development-', '-dev', '-development'],
        'test': ['test-', 'tst-', 'qa-', '-test', '-tst', '-qa'],
        'staging': ['stg-', 'staging-', 'stage-', '-stg', '-staging'],
        'poc': ['poc-', 'demo-', 'exp-', 'experiment-', '-poc', '-demo'],
        'sandbox': ['sandbox-', 'sbx-', '-sandbox', '-sbx']
    }
    
    pattern = draw(st.sampled_from(patterns[environment]))
    base_name = draw(st.text(min_size=3, max_size=15, alphabet=st.characters(whitelist_categories=('Ll', 'Lu', 'Nd'))))
    
    if pattern.startswith('-'):
        instance_name = base_name + pattern
    else:
        instance_name = pattern + base_name
    
    return {
        'instance_id': instance_name,
        'expected_environment': environment,
        'account_id': '123456789012',
        'region': 'us-east-1',
        'tags': {}
    }


@st.composite
def account_mapping_config(draw):
    """Generate account mapping configurations."""
    accounts = draw(st.lists(
        st.text(min_size=12, max_size=12, alphabet='0123456789'),
        min_size=1, max_size=5, unique=True
    ))
    
    environments = ['production', 'development', 'test', 'staging']
    
    mapping = {}
    for account in accounts:
        mapping[account] = draw(st.sampled_from(environments))
    
    return mapping


class TestEnvironmentClassification:
    """Property-based tests for automatic environment classification."""
    
    @given(environment_tags())
    @settings(max_examples=100, deadline=3000)
    def test_aws_tags_classification_priority(self, tags):
        """
        Property 6a: AWS tags have highest classification priority.
        
        For any instance with environment tags, the tag value should be used
        regardless of other classification methods.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment', 'Env', 'ENV', 'environment', 'env', 'Stage', 'STAGE'],
            'naming_patterns': {
                'production': ['^prod-'],  # Conflicting pattern
                'development': ['^dev-']
            },
            'account_mappings': {
                '123456789012': 'staging'  # Conflicting account mapping
            }
        }
        
        classifier = EnvironmentClassifier(config)
        
        # Create instance with conflicting indicators
        instance = {
            'instance_id': 'prod-conflicting-name',  # Suggests production via naming
            'account_id': '123456789012',  # Mapped to staging
            'region': 'us-east-1',
            'tags': tags
        }
        
        environment = classifier.get_environment(instance)
        source = classifier.get_classification_source(instance)
        
        # AWS tag should win
        expected_env = list(tags.values())[0].lower()
        assert environment == expected_env
        assert source == 'aws_tag'
    
    @given(instance_with_naming_pattern())
    @settings(max_examples=100, deadline=3000)
    def test_naming_pattern_classification(self, instance_data):
        """
        Property 6b: Naming patterns classify environments correctly.
        
        For any instance name following a naming pattern, the environment
        should be classified based on the pattern match.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {
                'production': ['^prod-', '^prd-', '^p-', '-prod$', '-prd$', '-production$'],
                'development': ['^dev-', '^development-', '-dev$', '-development$'],
                'test': ['^test-', '^tst-', '^qa-', '-test$', '-tst$', '-qa$'],
                'staging': ['^stg-', '^staging-', '^stage-', '-stg$', '-staging$'],
                'poc': ['^poc-', '^demo-', '^exp-', '^experiment-', '-poc$', '-demo$'],
                'sandbox': ['^sandbox-', '^sbx-', '-sandbox$', '-sbx$']
            },
            'account_mappings': {},
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        environment = classifier.get_environment(instance_data)
        source = classifier.get_classification_source(instance_data)
        
        assert environment == instance_data['expected_environment']
        assert source == 'naming_pattern'
    
    @given(account_mapping_config())
    @settings(max_examples=50, deadline=3000)
    def test_account_mapping_classification(self, account_mappings):
        """
        Property 6c: Account mappings classify environments correctly.
        
        For any account mapping configuration, instances in mapped accounts
        should be classified according to the mapping.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {},
            'account_mappings': account_mappings,
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        for account_id, expected_env in account_mappings.items():
            instance = {
                'instance_id': 'neutral-db-name',  # No naming pattern
                'account_id': account_id,
                'region': 'us-east-1',
                'tags': {}  # No environment tags
            }
            
            environment = classifier.get_environment(instance)
            source = classifier.get_classification_source(instance)
            
            assert environment == expected_env.lower()
            assert source == 'account_mapping'
    
    @given(st.dictionaries(
        st.text(min_size=5, max_size=20, alphabet=st.characters(whitelist_categories=('Ll', 'Lu', 'Nd'), whitelist_characters='-_')),
        st.sampled_from(['production', 'development', 'test', 'staging']),
        min_size=1, max_size=5
    ))
    @settings(max_examples=50, deadline=3000)
    def test_manual_instance_mapping_classification(self, instance_mappings):
        """
        Property 6d: Manual instance mappings override other methods.
        
        For any manual instance mapping, the mapped environment should be used
        over naming patterns and account mappings.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {
                'production': ['^prod-'],  # Conflicting pattern
            },
            'account_mappings': {
                '123456789012': 'development'  # Conflicting account mapping
            },
            'instance_mappings': instance_mappings
        }
        
        classifier = EnvironmentClassifier(config)
        
        for instance_id, expected_env in instance_mappings.items():
            instance = {
                'instance_id': instance_id,
                'account_id': '123456789012',  # Has conflicting account mapping
                'region': 'us-east-1',
                'tags': {}  # No environment tags
            }
            
            environment = classifier.get_environment(instance)
            source = classifier.get_classification_source(instance)
            
            assert environment == expected_env.lower()
            assert source == 'manual_mapping'
    
    @given(st.text(min_size=5, max_size=30, alphabet=st.characters(whitelist_categories=('Ll', 'Lu', 'Nd'), whitelist_characters='-_')))
    @settings(max_examples=100, deadline=3000)
    def test_default_environment_fallback(self, instance_name):
        """
        Property 6e: Default environment is used when no other method matches.
        
        For any instance that doesn't match tags, patterns, or mappings,
        the default environment should be used.
        """
        # Ensure the instance name doesn't match any patterns
        assume(not re.search(r'^(prod|prd|p|dev|test|tst|qa|stg|staging|stage|poc|demo|exp|experiment|sandbox|sbx)-', instance_name, re.IGNORECASE))
        assume(not re.search(r'-(prod|prd|production|dev|development|test|tst|qa|stg|staging|poc|demo|sandbox|sbx)$', instance_name, re.IGNORECASE))
        
        default_env = 'custom-default'
        config = {
            'default_environment': default_env,
            'environment_tag_names': ['Environment'],
            'naming_patterns': {
                'production': ['^prod-', '^prd-', '^p-', '-prod$', '-prd$', '-production$'],
                'development': ['^dev-', '^development-', '-dev$', '-development$'],
                'test': ['^test-', '^tst-', '^qa-', '-test$', '-tst$', '-qa$'],
                'staging': ['^stg-', '^staging-', '^stage-', '-stg$', '-staging$'],
                'poc': ['^poc-', '^demo-', '^exp-', '^experiment-', '-poc$', '-demo$'],
                'sandbox': ['^sandbox-', '^sbx-', '-sandbox$', '-sbx$']
            },
            'account_mappings': {},
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        instance = {
            'instance_id': instance_name,
            'account_id': '999999999999',  # Not in account mappings
            'region': 'us-east-1',
            'tags': {}  # No environment tags
        }
        
        environment = classifier.get_environment(instance)
        source = classifier.get_classification_source(instance)
        
        assert environment == default_env
        assert source == 'default'
    
    @given(st.sampled_from(['Environment', 'Env', 'ENV', 'environment', 'env', 'Stage', 'STAGE']))
    @settings(max_examples=20, deadline=3000)
    def test_flexible_tag_name_matching(self, tag_name):
        """
        Property 6f: Flexible tag name matching works with various tag formats.
        
        For any supported environment tag name format, the classifier should
        recognize and use the tag value.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment', 'Env', 'ENV', 'environment', 'env', 'Stage', 'STAGE'],
            'naming_patterns': {},
            'account_mappings': {},
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        instance = {
            'instance_id': 'test-instance',
            'account_id': '123456789012',
            'region': 'us-east-1',
            'tags': {tag_name: 'production'}
        }
        
        environment = classifier.get_environment(instance)
        source = classifier.get_classification_source(instance)
        
        assert environment == 'production'
        assert source == 'aws_tag'
    
    def test_classification_priority_order(self):
        """
        Property 6g: Classification methods follow correct priority order.
        
        The classification should follow the priority:
        1. AWS tags, 2. Manual mapping, 3. Account mapping, 4. Naming pattern, 5. Default
        """
        config = {
            'default_environment': 'default-env',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {
                'production': ['^prod-']
            },
            'account_mappings': {
                '123456789012': 'account-env'
            },
            'instance_mappings': {
                'prod-test-db': 'manual-env'
            }
        }
        
        classifier = EnvironmentClassifier(config)
        
        # Test priority 1: AWS tags (should override everything)
        instance_with_tag = {
            'instance_id': 'prod-test-db',  # Has manual mapping and naming pattern
            'account_id': '123456789012',   # Has account mapping
            'region': 'us-east-1',
            'tags': {'Environment': 'tag-env'}
        }
        
        assert classifier.get_environment(instance_with_tag) == 'tag-env'
        assert classifier.get_classification_source(instance_with_tag) == 'aws_tag'
        
        # Test priority 2: Manual mapping (should override account and naming)
        instance_manual = {
            'instance_id': 'prod-test-db',  # Has manual mapping and naming pattern
            'account_id': '123456789012',   # Has account mapping
            'region': 'us-east-1',
            'tags': {}  # No environment tags
        }
        
        assert classifier.get_environment(instance_manual) == 'manual-env'
        assert classifier.get_classification_source(instance_manual) == 'manual_mapping'
        
        # Test priority 3: Account mapping (should override naming pattern)
        instance_account = {
            'instance_id': 'prod-other-db',  # Has naming pattern but no manual mapping
            'account_id': '123456789012',    # Has account mapping
            'region': 'us-east-1',
            'tags': {}  # No environment tags
        }
        
        assert classifier.get_environment(instance_account) == 'account-env'
        assert classifier.get_classification_source(instance_account) == 'account_mapping'
        
        # Test priority 4: Naming pattern
        instance_naming = {
            'instance_id': 'prod-other-db',  # Has naming pattern
            'account_id': '999999999999',    # No account mapping
            'region': 'us-east-1',
            'tags': {}  # No environment tags
        }
        
        assert classifier.get_environment(instance_naming) == 'production'
        assert classifier.get_classification_source(instance_naming) == 'naming_pattern'
        
        # Test priority 5: Default
        instance_default = {
            'instance_id': 'random-db-name',  # No naming pattern
            'account_id': '999999999999',     # No account mapping
            'region': 'us-east-1',
            'tags': {}  # No environment tags
        }
        
        assert classifier.get_environment(instance_default) == 'default-env'
        assert classifier.get_classification_source(instance_default) == 'default'
    
    @given(st.text(min_size=1, max_size=50))
    @settings(max_examples=100, deadline=3000)
    def test_case_insensitive_classification(self, environment_value):
        """
        Property 6h: Environment classification is case-insensitive.
        
        For any environment value in any case, the classification should
        normalize to lowercase consistently.
        """
        config = {
            'default_environment': 'non-production',
            'environment_tag_names': ['Environment'],
            'naming_patterns': {},
            'account_mappings': {},
            'instance_mappings': {}
        }
        
        classifier = EnvironmentClassifier(config)
        
        instance = {
            'instance_id': 'test-instance',
            'account_id': '123456789012',
            'region': 'us-east-1',
            'tags': {'Environment': environment_value}
        }
        
        environment = classifier.get_environment(instance)
        
        # Should always be lowercase
        assert environment == environment_value.lower()
        assert environment.islower() or not environment.isalpha()  # Handle non-alphabetic characters


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])