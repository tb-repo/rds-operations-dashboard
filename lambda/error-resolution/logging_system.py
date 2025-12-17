"""
Comprehensive Logging System for Error Resolution

Provides structured logging, log analysis, search capabilities, and integration
with the audit trail system for complete observability.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-15T14:45:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-5.1, 5.3 → DESIGN-LoggingSystem → TASK-5",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import json
import re
import uuid
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional, Union, Callable
from enum import Enum
from dataclasses import dataclass, asdict
import logging
import os
from collections import defaultdict, deque

# Import shared modules
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

try:
    from structured_logger import StructuredLogger, get_logger, sanitize_log_data
    from audit_system import get_audit_trail, AuditEventType, AuditSeverity, create_audit_event
except ImportError:
    # Fallback for testing
    def get_logger(service_name, **kwargs):
        return logging.getLogger(service_name)
    def sanitize_log_data(data):
        return data
    def get_audit_trail():
        return None
    def create_audit_event(*args, **kwargs):
        pass

logger = get_logger('logging-system')


class LogLevel(Enum):
    """Log levels for structured logging."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class LogCategory(Enum):
    """Categories for log classification."""
    SYSTEM = "system"
    SECURITY = "security"
    PERFORMANCE = "performance"
    BUSINESS = "business"
    AUDIT = "audit"
    ERROR = "error"
    RESOLUTION = "resolution"
    MONITORING = "monitoring"


@dataclass
class LogEntry:
    """Represents a structured log entry."""
    id: str
    timestamp: datetime
    level: LogLevel
    category: LogCategory
    service: str
    correlation_id: str
    message: str
    details: Dict[str, Any]
    metadata: Dict[str, Any]
    tags: List[str]
    source_file: Optional[str] = None
    source_line: Optional[int] = None
    function_name: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['level'] = self.level.value
        data['category'] = self.category.value
        return data
    
    def to_json(self) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict(), sort_keys=True)


