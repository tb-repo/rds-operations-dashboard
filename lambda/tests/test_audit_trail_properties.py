"""
Property-Based Tests for Audit Trail System

Tests the completeness and integrity of audit trail functionality
using property-based testing to verify universal properties.

**Feature: api-error-resolution, Property 6: Audit trail completeness**
**Validates: Requirements 5.2**

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-15T15:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.2 → DESIGN-AuditSystem → TASK-5.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
from hypothesis import given, strategies as st, settings, assume
from datetime import datetime, timezone, timedelta
import json
import uuid
import sys
import os

# Add the error_resolution directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error_resolution'))

from audit_system import (
    AuditTrail, AuditEvent, AuditEventType, AuditSeverity,
    ComplianceReporter, get_audit_trail, create_audit_event
)


# Hypothesis strategies for generating test data
@st.composite
def audit_event_data(draw):
    """Generate valid audit event data."""
    event_types = list(AuditEventType)
    severities = list(AuditSeverity)
    
    return {
        'event_type': draw(st.sampled_from(event_types)),
        'action': draw(st.text(min_size=1, max_size=100, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Pc', 'Pd', 'Zs')))),
        'resource': draw(st.text(min_size=1, max_size=100, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Pc', 'Pd', 'Zs')))),
        'outcome': draw(st.sampled_from(['success', 'failure', 'pending', 'error', 'timeout'])),
        'severity': draw(st.sampled_from(severities)),
        'user_id': draw(st.one_of(st.none(), st.text(min_size=1, max_size=50))),
        'correlation_id': draw(st.one_of(st.none(), st.uuids().map(str))),
        'details': draw(st.dictionaries(
            st.text(min_size=1, max_size=20, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'))),
            st.one_of(st.text(max_size=100), st.integers(), st.booleans()),
            max_size=5
        )),
        'metadata': draw(st.dictionaries(
            st.text(min_size=1, max_size=20, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'))),
            st.one_of(st.text(max_size=100), st.integers(), st.booleans()),
            max_size=3
        ))
    }


class TestAuditTrailProperties:
    """Property-based tests for audit trail completeness."""
    
    def setup_method(self):
        """Set up test environment."""
        # Reset global audit trail to avoid test interference
        import audit_system
        audit_system._audit_trail = None
        self.audit_trail = AuditTrail("test-service")
    
    @given(audit_event_data())
    @settings(max_examples=100, deadline=5000)
    def test_audit_event_creation_completeness(self, event_data):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any valid audit event data, creating an audit event
        should result in a complete audit record with all required fields
        populated and integrity checksum calculated.
        """
        # Create audit event
        audit_event = self.audit_trail.create_audit_event(**event_data)
        
        # Verify completeness - all required fields must be present
        assert audit_event.id is not None and audit_event.id != ""
        assert audit_event.timestamp is not None
        assert isinstance(audit_event.timestamp, datetime)
        assert audit_event.event_type == event_data['event_type']
        assert audit_event.severity == event_data['severity']
        assert audit_event.service == "test-service"
        assert audit_event.action == event_data['action']
        assert audit_event.resource == event_data['resource']
        assert audit_event.outcome == event_data['outcome']
        assert audit_event.details == event_data['details']
        assert audit_event.metadata == event_data['metadata']
        
        # Verify integrity checksum is calculated
        assert audit_event.checksum is not None and audit_event.checksum != ""
        assert len(audit_event.checksum) == 64  # SHA-256 hex string length
        
        # Verify correlation ID handling
        if event_data['correlation_id']:
            assert audit_event.correlation_id == event_data['correlation_id']
        else:
            assert audit_event.correlation_id is not None and audit_event.correlation_id != ""
        
        # Verify user ID handling
        assert audit_event.user_id == event_data['user_id']
        
        # Verify event is stored in audit trail
        assert audit_event in self.audit_trail.audit_events
        
        # Verify integrity verification works
        assert self.audit_trail.verify_event_integrity(audit_event) is True
    
    @given(st.lists(audit_event_data(), min_size=1, max_size=20))
    @settings(max_examples=50, deadline=10000)
    def test_audit_trail_immutability(self, events_data):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any sequence of audit events, once created, the audit
        events should be immutable and their integrity should be verifiable.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        created_events = []
        
        # Create multiple audit events
        for event_data in events_data:
            audit_event = audit_trail.create_audit_event(**event_data)
            created_events.append(audit_event)
        
        # Verify all events maintain integrity
        for event in created_events:
            assert audit_trail.verify_event_integrity(event) is True
        
        # Verify events are in chronological order
        timestamps = [event.timestamp for event in audit_trail.audit_events]
        assert timestamps == sorted(timestamps)
        
        # Verify total count matches
        assert len(audit_trail.audit_events) == len(events_data)
        
        # Verify each event has unique ID
        event_ids = [event.id for event in audit_trail.audit_events]
        assert len(event_ids) == len(set(event_ids))
    
    @given(
        st.lists(audit_event_data(), min_size=5, max_size=50),
        st.sampled_from(list(AuditEventType)),
        st.text(min_size=1, max_size=50)
    )
    @settings(max_examples=30, deadline=10000)
    def test_audit_search_completeness(self, events_data, filter_event_type, filter_user_id):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any collection of audit events and any search criteria,
        the search results should contain all and only the events that match
        the criteria, maintaining completeness and accuracy.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        
        # Create audit events
        created_events = []
        for event_data in events_data:
            audit_event = audit_trail.create_audit_event(**event_data)
            created_events.append(audit_event)
        
        # Test event type filtering
        filtered_events = audit_trail.get_audit_events(event_type=filter_event_type)
        expected_events = [e for e in created_events if e.event_type == filter_event_type]
        
        assert len(filtered_events) == len(expected_events)
        for event in filtered_events:
            assert event.event_type == filter_event_type
            assert event in expected_events
        
        # Test user ID filtering
        filtered_by_user = audit_trail.get_audit_events(user_id=filter_user_id)
        expected_by_user = [e for e in created_events if e.user_id == filter_user_id]
        
        assert len(filtered_by_user) == len(expected_by_user)
        for event in filtered_by_user:
            assert event.user_id == filter_user_id
            assert event in expected_by_user
        
        # Test time range filtering
        if created_events:
            mid_time = created_events[len(created_events) // 2].timestamp
            filtered_by_time = audit_trail.get_audit_events(start_time=mid_time)
            
            for event in filtered_by_time:
                assert event.timestamp >= mid_time
    
    @given(st.lists(audit_event_data(), min_size=10, max_size=100))
    @settings(max_examples=20, deadline=15000)
    def test_compliance_report_completeness(self, events_data):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any collection of audit events, compliance reports
        should accurately reflect all events in the specified time period
        and maintain data integrity verification.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        
        # Create audit events
        created_events = []
        for event_data in events_data:
            audit_event = audit_trail.create_audit_event(**event_data)
            created_events.append(audit_event)
        
        # Get time range
        if created_events:
            start_time = min(event.timestamp for event in created_events) - timedelta(minutes=1)
            end_time = max(event.timestamp for event in created_events) + timedelta(minutes=1)
        else:
            start_time = datetime.now(timezone.utc) - timedelta(hours=1)
            end_time = datetime.now(timezone.utc)
        
        # Generate compliance report
        compliance_reporter = ComplianceReporter(audit_trail)
        report = compliance_reporter.generate_compliance_report(
            start_time=start_time,
            end_time=end_time,
            report_type="summary"
        )
        
        # Verify report completeness
        assert 'report_id' in report
        assert 'generated_at' in report
        assert 'total_events' in report
        assert 'integrity_verification' in report
        
        # Verify event count accuracy
        assert report['total_events'] == len(created_events)
        
        # Verify integrity verification
        integrity_info = report['integrity_verification']
        assert integrity_info['total_events'] == len(created_events)
        assert integrity_info['verified_events'] == len(created_events)
        assert integrity_info['integrity_rate'] == 1.0  # All events should be verified
        
        # Verify time period accuracy
        assert report['period']['start'] == start_time.isoformat()
        assert report['period']['end'] == end_time.isoformat()
    
    @given(
        audit_event_data(),
        st.text(min_size=1, max_size=100, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Zs')))
    )
    @settings(max_examples=50, deadline=5000)
    def test_audit_search_text_completeness(self, event_data, search_query):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any audit event and any search query, if the query
        matches any searchable field in the event, the event should be
        included in search results.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        
        # Create audit event with search query in action field
        event_data_with_query = event_data.copy()
        event_data_with_query['action'] = f"test_action_{search_query}_end"
        
        audit_event = audit_trail.create_audit_event(**event_data_with_query)
        
        # Search for the query
        search_results = audit_trail.search_audit_events(search_query)
        
        # Verify the event is found
        assert len(search_results) >= 1
        assert audit_event in search_results
        
        # Verify all results contain the search query
        for result in search_results:
            found_in_searchable_field = (
                search_query.lower() in result.action.lower() or
                search_query.lower() in result.resource.lower() or
                search_query.lower() in result.outcome.lower() or
                search_query.lower() in json.dumps(result.details).lower() or
                search_query.lower() in json.dumps(result.metadata).lower()
            )
            assert found_in_searchable_field
    
    @given(st.lists(audit_event_data(), min_size=5, max_size=30))
    @settings(max_examples=30, deadline=10000)
    def test_audit_export_completeness(self, events_data):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any collection of audit events, exporting the audit
        trail should preserve all event data and maintain data integrity.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        
        # Create audit events
        created_events = []
        for event_data in events_data:
            audit_event = audit_trail.create_audit_event(**event_data)
            created_events.append(audit_event)
        
        # Export as JSON
        json_export = audit_trail.export_audit_trail(format_type="json")
        exported_data = json.loads(json_export)
        
        # Verify completeness
        assert len(exported_data) == len(created_events)
        
        # Verify each exported event contains all required fields
        for exported_event in exported_data:
            assert 'id' in exported_event
            assert 'timestamp' in exported_event
            assert 'event_type' in exported_event
            assert 'severity' in exported_event
            assert 'service' in exported_event
            assert 'action' in exported_event
            assert 'resource' in exported_event
            assert 'outcome' in exported_event
            assert 'details' in exported_event
            assert 'metadata' in exported_event
            assert 'checksum' in exported_event
            assert 'correlation_id' in exported_event
        
        # Export as CSV
        csv_export = audit_trail.export_audit_trail(format_type="csv")
        csv_lines = csv_export.split('\n')
        
        # Verify CSV structure (header + data rows)
        if created_events:
            assert len(csv_lines) >= len(created_events) + 1  # Header + data rows
            
            # Verify header contains required fields
            header = csv_lines[0]
            required_fields = ['id', 'correlation_id', 'timestamp', 'event_type', 'severity', 'action', 'resource', 'outcome', 'checksum']
            for field in required_fields:
                assert field in header
    
    @given(audit_event_data())
    @settings(max_examples=100, deadline=5000)
    def test_audit_event_integrity_preservation(self, event_data):
        """
        **Feature: api-error-resolution, Property 6: Audit trail completeness**
        **Validates: Requirements 5.2**
        
        Property: For any audit event, the integrity checksum should remain
        valid and any tampering should be detectable.
        """
        # Create a fresh audit trail for each test example
        audit_trail = AuditTrail("test-service")
        
        # Create audit event
        audit_event = audit_trail.create_audit_event(**event_data)
        original_checksum = audit_event.checksum
        
        # Verify original integrity
        assert audit_trail.verify_event_integrity(audit_event) is True
        
        # Simulate tampering by modifying the event
        original_message = audit_event.action
        audit_event.action = "tampered_action"
        
        # Verify tampering is detected (checksum should not match)
        assert audit_trail.verify_event_integrity(audit_event) is False
        
        # Restore original data
        audit_event.action = original_message
        
        # Verify integrity is restored
        assert audit_trail.verify_event_integrity(audit_event) is True
        assert audit_event.checksum == original_checksum


if __name__ == "__main__":
    # Run the property-based tests
    pytest.main([__file__, "-v", "--tb=short"])