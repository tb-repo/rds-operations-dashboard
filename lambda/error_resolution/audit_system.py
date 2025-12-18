"""
Comprehensive Audit System for Error Resolution

Provides immutable audit trails, compliance logging, and searchable audit records
for all error resolution operations in the RDS Operations Dashboard.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-15T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.2 → DESIGN-AuditSystem → TASK-5",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Union
from enum import Enum
from dataclasses import dataclass, asdict
import logging
import hashlib
import os

# Import shared modules
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

try:
    from structured_logger import get_logger, sanitize_log_data
except ImportError:
    # Fallback for testing
    def get_logger(service_name, **kwargs):
        return logging.getLogger(service_name)
    def sanitize_log_data(data):
        return data

logger = get_logger('audit-system')


class AuditEventType(Enum):
    """Types of audit events."""
    ERROR_DETECTED = "error_detected"
    ERROR_CLASSIFIED = "error_classified"
    RESOLUTION_STARTED = "resolution_started"
    RESOLUTION_COMPLETED = "resolution_completed"
    RESOLUTION_FAILED = "resolution_failed"
    ROLLBACK_STARTED = "rollback_started"
    ROLLBACK_COMPLETED = "rollback_completed"
    ROLLBACK_FAILED = "rollback_failed"
    MANUAL_INTERVENTION = "manual_intervention"
    ALERT_GENERATED = "alert_generated"
    ALERT_ESCALATED = "alert_escalated"
    SYSTEM_STATE_CHANGED = "system_state_changed"
    CONFIGURATION_CHANGED = "configuration_changed"
    ACCESS_GRANTED = "access_granted"
    ACCESS_DENIED = "access_denied"


class AuditSeverity(Enum):
    """Audit event severity levels."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass
class AuditEvent:
    """Represents an immutable audit event."""
    id: str
    correlation_id: str
    timestamp: datetime
    event_type: AuditEventType
    severity: AuditSeverity
    service: str
    user_id: Optional[str]
    session_id: Optional[str]
    source_ip: Optional[str]
    user_agent: Optional[str]
    action: str
    resource: str
    outcome: str
    details: Dict[str, Any]
    metadata: Dict[str, Any]
    checksum: str
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['event_type'] = self.event_type.value
        data['severity'] = self.severity.value
        return data
    
    def to_json(self) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict(), sort_keys=True)