class LogBuffer:
    """In-memory buffer for log entries with size limits."""
    
    def __init__(self, max_size: int = 10000):
        """
        Initialize log buffer.
        
        Args:
            max_size: Maximum number of log entries to keep in memory
        """
        self.max_size = max_size
        self.entries = deque(maxlen=max_size)
        self.total_entries = 0
    
    def add_entry(self, entry: LogEntry):
        """Add a log entry to the buffer."""
        self.entries.append(entry)
        self.total_entries += 1
    
    def get_entries(
        self,
        level: Optional[LogLevel] = None,
        category: Optional[LogCategory] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: Optional[int] = None
    ) -> List[LogEntry]:
        """
        Get log entries with optional filtering.
        
        Args:
            level: Optional log level filter
            category: Optional category filter
            start_time: Optional start time filter
            end_time: Optional end time filter
            limit: Optional limit on number of results
        
        Returns:
            List of matching log entries
        """
        filtered_entries = list(self.entries)
        
        # Apply filters
        if level:
            filtered_entries = [e for e in filtered_entries if e.level == level]
        
        if category:
            filtered_entries = [e for e in filtered_entries if e.category == category]
        
        if start_time:
            filtered_entries = [e for e in filtered_entries if e.timestamp >= start_time]
        
        if end_time:
            filtered_entries = [e for e in filtered_entries if e.timestamp <= end_time]
        
        # Sort by timestamp (newest first)
        filtered_entries.sort(key=lambda e: e.timestamp, reverse=True)
        
        # Apply limit
        if limit:
            filtered_entries = filtered_entries[:limit]
        
        return filtered_entries
    
    def search_entries(self, query: str, fields: Optional[List[str]] = None) -> List[LogEntry]:
        """
        Search log entries by text query.
        
        Args:
            query: Search query string
            fields: Optional list of fields to search in
        
        Returns:
            List of matching log entries
        """
        if not fields:
            fields = ['message', 'details', 'metadata', 'tags']
        
        query_lower = query.lower()
        matching_entries = []
        
        for entry in self.entries:
            # Search in specified fields
            for field in fields:
                field_value = getattr(entry, field, None)
                if field_value:
                    if isinstance(field_value, str):
                        if query_lower in field_value.lower():
                            matching_entries.append(entry)
                            break
                    elif isinstance(field_value, (dict, list)):
                        # Search in dictionary/list values
                        field_str = json.dumps(field_value).lower()
                        if query_lower in field_str:
                            matching_entries.append(entry)
                            break
        
        # Sort by timestamp (newest first)
        matching_entries.sort(key=lambda e: e.timestamp, reverse=True)
        
        return matching_entries
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get buffer statistics."""
        level_counts = defaultdict(int)
        category_counts = defaultdict(int)
        
        for entry in self.entries:
            level_counts[entry.level.value] += 1
            category_counts[entry.category.value] += 1
        
        return {
            'current_entries': len(self.entries),
            'total_entries': self.total_entries,
            'max_size': self.max_size,
            'level_counts': dict(level_counts),
            'category_counts': dict(category_counts),
            'oldest_entry': self.entries[0].timestamp.isoformat() if self.entries else None,
            'newest_entry': self.entries[-1].timestamp.isoformat() if self.entries else None
        }


class LogAnalyzer:
    """Analyzes log patterns and generates insights."""
    
    def __init__(self, log_buffer: LogBuffer):
        """
        Initialize log analyzer.
        
        Args:
            log_buffer: LogBuffer instance to analyze
        """
        self.log_buffer = log_buffer
    
    def analyze_error_patterns(self, time_window: timedelta = timedelta(hours=1)) -> Dict[str, Any]:
        """
        Analyze error patterns in recent logs.
        
        Args:
            time_window: Time window to analyze
        
        Returns:
            Dictionary with error pattern analysis
        """
        cutoff_time = datetime.now(timezone.utc) - time_window
        error_entries = self.log_buffer.get_entries(
            level=LogLevel.ERROR,
            start_time=cutoff_time
        )
        
        # Group errors by message patterns
        error_patterns = defaultdict(list)
        for entry in error_entries:
            # Extract error pattern (simplified)
            pattern = self._extract_error_pattern(entry.message)
            error_patterns[pattern].append(entry)
        
        # Sort patterns by frequency
        sorted_patterns = sorted(
            error_patterns.items(),
            key=lambda x: len(x[1]),
            reverse=True
        )
        
        return {
            'time_window': str(time_window),
            'total_errors': len(error_entries),
            'unique_patterns': len(error_patterns),
            'top_patterns': [
                {
                    'pattern': pattern,
                    'count': len(entries),
                    'first_occurrence': min(e.timestamp for e in entries).isoformat(),
                    'last_occurrence': max(e.timestamp for e in entries).isoformat(),
                    'services': list(set(e.service for e in entries))
                }
                for pattern, entries in sorted_patterns[:10]
            ]
        }
    
    def analyze_performance_trends(self, time_window: timedelta = timedelta(hours=1)) -> Dict[str, Any]:
        """
        Analyze performance trends in logs.
        
        Args:
            time_window: Time window to analyze
        
        Returns:
            Dictionary with performance trend analysis
        """
        cutoff_time = datetime.now(timezone.utc) - time_window
        perf_entries = self.log_buffer.get_entries(
            category=LogCategory.PERFORMANCE,
            start_time=cutoff_time
        )
        
        # Extract performance metrics
        response_times = []
        throughput_data = []
        
        for entry in perf_entries:
            details = entry.details
            if 'duration_ms' in details:
                response_times.append(details['duration_ms'])
            if 'requests_per_second' in details:
                throughput_data.append(details['requests_per_second'])
        
        # Calculate statistics
        avg_response_time = sum(response_times) / len(response_times) if response_times else 0
        max_response_time = max(response_times) if response_times else 0
        min_response_time = min(response_times) if response_times else 0
        
        avg_throughput = sum(throughput_data) / len(throughput_data) if throughput_data else 0
        
        return {
            'time_window': str(time_window),
            'total_performance_entries': len(perf_entries),
            'response_time_stats': {
                'average_ms': avg_response_time,
                'max_ms': max_response_time,
                'min_ms': min_response_time,
                'sample_count': len(response_times)
            },
            'throughput_stats': {
                'average_rps': avg_throughput,
                'sample_count': len(throughput_data)
            }
        }
    
    def detect_anomalies(self, time_window: timedelta = timedelta(hours=1)) -> Dict[str, Any]:
        """
        Detect anomalies in log patterns.
        
        Args:
            time_window: Time window to analyze
        
        Returns:
            Dictionary with anomaly detection results
        """
        cutoff_time = datetime.now(timezone.utc) - time_window
        recent_entries = self.log_buffer.get_entries(start_time=cutoff_time)
        
        anomalies = []
        
        # Detect error rate spikes
        error_entries = [e for e in recent_entries if e.level == LogLevel.ERROR]
        error_rate = len(error_entries) / len(recent_entries) if recent_entries else 0
        
        if error_rate > 0.1:  # More than 10% errors
            anomalies.append({
                'type': 'high_error_rate',
                'severity': 'high' if error_rate > 0.2 else 'medium',
                'description': f'Error rate is {error_rate:.2%}, which is above normal threshold',
                'value': error_rate,
                'threshold': 0.1
            })
        
        # Detect unusual log volume
        entries_per_minute = len(recent_entries) / (time_window.total_seconds() / 60)
        if entries_per_minute > 100:  # More than 100 logs per minute
            anomalies.append({
                'type': 'high_log_volume',
                'severity': 'medium',
                'description': f'Log volume is {entries_per_minute:.1f} entries/minute, which is above normal',
                'value': entries_per_minute,
                'threshold': 100
            })
        
        # Detect repeated error patterns
        error_patterns = defaultdict(int)
        for entry in error_entries:
            pattern = self._extract_error_pattern(entry.message)
            error_patterns[pattern] += 1
        
        for pattern, count in error_patterns.items():
            if count > 5:  # Same error pattern more than 5 times
                anomalies.append({
                    'type': 'repeated_error_pattern',
                    'severity': 'medium',
                    'description': f'Error pattern "{pattern}" occurred {count} times',
                    'value': count,
                    'threshold': 5,
                    'pattern': pattern
                })
        
        return {
            'time_window': str(time_window),
            'total_entries_analyzed': len(recent_entries),
            'anomalies_detected': len(anomalies),
            'anomalies': anomalies
        }
    
    def _extract_error_pattern(self, message: str) -> str:
        """
        Extract error pattern from message by removing variable parts.
        
        Args:
            message: Error message
        
        Returns:
            Generalized error pattern
        """
        # Remove common variable patterns
        pattern = re.sub(r'\b\d+\b', '[NUMBER]', message)  # Numbers
        pattern = re.sub(r'\b[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\b', '[UUID]', pattern)  # UUIDs
        pattern = re.sub(r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', '[TIMESTAMP]', pattern)  # ISO timestamps
        pattern = re.sub(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b', '[EMAIL]', pattern)  # Email addresses
        pattern = re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IP]', pattern)  # IP addresses
        
        return pattern.strip()


class ComprehensiveLogger:
    """Main comprehensive logging system."""
    
    def __init__(self, service_name: str = "error-resolution", buffer_size: int = 10000):
        """
        Initialize comprehensive logger.
        
        Args:
            service_name: Name of the service
            buffer_size: Size of the in-memory log buffer
        """
        self.service_name = service_name
        self.log_buffer = LogBuffer(buffer_size)
        self.log_analyzer = LogAnalyzer(self.log_buffer)
        self.structured_logger = get_logger(service_name)
        self.audit_trail = get_audit_trail(service_name)
        self.entry_counter = 0
    
    def log(
        self,
        level: LogLevel,
        message: str,
        category: LogCategory = LogCategory.SYSTEM,
        correlation_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None,
        tags: Optional[List[str]] = None,
        create_audit: bool = False,
        audit_action: Optional[str] = None,
        audit_resource: Optional[str] = None,
        audit_outcome: Optional[str] = None
    ) -> LogEntry:
        """
        Create a comprehensive log entry.
        
        Args:
            level: Log level
            message: Log message
            category: Log category
            correlation_id: Optional correlation ID
            details: Optional additional details
            metadata: Optional metadata
            tags: Optional tags for categorization
            create_audit: Whether to create an audit event
            audit_action: Action for audit event (required if create_audit=True)
            audit_resource: Resource for audit event (required if create_audit=True)
            audit_outcome: Outcome for audit event (required if create_audit=True)
        
        Returns:
            LogEntry object
        """
        self.entry_counter += 1
        
        # Generate unique log entry ID
        entry_id = f"log_{int(datetime.now(timezone.utc).timestamp())}_{self.entry_counter}_{uuid.uuid4().hex[:8]}"
        
        # Use provided correlation ID or generate one
        if not correlation_id:
            correlation_id = str(uuid.uuid4())
        
        # Sanitize sensitive data
        sanitized_details = sanitize_log_data(details or {})
        sanitized_metadata = sanitize_log_data(metadata or {})
        
        # Remove 'category' from details/metadata to avoid parameter conflicts
        sanitized_details.pop('category', None)
        sanitized_metadata.pop('category', None)
        
        # Create log entry
        log_entry = LogEntry(
            id=entry_id,
            timestamp=datetime.now(timezone.utc),
            level=level,
            category=category,
            service=self.service_name,
            correlation_id=correlation_id,
            message=message,
            details=sanitized_details,
            metadata=sanitized_metadata,
            tags=tags or []
        )
        
        # Add to buffer
        self.log_buffer.add_entry(log_entry)
        
        # Log using structured logger
        # Map CRITICAL to ERROR since structured logger doesn't have critical method
        log_level = level.value.lower()
        if log_level == 'critical':
            log_level = 'error'
        
        log_method = getattr(self.structured_logger, log_level)
        log_method(
            message,
            log_id=entry_id,
            category=category.value,
            correlation_id=correlation_id,
            **sanitized_details,
            **sanitized_metadata
        )
        
        # Create audit event if requested
        if create_audit and audit_action and audit_resource and audit_outcome:
            # Map log level to audit severity
            audit_severity = AuditSeverity.INFO
            if level == LogLevel.ERROR:
                audit_severity = AuditSeverity.ERROR
            elif level == LogLevel.CRITICAL:
                audit_severity = AuditSeverity.CRITICAL
            elif level == LogLevel.WARNING:
                audit_severity = AuditSeverity.WARNING
            
            # Map category to audit event type
            event_type = AuditEventType.SYSTEM_STATE_CHANGED
            if category == LogCategory.SECURITY:
                event_type = AuditEventType.ACCESS_GRANTED if audit_outcome == "success" else AuditEventType.ACCESS_DENIED
            elif category == LogCategory.ERROR:
                event_type = AuditEventType.ERROR_DETECTED
            elif category == LogCategory.RESOLUTION:
                if "started" in audit_action.lower():
                    event_type = AuditEventType.RESOLUTION_STARTED
                elif "completed" in audit_action.lower():
                    event_type = AuditEventType.RESOLUTION_COMPLETED
                elif "failed" in audit_action.lower():
                    event_type = AuditEventType.RESOLUTION_FAILED
            
            create_audit_event(
                event_type=event_type,
                action=audit_action,
                resource=audit_resource,
                outcome=audit_outcome,
                severity=audit_severity,
                correlation_id=correlation_id,
                details=sanitized_details,
                metadata=sanitized_metadata
            )
        
        return log_entry
    
    def debug(self, message: str, **kwargs) -> LogEntry:
        """Log debug message."""
        return self.log(LogLevel.DEBUG, message, **kwargs)
    
    def info(self, message: str, **kwargs) -> LogEntry:
        """Log info message."""
        return self.log(LogLevel.INFO, message, **kwargs)
    
    def warning(self, message: str, **kwargs) -> LogEntry:
        """Log warning message."""
        return self.log(LogLevel.WARNING, message, **kwargs)
    
    def error(self, message: str, **kwargs) -> LogEntry:
        """Log error message."""
        return self.log(LogLevel.ERROR, message, **kwargs)
    
    def critical(self, message: str, **kwargs) -> LogEntry:
        """Log critical message."""
        return self.log(LogLevel.CRITICAL, message, **kwargs)
    
    def search_logs(self, query: str, **filters) -> List[LogEntry]:
        """
        Search logs with text query and optional filters.
        
        Args:
            query: Search query string
            **filters: Optional filters (level, category, start_time, end_time, limit)
        
        Returns:
            List of matching log entries
        """
        if query:
            # First search by text
            entries = self.log_buffer.search_entries(query)
        else:
            # Get all entries
            entries = list(self.log_buffer.entries)
        
        # Apply additional filters
        if 'level' in filters:
            entries = [e for e in entries if e.level == filters['level']]
        
        if 'category' in filters:
            entries = [e for e in entries if e.category == filters['category']]
        
        if 'start_time' in filters:
            entries = [e for e in entries if e.timestamp >= filters['start_time']]
        
        if 'end_time' in filters:
            entries = [e for e in entries if e.timestamp <= filters['end_time']]
        
        # Sort by timestamp (newest first)
        entries.sort(key=lambda e: e.timestamp, reverse=True)
        
        # Apply limit
        if 'limit' in filters:
            entries = entries[:filters['limit']]
        
        return entries
    
    def get_log_statistics(self) -> Dict[str, Any]:
        """Get comprehensive logging statistics."""
        buffer_stats = self.log_buffer.get_statistics()
        
        # Add analyzer insights
        error_analysis = self.log_analyzer.analyze_error_patterns()
        performance_analysis = self.log_analyzer.analyze_performance_trends()
        anomaly_detection = self.log_analyzer.detect_anomalies()
        
        return {
            'buffer_statistics': buffer_stats,
            'error_analysis': error_analysis,
            'performance_analysis': performance_analysis,
            'anomaly_detection': anomaly_detection,
            'logger_version': '1.0.0'
        }
    
    def export_logs(
        self,
        format_type: str = "json",
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        level: Optional[LogLevel] = None,
        category: Optional[LogCategory] = None
    ) -> str:
        """
        Export logs in specified format.
        
        Args:
            format_type: Export format ("json" or "csv")
            start_time: Optional start time filter
            end_time: Optional end time filter
            level: Optional log level filter
            category: Optional category filter
        
        Returns:
            Exported logs as string
        """
        entries = self.log_buffer.get_entries(
            level=level,
            category=category,
            start_time=start_time,
            end_time=end_time
        )
        
        if format_type.lower() == "json":
            return json.dumps([entry.to_dict() for entry in entries], indent=2)
        elif format_type.lower() == "csv":
            if not entries:
                return "No logs to export"
            
            # CSV headers
            headers = [
                "id", "timestamp", "level", "category", "service",
                "correlation_id", "message", "tags"
            ]
            
            lines = [",".join(headers)]
            
            for entry in entries:
                row = [
                    entry.id,
                    entry.timestamp.isoformat(),
                    entry.level.value,
                    entry.category.value,
                    entry.service,
                    entry.correlation_id,
                    entry.message,
                    "|".join(entry.tags)
                ]
                lines.append(",".join(f'"{str(field)}"' for field in row))
            
            return "\n".join(lines)
        else:
            raise ValueError(f"Unsupported export format: {format_type}")


# Global comprehensive logger instance
_comprehensive_logger: Optional[ComprehensiveLogger] = None


def get_comprehensive_logger(service_name: str = "error-resolution") -> ComprehensiveLogger:
    """
    Get the global comprehensive logger instance.
    
    Args:
        service_name: Name of the service
    
    Returns:
        ComprehensiveLogger instance
    """
    global _comprehensive_logger
    if _comprehensive_logger is None:
        _comprehensive_logger = ComprehensiveLogger(service_name)
    return _comprehensive_logger


def log_operation(
    message: str,
    level: LogLevel = LogLevel.INFO,
    category: LogCategory = LogCategory.SYSTEM,
    **kwargs
) -> LogEntry:
    """
    Convenience function to log an operation.
    
    Args:
        message: Log message
        level: Log level
        category: Log category
        **kwargs: Additional arguments
    
    Returns:
        LogEntry object
    """
    logger = get_comprehensive_logger()
    return logger.log(level, message, category, **kwargs)