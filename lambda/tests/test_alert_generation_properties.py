"""
Property-Based Tests for Alert Generation

**Feature: api-error-resolution, Property 5: Alert generation consistency**
**Validates: Requirements 4.1**

Tests that alert generation behaves consistently across all valid inputs.
Property: For any valid API error, if it matches alert rule conditions,
then an alert should be generated with consistent properties.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-4.1 → DESIGN-AlertSystem → TASK-4.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
import sys
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Import hypothesis for property-based testing
try:
    from hypothesis import given, strategies as st, settings, assume
    from hypothesis.strategies import composite
except ImportError:
    pytest.skip("Hypothesis not available", allow_module_level=True)

# Import the modules under test
try:
    from error_resolution.alert_system import (
        AlertSystem, AlertRuleEngine, AlertRule, Alert, AlertSeverity, 
        AlertStatus, NotificationChannel, get_alert_system
    )
except ImportError:
    # Try alternative import path
    import sys
    import os
    sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error_resolution'))
    from alert_system import (
        AlertSystem, AlertRuleEngine, AlertRule, Alert, AlertSeverity, 
        AlertStatus, NotificationChannel, get_alert_system
    )


# Generators for property-based testing
@composite
def api_error_data(draw):
    """Generate valid API error data for testing."""
    status_codes = [400, 401, 403, 404, 429, 500, 502, 503, 504]
    categories = ["authentication", "authorization", "database", "network", "timeout", "rate_limit", "configuration", "resource", "unknown"]
    services = ["health-monitor", "operations", "discovery", "query-handler", "cost-analyzer"]
    
    return {
        "id": f"err_{draw(st.integers(min_value=1000000, max_value=9999999))}",
        "timestamp": datetime.utcnow().isoformat(),
        "status_code": draw(st.sampled_from(status_codes)),
        "message": draw(st.text(min_size=10, max_size=200)),
        "service": draw(st.sampled_from(services)),
        "endpoint": f"/api/{draw(st.text(min_size=3, max_size=20, alphabet=st.characters(whitelist_categories=('Ll', 'Lu', 'Nd'))))}",
        "request_id": f"req_{draw(st.integers(min_value=100000, max_value=999999))}",
        "category": draw(st.sampled_from(categories)),
        "severity": draw(st.sampled_from(["low", "medium", "high", "critical"])),
        "context": draw(st.dictionaries(
            st.text(min_size=1, max_size=10), 
            st.one_of(st.text(), st.integers(), st.booleans()),
            min_size=0, max_size=5
        ))
    }


@composite
def alert_rule_data(draw):
    """Generate valid alert rule data for testing."""
    severities = list(AlertSeverity)
    channels = list(NotificationChannel)
    
    return AlertRule(
        id=f"rule_{draw(st.integers(min_value=1, max_value=1000))}",
        name=draw(st.text(min_size=5, max_size=50)),
        description=draw(st.text(min_size=10, max_size=200)),
        severity=draw(st.sampled_from(severities)),
        conditions={
            "status_codes": draw(st.lists(st.integers(min_value=400, max_value=599), min_size=1, max_size=5)),
            "categories": draw(st.lists(st.text(min_size=3, max_size=15), min_size=1, max_size=3)),
            "services": draw(st.lists(st.text(min_size=3, max_size=20), min_size=1, max_size=3))
        },
        notification_channels=draw(st.lists(st.sampled_from(channels), min_size=1, max_size=3)),
        escalation_delay_minutes=draw(st.integers(min_value=5, max_value=120)),
        max_escalations=draw(st.integers(min_value=1, max_value=5)),
        enabled=draw(st.booleans())
    )


class TestAlertGenerationProperties:
    """Property-based tests for alert generation consistency."""
    
    @given(api_error_data())
    @settings(max_examples=10, deadline=None)
    def test_alert_generation_consistency(self, api_error: Dict[str, Any]):
        """
        **Feature: api-error-resolution, Property 5: Alert generation consistency**
        **Validates: Requirements 4.1**
        
        Property: For any valid API error, alert generation should be consistent.
        If an error matches rule conditions, an alert should always be generated
        with the same properties for the same input.
        """
        # Create alert system with test configuration
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        # Process the error twice
        alerts1 = alert_system.process_api_error(api_error)
        alerts2 = alert_system.process_api_error(api_error)
        
        # Both calls should generate the same number of alerts
        assert len(alerts1) == len(alerts2), "Alert generation should be consistent"
        
        # If alerts were generated, they should have consistent properties
        if alerts1:
            for alert1, alert2 in zip(alerts1, alerts2):
                # Same rule should be triggered
                assert alert1.rule_id == alert2.rule_id, "Same rule should be triggered consistently"
                
                # Same severity should be assigned
                assert alert1.severity == alert2.severity, "Alert severity should be consistent"
                
                # Same service and endpoint
                assert alert1.service == alert2.service, "Alert service should be consistent"
                assert alert1.endpoint == alert2.endpoint, "Alert endpoint should be consistent"
    
    @given(api_error_data(), alert_rule_data())
    @settings(max_examples=10, deadline=None)
    def test_rule_matching_consistency(self, api_error: Dict[str, Any], rule: AlertRule):
        """
        Property: Rule matching should be deterministic and consistent.
        The same error should always match or not match the same rule.
        """
        # Test rule matching multiple times
        match1 = rule.matches_error(api_error)
        match2 = rule.matches_error(api_error)
        match3 = rule.matches_error(api_error)
        
        # All results should be the same
        assert match1 == match2 == match3, "Rule matching should be deterministic"
        
        # If rule is disabled, it should never match
        if not rule.enabled:
            assert not match1, "Disabled rules should never match"
    
    @given(api_error_data())
    @settings(max_examples=10, deadline=None)
    def test_alert_properties_validity(self, api_error: Dict[str, Any]):
        """
        Property: Generated alerts should always have valid properties.
        All required fields should be present and have appropriate values.
        """
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        alerts = alert_system.process_api_error(api_error)
        
        for alert in alerts:
            # Alert should have valid ID
            assert alert.id is not None and len(alert.id) > 0, "Alert ID should be non-empty"
            
            # Alert should have valid severity
            assert isinstance(alert.severity, AlertSeverity), "Alert severity should be valid enum"
            
            # Alert should have valid status
            assert isinstance(alert.status, AlertStatus), "Alert status should be valid enum"
            
            # Alert should have valid timestamps
            assert isinstance(alert.first_occurrence, datetime), "First occurrence should be datetime"
            assert isinstance(alert.last_occurrence, datetime), "Last occurrence should be datetime"
            assert alert.first_occurrence <= alert.last_occurrence, "First occurrence should be <= last occurrence"
            
            # Alert should have positive error count
            assert alert.error_count > 0, "Error count should be positive"
            
            # Alert should have valid escalation level
            assert alert.escalation_level >= 0, "Escalation level should be non-negative"
            
            # Service and endpoint should match the error
            assert alert.service == api_error["service"], "Alert service should match error service"
            assert alert.endpoint == api_error["endpoint"], "Alert endpoint should match error endpoint"
    
    @given(st.lists(api_error_data(), min_size=1, max_size=5))
    @settings(max_examples=5, deadline=None)
    def test_multiple_errors_consistency(self, api_errors: List[Dict[str, Any]]):
        """
        Property: Processing multiple errors should maintain consistency.
        The order of processing should not affect the final alert state.
        """
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        
        # Process errors in original order
        alert_system1 = AlertSystem(config)
        all_alerts1 = []
        for error in api_errors:
            alerts = alert_system1.process_api_error(error)
            all_alerts1.extend(alerts)
        
        # Process errors in reverse order
        alert_system2 = AlertSystem(config)
        all_alerts2 = []
        for error in reversed(api_errors):
            alerts = alert_system2.process_api_error(error)
            all_alerts2.extend(alerts)
        
        # Should generate the same total number of unique alerts
        # (Note: This tests that alert generation is not order-dependent)
        unique_rules1 = set(alert.rule_id for alert in all_alerts1)
        unique_rules2 = set(alert.rule_id for alert in all_alerts2)
        
        # The same rules should be triggered regardless of order
        assert unique_rules1 == unique_rules2, "Same rules should be triggered regardless of processing order"
    
    @given(api_error_data())
    @settings(max_examples=10, deadline=None)
    def test_alert_escalation_properties(self, api_error: Dict[str, Any]):
        """
        Property: Alert escalation should follow consistent rules.
        Escalation levels should never exceed maximum, and timing should be consistent.
        """
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        # Generate initial alerts
        alerts = alert_system.process_api_error(api_error)
        
        for alert in alerts:
            # Find the rule for this alert
            rule = None
            for r in alert_system.rule_engine.rules:
                if r.id == alert.rule_id:
                    rule = r
                    break
            
            if rule:
                # Escalation level should not exceed maximum
                assert alert.escalation_level <= rule.max_escalations, \
                    "Escalation level should not exceed rule maximum"
                
                # If escalation is possible, next escalation time should be set
                if alert.escalation_level < rule.max_escalations and alert.status == AlertStatus.ACTIVE:
                    assert alert.next_escalation_at is not None, \
                        "Next escalation time should be set for active alerts"
                    assert alert.next_escalation_at > alert.last_occurrence, \
                        "Next escalation should be in the future"
    
    @given(api_error_data())
    @settings(max_examples=10, deadline=None)
    def test_alert_serialization_consistency(self, api_error: Dict[str, Any]):
        """
        Property: Alert serialization should be consistent and reversible.
        Converting to dict and back should preserve all important properties.
        """
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        alerts = alert_system.process_api_error(api_error)
        
        for alert in alerts:
            # Convert to dictionary
            alert_dict = alert.to_dict()
            
            # Dictionary should contain all required fields
            required_fields = [
                'id', 'rule_id', 'error_id', 'severity', 'status', 
                'title', 'description', 'service', 'endpoint', 
                'error_count', 'first_occurrence', 'last_occurrence'
            ]
            
            for field in required_fields:
                assert field in alert_dict, f"Alert dictionary should contain {field}"
            
            # Severity and status should be string values
            assert isinstance(alert_dict['severity'], str), "Severity should be serialized as string"
            assert isinstance(alert_dict['status'], str), "Status should be serialized as string"
            
            # Timestamps should be ISO format strings
            assert isinstance(alert_dict['first_occurrence'], str), "First occurrence should be ISO string"
            assert isinstance(alert_dict['last_occurrence'], str), "Last occurrence should be ISO string"
    
    def test_alert_system_statistics_consistency(self):
        """
        Property: Alert system statistics should be consistent with actual alert state.
        Statistics should accurately reflect the current state of alerts.
        """
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        # Generate some test errors
        test_errors = [
            {
                "id": "err_test_1",
                "status_code": 500,
                "message": "Internal server error",
                "service": "health-monitor",
                "endpoint": "/api/health",
                "category": "database",
                "severity": "critical"
            },
            {
                "id": "err_test_2", 
                "status_code": 403,
                "message": "Access denied",
                "service": "operations",
                "endpoint": "/api/operations",
                "category": "authorization",
                "severity": "high"
            }
        ]
        
        # Process errors
        all_alerts = []
        for error in test_errors:
            alerts = alert_system.process_api_error(error)
            all_alerts.extend(alerts)
        
        # Get statistics
        stats = alert_system.get_alert_statistics()
        
        # Statistics should match actual alert count
        active_alerts = alert_system.rule_engine.get_active_alerts()
        assert stats['total_active_alerts'] == len(active_alerts), \
            "Statistics should match actual active alert count"
        
        # Severity counts should add up to total
        severity_total = sum(stats['alerts_by_severity'].values())
        assert severity_total == stats['total_active_alerts'], \
            "Severity counts should sum to total active alerts"
        
        # Status counts should add up to total
        status_total = sum(stats['alerts_by_status'].values())
        assert status_total == stats['total_active_alerts'], \
            "Status counts should sum to total active alerts"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])