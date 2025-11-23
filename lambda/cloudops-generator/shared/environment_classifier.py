#!/usr/bin/env python3
"""
Environment Classifier

Determines environment type using multiple methods with fallback priority.
Supports AWS tags, manual mappings, account-based, and naming patterns.
"""

import re
from typing import Dict, Any, Optional


class EnvironmentClassifier:
    """Classify RDS instances into environments using multiple methods."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize classifier with configuration.
        
        Args:
            config: Configuration including environment mappings
        """
        self.config = config
        self.instance_mappings = config.get('instance_mappings', {})
        self.account_mappings = config.get('account_mappings', {})
        self.naming_patterns = config.get('naming_patterns', {})
        self.default_environment = config.get('default_environment', 'non-production')
        
        # Flexible environment tag names (case-insensitive)
        self.environment_tag_names = config.get('environment_tag_names', [
            'Environment',
            'Env', 
            'ENV',
            'environment',
            'env',
            'Environ',
            'environ',
            'ENVIRON',
            'Stage',
            'stage',
            'STAGE'
        ])
    
    def get_environment(self, instance: Dict[str, Any]) -> str:
        """
        Determine environment for an instance using priority order.
        
        Priority:
        1. AWS Tags (if present)
        2. Manual instance mapping
        3. Account-based classification
        4. Naming pattern matching
        5. Default environment
        
        Args:
            instance: RDS instance metadata
            
        Returns:
            str: Environment type (lowercase)
        """
        instance_id = instance.get('instance_id', '')
        account_id = instance.get('account_id', '')
        tags = instance.get('tags', {})
        
        # Priority 1: AWS Tags (flexible tag names)
        env_value = self._get_environment_from_tags(tags)
        if env_value:
            return env_value.lower()
        
        # Priority 2: Manual instance mapping
        if instance_id in self.instance_mappings:
            return self.instance_mappings[instance_id].lower()
        
        # Priority 3: Account-based classification
        if account_id in self.account_mappings:
            return self.account_mappings[account_id].lower()
        
        # Priority 4: Naming pattern matching
        pattern_env = self._match_naming_pattern(instance_id)
        if pattern_env:
            return pattern_env.lower()
        
        # Priority 5: Default
        return self.default_environment.lower()
    
    def get_classification_source(self, instance: Dict[str, Any]) -> str:
        """
        Identify which method was used to classify the instance.
        
        Args:
            instance: RDS instance metadata
            
        Returns:
            str: Classification source
        """
        instance_id = instance.get('instance_id', '')
        account_id = instance.get('account_id', '')
        tags = instance.get('tags', {})
        
        if self._get_environment_from_tags(tags):
            return 'aws_tag'
        elif instance_id in self.instance_mappings:
            return 'manual_mapping'
        elif account_id in self.account_mappings:
            return 'account_mapping'
        elif self._match_naming_pattern(instance_id):
            return 'naming_pattern'
        else:
            return 'default'
    
    def _match_naming_pattern(self, instance_id: str) -> Optional[str]:
        """
        Match instance ID against naming patterns.
        
        Args:
            instance_id: RDS instance identifier
            
        Returns:
            str: Matched environment or None
        """
        for environment, patterns in self.naming_patterns.items():
            for pattern in patterns:
                # Try as regex pattern
                try:
                    if re.search(pattern, instance_id, re.IGNORECASE):
                        return environment
                except re.error:
                    # If regex fails, try as simple string match
                    if pattern.lower() in instance_id.lower():
                        return environment
        
        return None
    
    def _get_environment_from_tags(self, tags: Dict[str, str]) -> Optional[str]:
        """
        Find environment value from tags using flexible tag names.
        
        Supports various tag names like:
        - Environment, Env, ENV, environment, env
        - Environ, environ, ENVIRON
        - Stage, stage, STAGE
        
        Args:
            tags: Dictionary of AWS tags
            
        Returns:
            str: Environment value or None if not found
        """
        # Try each possible environment tag name
        for tag_name in self.environment_tag_names:
            if tag_name in tags and tags[tag_name]:
                return tags[tag_name]
        
        # Also try case-insensitive matching for any tag that might be environment-related
        for tag_key, tag_value in tags.items():
            if tag_key.lower() in ['environment', 'env', 'environ', 'stage'] and tag_value:
                return tag_value
        
        return None