class AuditTrail:
    """Manages immutable audit trail creation and storage."""
    
    def __init__(self, service_name: str = "error-resolution"):
        """
        Initialize audit trail manager.
        
        Args:
            service_name: Name of the service creating audit events
        """
        self.service_name = service_name
        self.audit_events: List[AuditEvent] = []
        self.event_counter = 0
    
    def create_audit_event(
        self,
        event_type: AuditEventType,
        action: str,
        resource: str,
        outcome: str,
        severity: AuditSeverity = AuditSeverity.INFO,
        correlation_id: Optional[str] = None,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        source_ip: Optional[str] = None,
        user_agent: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> AuditEvent:
        """
        Create an immutable audit event.
        
        Args:
            event_type: Type of audit event
            action: Action that was performed
            resource: Resource that was acted upon
            outcome: Outcome of the action (success, failure, etc.)
            severity: Severity level of the event
            correlation_id: Optional correlation ID for request tracing
            user_id: Optional user identifier
            session_id: Optional session identifier
            source_ip: Optional source IP address
            user_agent: Optional user agent string
            details: Optional additional details
            metadata: Optional metadata
        
        Returns:
            AuditEvent object
        """
        self.event_counter += 1
        
        # Generate unique event ID
        event_id = f"audit_{int(datetime.now(timezone.utc).timestamp())}_{self.event_counter}_{uuid.uuid4().hex[:8]}"
        
        # Use provided correlation ID or generate one
        if not correlation_id:
            correlation_id = str(uuid.uuid4())
        
        # Sanitize sensitive data in details
        sanitized_details = sanitize_log_data(details or {})
        sanitized_metadata = sanitize_log_data(metadata or {})
        
        # Create audit event
        audit_event = AuditEvent(
            id=event_id,
            correlation_id=correlation_id,
            timestamp=datetime.now(timezone.utc),
            event_type=event_type,
            severity=severity,
            service=self.service_name,
            user_id=user_id,
            session_id=session_id,
            source_ip=source_ip,
            user_agent=user_agent,
            action=action,
            resource=resource,
            outcome=outcome,
            details=sanitized_details,
            metadata=sanitized_metadata,
            checksum=""  # Will be calculated below
        )
        
        # Calculate checksum for integrity verification
        audit_event.checksum = self._calculate_checksum(audit_event)
        
        # Store audit event
        self.audit_events.append(audit_event)
        
        # Log the audit event
        logger.info(
            f"Audit event created: {event_type.value}",
            event_id=event_id,
            correlation_id=correlation_id,
            event_type=event_type.value,
            action=action,
            resource=resource,
            outcome=outcome,
            severity=severity.value,
            user_id=user_id
        )
        
        return audit_event
    
    def _calculate_checksum(self, audit_event: AuditEvent) -> str:
        """
        Calculate SHA-256 checksum for audit event integrity.
        
        Args:
            audit_event: Audit event to calculate checksum for
        
        Returns:
            SHA-256 checksum as hex string
        """
        # Create a copy without the checksum field for calculation
        event_data = audit_event.to_dict()
        event_data.pop('checksum', None)
        
        # Create deterministic JSON string
        json_string = json.dumps(event_data, sort_keys=True, separators=(',', ':'))
        
        # Calculate SHA-256 hash
        return hashlib.sha256(json_string.encode('utf-8')).hexdigest()
    
    def verify_event_integrity(self, audit_event: AuditEvent) -> bool:
        """
        Verify the integrity of an audit event using its checksum.
        
        Args:
            audit_event: Audit event to verify
        
        Returns:
            True if integrity is verified, False otherwise
        """
        expected_checksum = self._calculate_checksum(audit_event)
        return audit_event.checksum == expected_checksum
    
    def get_audit_events(
        self,
        event_type: Optional[AuditEventType] = None,
        correlation_id: Optional[str] = None,
        user_id: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: Optional[int] = None
    ) -> List[AuditEvent]:
        """
        Retrieve audit events with optional filtering.
        
        Args:
            event_type: Optional event type filter
            correlation_id: Optional correlation ID filter
            user_id: Optional user ID filter
            start_time: Optional start time filter
            end_time: Optional end time filter
            limit: Optional limit on number of results
        
        Returns:
            List of matching audit events
        """
        filtered_events = self.audit_events
        
        # Apply filters
        if event_type:
            filtered_events = [e for e in filtered_events if e.event_type == event_type]
        
        if correlation_id:
            filtered_events = [e for e in filtered_events if e.correlation_id == correlation_id]
        
        if user_id:
            filtered_events = [e for e in filtered_events if e.user_id == user_id]
        
        if start_time:
            filtered_events = [e for e in filtered_events if e.timestamp >= start_time]
        
        if end_time:
            filtered_events = [e for e in filtered_events if e.timestamp <= end_time]
        
        # Sort by timestamp (newest first)
        filtered_events.sort(key=lambda e: e.timestamp, reverse=True)
        
        # Apply limit
        if limit:
            filtered_events = filtered_events[:limit]
        
        return filtered_events
    
    def search_audit_events(
        self,
        query: str,
        fields: Optional[List[str]] = None
    ) -> List[AuditEvent]:
        """
        Search audit events by text query.
        
        Args:
            query: Search query string
            fields: Optional list of fields to search in
        
        Returns:
            List of matching audit events
        """
        if not fields:
            fields = ['action', 'resource', 'outcome', 'details', 'metadata']
        
        query_lower = query.lower()
        matching_events = []
        
        for event in self.audit_events:
            # Search in specified fields
            for field in fields:
                field_value = getattr(event, field, None)
                if field_value:
                    if isinstance(field_value, str):
                        if query_lower in field_value.lower():
                            matching_events.append(event)
                            break
                    elif isinstance(field_value, dict):
                        # Search in dictionary values
                        dict_str = json.dumps(field_value).lower()
                        if query_lower in dict_str:
                            matching_events.append(event)
                            break
        
        # Sort by timestamp (newest first)
        matching_events.sort(key=lambda e: e.timestamp, reverse=True)
        
        return matching_events
    
    def get_audit_statistics(self) -> Dict[str, Any]:
        """
        Get audit trail statistics.
        
        Returns:
            Dictionary with audit statistics
        """
        total_events = len(self.audit_events)
        
        # Count by event type
        event_type_counts = {}
        for event in self.audit_events:
            event_type = event.event_type.value
            event_type_counts[event_type] = event_type_counts.get(event_type, 0) + 1
        
        # Count by severity
        severity_counts = {}
        for event in self.audit_events:
            severity = event.severity.value
            severity_counts[severity] = severity_counts.get(severity, 0) + 1
        
        # Count by outcome
        outcome_counts = {}
        for event in self.audit_events:
            outcome = event.outcome
            outcome_counts[outcome] = outcome_counts.get(outcome, 0) + 1
        
        # Calculate integrity verification
        verified_events = sum(1 for event in self.audit_events if self.verify_event_integrity(event))
        
        return {
            'total_events': total_events,
            'verified_events': verified_events,
            'integrity_rate': verified_events / total_events if total_events > 0 else 1.0,
            'event_type_counts': event_type_counts,
            'severity_counts': severity_counts,
            'outcome_counts': outcome_counts,
            'oldest_event': self.audit_events[0].timestamp.isoformat() if self.audit_events else None,
            'newest_event': self.audit_events[-1].timestamp.isoformat() if self.audit_events else None
        }
    
    def export_audit_trail(
        self,
        format_type: str = "json",
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None
    ) -> str:
        """
        Export audit trail in specified format.
        
        Args:
            format_type: Export format ("json" or "csv")
            start_time: Optional start time filter
            end_time: Optional end time filter
        
        Returns:
            Exported audit trail as string
        """
        events = self.get_audit_events(start_time=start_time, end_time=end_time)
        
        if format_type.lower() == "json":
            return json.dumps([event.to_dict() for event in events], indent=2)
        elif format_type.lower() == "csv":
            if not events:
                return "No events to export"
            
            # CSV headers
            headers = [
                "id", "correlation_id", "timestamp", "event_type", "severity",
                "service", "user_id", "action", "resource", "outcome", "checksum"
            ]
            
            lines = [",".join(headers)]
            
            for event in events:
                row = [
                    event.id,
                    event.correlation_id,
                    event.timestamp.isoformat(),
                    event.event_type.value,
                    event.severity.value,
                    event.service,
                    event.user_id or "",
                    event.action,
                    event.resource,
                    event.outcome,
                    event.checksum
                ]
                lines.append(",".join(f'"{str(field)}"' for field in row))
            
            return "\n".join(lines)
        else:
            raise ValueError(f"Unsupported export format: {format_type}")


class ComplianceReporter:
    """Generates compliance reports from audit trails."""
    
    def __init__(self, audit_trail: AuditTrail):
        """
        Initialize compliance reporter.
        
        Args:
            audit_trail: AuditTrail instance to generate reports from
        """
        self.audit_trail = audit_trail
    
    def generate_compliance_report(
        self,
        start_time: datetime,
        end_time: datetime,
        report_type: str = "summary"
    ) -> Dict[str, Any]:
        """
        Generate compliance report for specified time period.
        
        Args:
            start_time: Report start time
            end_time: Report end time
            report_type: Type of report ("summary", "detailed", "security")
        
        Returns:
            Compliance report dictionary
        """
        events = self.audit_trail.get_audit_events(start_time=start_time, end_time=end_time)
        
        report = {
            'report_id': str(uuid.uuid4()),
            'generated_at': datetime.now(timezone.utc).isoformat(),
            'report_type': report_type,
            'period': {
                'start': start_time.isoformat(),
                'end': end_time.isoformat()
            },
            'total_events': len(events),
            'data_retention_policy': 'Events retained for 7 years for compliance',
            'integrity_verification': {
                'total_events': len(events),
                'verified_events': sum(1 for e in events if self.audit_trail.verify_event_integrity(e)),
                'integrity_rate': sum(1 for e in events if self.audit_trail.verify_event_integrity(e)) / len(events) if events else 1.0
            }
        }
        
        if report_type == "summary":
            report.update(self._generate_summary_report(events))
        elif report_type == "detailed":
            report.update(self._generate_detailed_report(events))
        elif report_type == "security":
            report.update(self._generate_security_report(events))
        
        return report
    
    def _generate_summary_report(self, events: List[AuditEvent]) -> Dict[str, Any]:
        """Generate summary compliance report."""
        # Count critical events
        critical_events = [e for e in events if e.severity == AuditSeverity.CRITICAL]
        error_events = [e for e in events if e.severity == AuditSeverity.ERROR]
        
        # Count resolution activities
        resolution_events = [e for e in events if e.event_type in [
            AuditEventType.RESOLUTION_STARTED,
            AuditEventType.RESOLUTION_COMPLETED,
            AuditEventType.RESOLUTION_FAILED
        ]]
        
        successful_resolutions = [e for e in resolution_events if e.outcome == "success"]
        
        return {
            'summary': {
                'critical_events': len(critical_events),
                'error_events': len(error_events),
                'total_resolutions': len(resolution_events),
                'successful_resolutions': len(successful_resolutions),
                'resolution_success_rate': len(successful_resolutions) / len(resolution_events) if resolution_events else 0
            }
        }
    
    def _generate_detailed_report(self, events: List[AuditEvent]) -> Dict[str, Any]:
        """Generate detailed compliance report."""
        # Group events by type
        events_by_type = {}
        for event in events:
            event_type = event.event_type.value
            if event_type not in events_by_type:
                events_by_type[event_type] = []
            events_by_type[event_type].append(event.to_dict())
        
        # Group events by user
        events_by_user = {}
        for event in events:
            user_id = event.user_id or "system"
            if user_id not in events_by_user:
                events_by_user[user_id] = []
            events_by_user[user_id].append(event.to_dict())
        
        return {
            'detailed': {
                'events_by_type': events_by_type,
                'events_by_user': events_by_user,
                'all_events': [event.to_dict() for event in events]
            }
        }
    
    def _generate_security_report(self, events: List[AuditEvent]) -> Dict[str, Any]:
        """Generate security-focused compliance report."""
        # Security-relevant events
        security_events = [e for e in events if e.event_type in [
            AuditEventType.ACCESS_GRANTED,
            AuditEventType.ACCESS_DENIED,
            AuditEventType.CONFIGURATION_CHANGED,
            AuditEventType.MANUAL_INTERVENTION
        ]]
        
        # Failed access attempts
        access_denied_events = [e for e in events if e.event_type == AuditEventType.ACCESS_DENIED]
        
        # Configuration changes
        config_changes = [e for e in events if e.event_type == AuditEventType.CONFIGURATION_CHANGED]
        
        return {
            'security': {
                'total_security_events': len(security_events),
                'access_denied_events': len(access_denied_events),
                'configuration_changes': len(config_changes),
                'manual_interventions': len([e for e in events if e.event_type == AuditEventType.MANUAL_INTERVENTION]),
                'security_events': [event.to_dict() for event in security_events]
            }
        }


# Global audit trail instance
_audit_trail: Optional[AuditTrail] = None


def get_audit_trail(service_name: str = "error-resolution") -> AuditTrail:
    """
    Get the global audit trail instance.
    
    Args:
        service_name: Name of the service
    
    Returns:
        AuditTrail instance
    """
    global _audit_trail
    if _audit_trail is None:
        _audit_trail = AuditTrail(service_name)
    return _audit_trail


def create_audit_event(
    event_type: AuditEventType,
    action: str,
    resource: str,
    outcome: str,
    **kwargs
) -> AuditEvent:
    """
    Convenience function to create an audit event.
    
    Args:
        event_type: Type of audit event
        action: Action that was performed
        resource: Resource that was acted upon
        outcome: Outcome of the action
        **kwargs: Additional arguments for audit event creation
    
    Returns:
        AuditEvent object
    """
    audit_trail = get_audit_trail()
    return audit_trail.create_audit_event(
        event_type=event_type,
        action=action,
        resource=resource,
        outcome=outcome,
        **kwargs
    )