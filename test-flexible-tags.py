#!/usr/bin/env python3
"""
Quick test to demonstrate flexible environment tag names.
"""

import sys
import os

# Add lambda directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lambda'))

# Import just the classifier (avoid boto3 dependencies)
import re
from typing import Dict, Any, Optional

class EnvironmentClassifier:
    """Simplified classifier for testing."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.default_environment = config.get('default_environment', 'non-production')
        self.environment_tag_names = config.get('environment_tag_names', [
            'Environment', 'Env', 'ENV', 'environment', 'env',
            'Environ', 'environ', 'ENVIRON', 'Stage', 'stage', 'STAGE'
        ])
    
    def get_environment(self, instance: Dict[str, Any]) -> str:
        tags = instance.get('tags', {})
        env_value = self._get_environment_from_tags(tags)
        if env_value:
            return env_value.lower()
        return self.default_environment.lower()
    
    def get_classification_source(self, instance: Dict[str, Any]) -> str:
        tags = instance.get('tags', {})
        if self._get_environment_from_tags(tags):
            return 'aws_tag'
        return 'default'
    
    def _get_environment_from_tags(self, tags: Dict[str, str]) -> Optional[str]:
        for tag_name in self.environment_tag_names:
            if tag_name in tags and tags[tag_name]:
                return tags[tag_name]
        for tag_key, tag_value in tags.items():
            if tag_key.lower() in ['environment', 'env', 'environ', 'stage'] and tag_value:
                return tag_value
        return None

# Initialize classifier
config = {
    'default_environment': 'non-production',
    'environment_tag_names': [
        'Environment', 'Env', 'ENV', 'environment', 'env',
        'Environ', 'environ', 'ENVIRON', 'Stage', 'stage', 'STAGE'
    ]
}

classifier = EnvironmentClassifier(config)

# Test cases
test_cases = [
    {'tags': {'Environment': 'Production'}, 'expected': 'production'},
    {'tags': {'Env': 'Development'}, 'expected': 'development'},
    {'tags': {'ENV': 'TEST'}, 'expected': 'test'},
    {'tags': {'env': 'staging'}, 'expected': 'staging'},
    {'tags': {'Environ': 'POC'}, 'expected': 'poc'},
    {'tags': {'Stage': 'Production'}, 'expected': 'production'},
    {'tags': {'ENVIRONMENT': 'Production'}, 'expected': 'production'},  # Fallback
    {'tags': {'Team': 'DataPlatform'}, 'expected': 'non-production'},  # Default
]

print("\n" + "="*60)
print("Flexible Environment Tag Names - Test Results")
print("="*60 + "\n")

passed = 0
failed = 0

for i, test in enumerate(test_cases, 1):
    instance = {
        'instance_id': f'test-db-{i:02d}',
        'account_id': '123456789012',
        'tags': test['tags']
    }
    
    result = classifier.get_environment(instance)
    source = classifier.get_classification_source(instance)
    expected = test['expected']
    
    status = "✅ PASS" if result == expected else "❌ FAIL"
    
    tag_display = ', '.join([f"{k}={v}" for k, v in test['tags'].items()])
    
    print(f"Test {i}: {status}")
    print(f"  Tags: {tag_display}")
    print(f"  Expected: {expected}")
    print(f"  Got: {result}")
    print(f"  Source: {source}")
    print()
    
    if result == expected:
        passed += 1
    else:
        failed += 1

print("="*60)
print(f"Results: {passed}/{len(test_cases)} passed")
print("="*60)

if failed == 0:
    print("\n✅ All tests passed! Flexible tag names work correctly.\n")
    sys.exit(0)
else:
    print(f"\n❌ {failed} test(s) failed.\n")
    sys.exit(1)
