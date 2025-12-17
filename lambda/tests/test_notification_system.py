"""
Unit Tests for Notification System

Tests alert rule evaluation, notification delivery, and escalation logic
for the API error resolution alerting system.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-4.1, REQ-4.2, REQ-4.3 → DESIGN-AlertSystem → TASK-4.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
import sys
import os
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime, timedelta
from typing import Dict, Any, List

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Import the modules under test
try:
    from error_resolution.alert_system import (
        AlertSystem, AlertRuleEngine, AlertRule, Alert, AlertSeverity, 
        AlertStatus, NotificationChannel, NotificationDeliverySystem,
        EscalationWorkflow, get_alert_system
    )
except ImportError:
    # Try alternative import path
    import sys
    import os
    sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error-resolution'))
    from alert_system import (
        AlertSystem, AlertRuleEngine, AlertRule, Alert, AlertSeverity, 
        AlertStatus, NotificationChannel, NotificationDeliverySystem,
        EscalationWorkflow, get_alert_system
    )


class TestAlertRuleEvaluation:
    """Test alert rule evaluation logic."""
    
    def test_rule_matches_status_code(self):
        """Test alert rule evaluation - status code matching."""
        rule = AlertRule(
            id="test_rule",
            name="Test Rule",
            description="Test rule for 500 errors",
            severity=AlertSeverity.HIGH,
            conditions={"status_codes": [500, 502, 503]},
            notification_channels=[NotificationChannel.EMAIL]
        )
        
        # Should match
        error_500 = {"status_code": 500, "service": "test", "category": "database"}
        assert rule.matches_error(error_500) == True
        
        error_502 = {"status_code": 502, "service": "test", "category": "database"}
        assert rule.matches_error(error_502) == True
        
        # Should not match
        error_404 = {"status_code": 404, "service": "test", "category": "database"}
        assert rule.matches_error(error_404) == False
    
    def test_rule_matches_category(self):
        """Test alert rule evaluation - category matching."""
        rule = AlertRule(
            id="auth_rule",
            name="Auth Rule",
            description="Authentication errors",
            severity=AlertSeverity.HIGH,
            conditions={"categories": ["authentication", "authorization"]},
            notification_channels=[NotificationChannel.SNS]
        )
        
        # Should match
        auth_error = {"status_code": 401, "category": "authentication", "service": "api"}
        assert rule.matches_error(auth_error) == True
        
        authz_error = {"status_code": 403, "category": "authorization", "service": "api"}
        assert rule.matches_error(authz_error) == True
        
        # Should not match
        db_error = {"status_code": 500, "category": "database", "service": "api"}
        assert rule.matches_error(db_error) == False
    
    def test_rule_matches_service(self):
        """Test alert rule evaluation - service matching."""
        rule = AlertRule(
            id="critical_services",
            name="Critical Services",
            description="Errors in critical services",
            severity=AlertSeverity.CRITICAL,
            conditions={"services": ["health-monitor", "operations"]},
            notification_channels=[NotificationChannel.PAGERDUTY]
        )
        
        # Should match
        health_error = {"status_code": 500, "service": "health-monitor", "category": "database"}
        assert rule.matches_error(health_error) == True
        
        ops_error = {"status_code": 403, "service": "operations", "category": "authorization"}
        assert rule.matches_error(ops_error) == True
        
        # Should not match
        other_error = {"status_code": 500, "service": "cost-analyzer", "category": "database"}
        assert rule.matches_error(other_error) == False
    
    def test_rule_disabled(self):
        """Test that disabled rules never match."""
        rule = AlertRule(
            id="disabled_rule",
            name="Disabled Rule",
            description="This rule is disabled",
            severity=AlertSeverity.HIGH,
            conditions={"status_codes": [500]},
            notification_channels=[NotificationChannel.EMAIL],
            enabled=False
        )
        
        error = {"status_code": 500, "service": "test", "category": "database"}
        assert rule.matches_error(error) == False
    
    def test_rule_multiple_conditions(self):
        """Test alert rule with multiple conditions (AND logic)."""
        rule = AlertRule(
            id="complex_rule",
            name="Complex Rule",
            description="Multiple conditions",
            severity=AlertSeverity.HIGH,
            conditions={
                "status_codes": [500, 503],
                "categories": ["database"],
                "services": ["health-monitor"]
            },
            notification_channels=[NotificationChannel.SNS]
        )
        
        # Should match (all conditions met)
        matching_error = {
            "status_code": 500,
            "category": "database",
            "service": "health-monitor"
        }
        assert rule.matches_error(matching_error) == True
        
        # Should not match (missing category condition)
        non_matching_error = {
            "status_code": 500,
            "category": "network",
            "service": "health-monitor"
        }
        assert rule.matches_error(non_matching_error) == False


class TestAlertGeneration:
    """Test alert generation and management."""
    
    def test_create_new_alert(self):
        """Test creating a new alert."""
        engine = AlertRuleEngine()
        
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "message": "Database connection failed",
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database",
            "severity": "critical"
        }
        
        alerts = engine.evaluate_error(api_error)
        
        # Should generate alerts for matching rules
        assert len(alerts) > 0
        
        # Check alert properties
        alert = alerts[0]
        assert alert.service == "health-monitor"
        assert alert.endpoint == "/api/health"
        assert alert.error_count == 1
        assert alert.status == AlertStatus.ACTIVE
        assert isinstance(alert.first_occurrence, datetime)
        assert isinstance(alert.last_occurrence, datetime)
    
    def test_update_existing_alert(self):
        """Test updating an existing alert with same error pattern."""
        engine = AlertRuleEngine()
        
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "message": "Database connection failed",
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database",
            "severity": "critical"
        }
        
        # Generate first alert
        alerts1 = engine.evaluate_error(api_error)
        assert len(alerts1) > 0
        first_alert = alerts1[0]
        initial_count = first_alert.error_count
        
        # Generate second alert with same pattern
        api_error["id"] = "err_test_2"  # Different error ID
        alerts2 = engine.evaluate_error(api_error)
        
        # Should update existing alert, not create new one
        assert len(alerts2) > 0
        updated_alert = alerts2[0]
        assert updated_alert.id == first_alert.id  # Same alert ID
        assert updated_alert.error_count == initial_count + 1
    
    def test_acknowledge_alert(self):
        """Test acknowledging an alert."""
        engine = AlertRuleEngine()
        
        # Create an alert
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database"
        }
        
        alerts = engine.evaluate_error(api_error)
        alert = alerts[0]
        
        # Acknowledge the alert
        success = engine.acknowledge_alert(alert.id, "test_user")
        
        assert success == True
        assert alert.status == AlertStatus.ACKNOWLEDGED
        assert alert.acknowledged_by == "test_user"
        assert alert.acknowledged_at is not None
        assert alert.next_escalation_at is None  # Escalation stopped
    
    def test_resolve_alert(self):
        """Test resolving an alert."""
        engine = AlertRuleEngine()
        
        # Create an alert
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database"
        }
        
        alerts = engine.evaluate_error(api_error)
        alert = alerts[0]
        alert_id = alert.id
        
        # Resolve the alert
        success = engine.resolve_alert(alert_id)
        
        assert success == True
        assert alert.status == AlertStatus.RESOLVED
        assert alert.resolved_at is not None
        
        # Alert should be removed from active alerts
        active_alerts = engine.get_active_alerts()
        active_alert_ids = [a.id for a in active_alerts]
        assert alert_id not in active_alert_ids


class TestNotificationDelivery:
    """Test notification delivery system."""
    
    @patch('boto3.client')
    def test_sns_notification_success(self, mock_boto_client):
        """Test successful SNS notification delivery."""
        # Mock SNS client
        mock_sns = Mock()
        mock_boto_client.return_value = mock_sns
        mock_sns.publish.return_value = {'MessageId': 'test-message-id'}
        
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        
        # Create test alert and rule
        alert = Alert(
            id="test_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.HIGH,
            status=AlertStatus.ACTIVE,
            title="Test Alert",
            description="Test alert description",
            service="health-monitor",
            endpoint="/api/health",
            error_count=1,
            first_occurrence=datetime.utcnow(),
            last_occurrence=datetime.utcnow()
        )
        
        rule = AlertRule(
            id="test_rule",
            name="Test Rule",
            description="Test rule",
            severity=AlertSeverity.HIGH,
            conditions={"status_codes": [500]},
            notification_channels=[NotificationChannel.SNS]
        )
        
        # Send notification
        results = notification_system.send_notifications(alert, rule)
        
        # Verify SNS was called
        assert results[NotificationChannel.SNS] == True
        mock_sns.publish.assert_called_once()
        
        # Check call arguments
        call_args = mock_sns.publish.call_args
        assert call_args[1]['TopicArn'] == config['sns_topic_arn']
        assert 'Test Alert' in call_args[1]['Subject']
        assert 'Test alert description' in call_args[1]['Message']
    
    @patch('boto3.client')
    def test_sns_notification_failure(self, mock_boto_client):
        """Test SNS notification failure handling."""
        # Mock SNS client to raise exception
        mock_sns = Mock()
        mock_boto_client.return_value = mock_sns
        mock_sns.publish.side_effect = Exception("SNS error")
        
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        
        alert = Alert(
            id="test_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.HIGH,
            status=AlertStatus.ACTIVE,
            title="Test Alert",
            description="Test alert description",
            service="health-monitor",
            endpoint="/api/health",
            error_count=1,
            first_occurrence=datetime.utcnow(),
            last_occurrence=datetime.utcnow()
        )
        
        rule = AlertRule(
            id="test_rule",
            name="Test Rule",
            description="Test rule",
            severity=AlertSeverity.HIGH,
            conditions={"status_codes": [500]},
            notification_channels=[NotificationChannel.SNS]
        )
        
        # Send notification
        results = notification_system.send_notifications(alert, rule)
        
        # Should handle failure gracefully
        assert results[NotificationChannel.SNS] == False
    
    def test_multiple_notification_channels(self):
        """Test sending notifications through multiple channels."""
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        
        alert = Alert(
            id="test_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.HIGH,
            status=AlertStatus.ACTIVE,
            title="Test Alert",
            description="Test alert description",
            service="health-monitor",
            endpoint="/api/health",
            error_count=1,
            first_occurrence=datetime.utcnow(),
            last_occurrence=datetime.utcnow()
        )
        
        rule = AlertRule(
            id="test_rule",
            name="Test Rule",
            description="Test rule",
            severity=AlertSeverity.HIGH,
            conditions={"status_codes": [500]},
            notification_channels=[NotificationChannel.EMAIL, NotificationChannel.SLACK]
        )
        
        # Send notifications
        results = notification_system.send_notifications(alert, rule)
        
        # Should attempt both channels
        assert NotificationChannel.EMAIL in results
        assert NotificationChannel.SLACK in results
    
    def test_build_sns_message(self):
        """Test SNS message building."""
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        
        alert = Alert(
            id="test_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.CRITICAL,
            status=AlertStatus.ACTIVE,
            title="Critical Database Error",
            description="Database connection failed",
            service="health-monitor",
            endpoint="/api/health/database",
            error_count=3,
            first_occurrence=datetime(2025, 12, 13, 10, 0, 0),
            last_occurrence=datetime(2025, 12, 13, 10, 5, 0),
            escalation_level=1
        )
        
        rule = AlertRule(
            id="test_rule",
            name="Test Rule",
            description="Test rule",
            severity=AlertSeverity.CRITICAL,
            conditions={"status_codes": [500]},
            notification_channels=[NotificationChannel.SNS]
        )
        
        message = notification_system._build_sns_message(alert, rule)
        
        # Check message content
        assert "test_alert_1" in message
        assert "CRITICAL" in message
        assert "health-monitor" in message
        assert "/api/health/database" in message
        assert "Database connection failed" in message
        assert "Error Count: 3" in message
        assert "🚨 ESCALATED (Level 1)" in message


class TestEscalationWorkflow:
    """Test alert escalation logic."""
    
    def test_escalation_timing(self):
        """Test escalation timing logic."""
        engine = AlertRuleEngine()
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        escalation_workflow = EscalationWorkflow(engine, notification_system)
        
        # Create an alert that should escalate
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database"
        }
        
        alerts = engine.evaluate_error(api_error)
        alert = alerts[0]
        
        # Set escalation time to past (should escalate)
        alert.next_escalation_at = datetime.utcnow() - timedelta(minutes=1)
        
        # Process escalations
        escalated_count = escalation_workflow.process_escalations()
        
        assert escalated_count > 0
        assert alert.escalation_level > 0
        assert alert.status == AlertStatus.ESCALATED
    
    def test_escalation_max_level(self):
        """Test that escalation respects maximum level."""
        engine = AlertRuleEngine()
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        escalation_workflow = EscalationWorkflow(engine, notification_system)
        
        # Find a rule with max escalations
        rule = None
        for r in engine.rules:
            if r.max_escalations > 0:
                rule = r
                break
        
        assert rule is not None, "Should have at least one rule with max escalations"
        
        # Create alert and set to max escalation level
        api_error = {
            "id": "err_test_1",
            "status_code": 500,
            "service": "health-monitor",
            "endpoint": "/api/health",
            "category": "database"
        }
        
        alerts = engine.evaluate_error(api_error)
        alert = alerts[0]
        
        # Set to max escalation level
        alert.escalation_level = rule.max_escalations
        alert.next_escalation_at = datetime.utcnow() - timedelta(minutes=1)
        
        # Process escalations
        escalated_count = escalation_workflow.process_escalations()
        
        # Should not escalate further
        assert alert.escalation_level == rule.max_escalations
    
    def test_create_incident_ticket(self):
        """Test incident ticket creation for critical alerts."""
        engine = AlertRuleEngine()
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        escalation_workflow = EscalationWorkflow(engine, notification_system)
        
        # Create critical alert
        critical_alert = Alert(
            id="critical_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.CRITICAL,
            status=AlertStatus.ACTIVE,
            title="Critical System Failure",
            description="System is down",
            service="health-monitor",
            endpoint="/api/health",
            error_count=1,
            first_occurrence=datetime.utcnow(),
            last_occurrence=datetime.utcnow()
        )
        
        # Create incident ticket
        ticket_id = escalation_workflow.create_incident_ticket(critical_alert)
        
        assert ticket_id is not None
        assert ticket_id.startswith("INC-")
    
    def test_no_incident_for_non_critical(self):
        """Test that incident tickets are not created for non-critical alerts."""
        engine = AlertRuleEngine()
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        notification_system = NotificationDeliverySystem(config)
        escalation_workflow = EscalationWorkflow(engine, notification_system)
        
        # Create non-critical alert
        medium_alert = Alert(
            id="medium_alert_1",
            rule_id="test_rule",
            error_id="err_test_1",
            severity=AlertSeverity.MEDIUM,
            status=AlertStatus.ACTIVE,
            title="Medium Priority Alert",
            description="Non-critical issue",
            service="health-monitor",
            endpoint="/api/health",
            error_count=1,
            first_occurrence=datetime.utcnow(),
            last_occurrence=datetime.utcnow()
        )
        
        # Try to create incident ticket
        ticket_id = escalation_workflow.create_incident_ticket(medium_alert)
        
        assert ticket_id is None


class TestAlertSystem:
    """Test the main alert system orchestrator."""
    
    @patch('boto3.client')
    def test_process_api_error_end_to_end(self, mock_boto_client):
        """Test end-to-end API error processing."""
        # Mock AWS clients
        mock_sns = Mock()
        mock_boto_client.return_value = mock_sns
        mock_sns.publish.return_value = {'MessageId': 'test-message-id'}
        
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        # Process a critical error
        api_error = {
            "id": "err_critical_1",
            "status_code": 500,
            "message": "Database connection failed",
            "service": "health-monitor",
            "endpoint": "/api/health/database",
            "category": "database",
            "severity": "critical"
        }
        
        alerts = alert_system.process_api_error(api_error)
        
        # Should generate alerts
        assert len(alerts) > 0
        
        # Should have critical alert with incident ticket
        critical_alerts = [a for a in alerts if a.severity == AlertSeverity.CRITICAL]
        assert len(critical_alerts) > 0
        
        critical_alert = critical_alerts[0]
        assert critical_alert.metadata is not None
        assert 'incident_ticket' in critical_alert.metadata
    
    def test_get_alert_statistics(self):
        """Test alert system statistics."""
        config = {"sns_topic_arn": "arn:aws:sns:us-east-1:123456789012:test-alerts"}
        alert_system = AlertSystem(config)
        
        # Generate some alerts
        api_errors = [
            {
                "id": "err_1",
                "status_code": 500,
                "service": "health-monitor",
                "endpoint": "/api/health",
                "category": "database",
                "severity": "critical"
            },
            {
                "id": "err_2",
                "status_code": 403,
                "service": "operations",
                "endpoint": "/api/operations",
                "category": "authorization",
                "severity": "high"
            }
        ]
        
        for error in api_errors:
            alert_system.process_api_error(error)
        
        # Get statistics
        stats = alert_system.get_alert_statistics()
        
        # Verify statistics structure
        assert 'total_active_alerts' in stats
        assert 'alerts_by_severity' in stats
        assert 'alerts_by_status' in stats
        assert 'total_rules' in stats
        assert 'enabled_rules' in stats
        
        # Should have some active alerts
        assert stats['total_active_alerts'] > 0
        
        # Severity counts should add up
        severity_total = sum(stats['alerts_by_severity'].values())
        assert severity_total == stats['total_active_alerts']
        
        # Status counts should add up
        status_total = sum(stats['alerts_by_status'].values())
        assert status_total == stats['total_active_alerts']


if __name__ == '__main__':
    pytest.main([__file__, '-v'])