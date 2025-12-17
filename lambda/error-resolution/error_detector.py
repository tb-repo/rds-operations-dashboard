"""
Error Detection and Classification System

Provides real-time error detection, classification, and severity assessment
for API errors in the RDS Operations Dashboard.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-11T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.1 → DESIGN-ErrorDetection → TASK-1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import re
import json
import time
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Tuple
from enum import Enum
from dataclasses import dataclass, asdict
import logging
import sys
import os

# Add monitoring module to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'monitoring'))

# Import performance optimization
from performance_optimizer import get_performance_optimizer, optimize_error_detection

logger = logging.getLogger(__name__)


class ErrorSeverity(Enum):
    """Error severity levels."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class ErrorCategory(Enum):
    """Error categories for classification."""
    AUTHENTICATION = "authentication"
    AUTHORIZATION = "authorization"
    DATABASE = "database"
    NETWORK = "network"
    TIMEOUT = "timeout"
    RATE_LIMIT = "rate_limit"
    CONFIGURATION = "configuration"
    RESOURCE = "resource"
    UNKNOWN = "unknown"


@dataclass
class APIError:
    """Represents a detected API error with classification."""
    id: str
    timestamp: datetime
    status_code: int
    message: str
    service: str
    endpoint: str
    request_id: str
    user_id: Optional[str]
    category: ErrorCategory
    severity: ErrorSeverity
    context: Dict[str, Any]
    stack_trace: Optional[str] = None
    resolution_attempted: bool = False
    resolution_successful: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['category'] = self.category.value
        data['severity'] = self.severity.value
        return data


class ErrorPatternMatcher:
    """Matches error patterns to classify errors with performance optimization."""
    
    # Error patterns for classification
    PATTERNS = {
        ErrorCategory.AUTHENTICATION: [
            r'authentication.*failed',
            r'invalid.*credentials',
            r'token.*expired',
            r'unauthorized',
            r'cognito.*error',
            r'jwt.*invalid'
        ],
        ErrorCategory.AUTHORIZATION: [
            r'access.*denied',
            r'forbidden',
            r'insufficient.*permissions',
            r'iam.*role.*not.*found',
            r'assume.*role.*failed',
            r'permission.*denied'
        ],
        ErrorCategory.DATABASE: [
            r'database.*connection.*failed',
            r'rds.*unavailable',
            r'connection.*timeout.*database',
            r'database.*error',
            r'sql.*error',
            r'dynamodb.*(error|operation.*failed)'
        ],
        ErrorCategory.NETWORK: [
            r'network.*error',
            r'connection.*refused',
            r'dns.*resolution.*failed',
            r'endpoint.*unreachable',
            r'socket.*timeout',
            r'ssl.*error'
        ],
        ErrorCategory.TIMEOUT: [
            r'timeout',
            r'request.*timed.*out',
            r'lambda.*timeout',
            r'gateway.*timeout',
            r'read.*timeout'
        ],
        ErrorCategory.RATE_LIMIT: [
            r'rate.*limit.*exceeded',
            r'throttling',
            r'too.*many.*requests',
            r'quota.*exceeded',
            r'api.*limit.*reached'
        ],
        ErrorCategory.CONFIGURATION: [
            r'configuration.*error',
            r'environment.*variable.*missing',
            r'invalid.*configuration',
            r'missing.*parameter',
            r'config.*not.*found'
        ],
        ErrorCategory.RESOURCE: [
            r'resource.*not.*found',
            r'service.*unavailable',
            r'internal.*server.*error',
            r'out.*of.*memory',
            r'disk.*full'
        ]
    }
    
    # Severity patterns based on status codes and keywords
    SEVERITY_PATTERNS = {
        ErrorSeverity.CRITICAL: [
            r'critical.*error',
            r'system.*failure',
            r'service.*down',
            r'database.*unavailable'
        ],
        ErrorSeverity.HIGH: [
            r'internal.*server.*error',
            r'service.*unavailable',
            r'authentication.*failed',
            r'access.*denied'
        ],
        ErrorSeverity.MEDIUM: [
            r'timeout',
            r'rate.*limit',
            r'throttling',
            r'bad.*request'
        ],
        ErrorSeverity.LOW: [
            r'not.*found',
            r'validation.*error',
            r'invalid.*input'
        ]
    }
    
    def __init__(self):
        """Initialize pattern matcher with compiled regex patterns and caching."""
        self.compiled_patterns = {}
        self.compiled_severity_patterns = {}
        self.performance_optimizer = get_performance_optimizer()
        
        # Compile category patterns with caching
        for category, patterns in self.PATTERNS.items():
            compiled_list = []
            for pattern in patterns:
                # Try to get from cache first
                cached_pattern = self.performance_optimizer.pattern_cache.get_compiled_pattern(pattern)
                if cached_pattern is not None:
                    compiled_list.append(cached_pattern)
                else:
                    # Compile and cache
                    compiled = re.compile(pattern, re.IGNORECASE)
                    self.performance_optimizer.pattern_cache.cache_compiled_pattern(pattern, compiled)
                    compiled_list.append(compiled)
            self.compiled_patterns[category] = compiled_list
        
        # Compile severity patterns with caching
        for severity, patterns in self.SEVERITY_PATTERNS.items():
            compiled_list = []
            for pattern in patterns:
                # Try to get from cache first
                cached_pattern = self.performance_optimizer.pattern_cache.get_compiled_pattern(pattern)
                if cached_pattern is not None:
                    compiled_list.append(cached_pattern)
                else:
                    # Compile and cache
                    compiled = re.compile(pattern, re.IGNORECASE)
                    self.performance_optimizer.pattern_cache.cache_compiled_pattern(pattern, compiled)
                    compiled_list.append(compiled)
            self.compiled_severity_patterns[severity] = compiled_list
    
    def classify_error(self, error_message: str, status_code: int) -> ErrorCategory:
        """
        Classify error based on message and status code with optimization.
        
        Args:
            error_message: The error message to classify
            status_code: HTTP status code
        
        Returns:
            ErrorCategory enum value
        """
        # Optimize by checking status code first for common cases (faster than regex)
        if status_code == 401:
            return ErrorCategory.AUTHENTICATION
        elif status_code == 403:
            return ErrorCategory.AUTHORIZATION
        elif status_code == 404:
            return ErrorCategory.RESOURCE
        elif status_code == 429:
            return ErrorCategory.RATE_LIMIT
        elif status_code == 504:
            return ErrorCategory.TIMEOUT
        
        # For other status codes, check message patterns
        # Optimize by checking most common categories first
        priority_categories = [
            ErrorCategory.DATABASE,
            ErrorCategory.AUTHENTICATION,
            ErrorCategory.AUTHORIZATION,
            ErrorCategory.TIMEOUT,
            ErrorCategory.NETWORK,
            ErrorCategory.RATE_LIMIT,
            ErrorCategory.CONFIGURATION,
            ErrorCategory.RESOURCE
        ]
        
        for category in priority_categories:
            if category in self.compiled_patterns:
                for pattern in self.compiled_patterns[category]:
                    if pattern.search(error_message):
                        return category
        
        # Fallback for 5xx errors
        if status_code >= 500:
            return ErrorCategory.RESOURCE
        
        return ErrorCategory.UNKNOWN
    
    def assess_severity(self, error_message: str, status_code: int, category: ErrorCategory) -> ErrorSeverity:
        """
        Assess error severity based on message, status code, and category.
        
        Args:
            error_message: The error message
            status_code: HTTP status code
            category: Error category
        
        Returns:
            ErrorSeverity enum value
        """
        # Critical status codes
        if status_code >= 500 and status_code != 503:
            if category in [ErrorCategory.DATABASE, ErrorCategory.AUTHENTICATION]:
                return ErrorSeverity.CRITICAL
            return ErrorSeverity.HIGH
        
        # Check message patterns for severity
        for severity, patterns in self.compiled_severity_patterns.items():
            for pattern in patterns:
                if pattern.search(error_message):
                    return severity
        
        # Default severity based on status code
        if status_code >= 500:
            return ErrorSeverity.HIGH
        elif status_code >= 400:
            return ErrorSeverity.MEDIUM
        else:
            return ErrorSeverity.LOW


class ErrorDetector:
    """Main error detection and classification service."""
    
    def __init__(self):
        """Initialize error detector."""
        self.pattern_matcher = ErrorPatternMatcher()
        self.error_count = 0
        
    def detect_and_classify(
        self,
        status_code: int,
        error_message: str,
        service: str,
        endpoint: str,
        request_id: str,
        context: Dict[str, Any],
        user_id: Optional[str] = None,
        stack_trace: Optional[str] = None
    ) -> APIError:
        """
        Detect and classify an API error.
        
        Args:
            status_code: HTTP status code
            error_message: Error message
            service: Service name where error occurred
            endpoint: API endpoint
            request_id: Request identifier
            context: Additional context information
            user_id: Optional user identifier
            stack_trace: Optional stack trace
        
        Returns:
            APIError object with classification
        """
        self.error_count += 1
        
        # Generate unique error ID
        error_id = f"err_{int(datetime.now(timezone.utc).timestamp())}_{self.error_count}"
        
        # Classify error
        category = self.pattern_matcher.classify_error(error_message, status_code)
        severity = self.pattern_matcher.assess_severity(error_message, status_code, category)
        
        # Create error object
        api_error = APIError(
            id=error_id,
            timestamp=datetime.now(timezone.utc),
            status_code=status_code,
            message=error_message,
            service=service,
            endpoint=endpoint,
            request_id=request_id,
            user_id=user_id,
            category=category,
            severity=severity,
            context=context,
            stack_trace=stack_trace
        )
        
        # Record metrics for the error (optimized for performance)
        try:
            from metrics_collector import get_metrics_collector
            metrics_collector = get_metrics_collector()
            
            # Use optimized metric collection with minimal overhead
            start_time = time.perf_counter()
            metrics_collector.collect_error_metric(
                service=service,
                endpoint=endpoint,
                error_type=category.value,
                severity=severity.value,
                user_id=user_id,
                response_time_ms=context.get('response_time_ms'),
                resolution_attempt_id=None  # Will be set later if resolution is attempted
            )
            
            # Track metrics collection performance (only log if very slow)
            collection_time = time.perf_counter() - start_time
            if collection_time > 0.5:  # Only log if > 500ms (very slow)
                logger.warning(f"Slow metrics collection: {collection_time:.3f}s")
                
        except Exception as e:
            # Don't let metrics collection failures slow down error detection
            logger.debug(f"Failed to record error metrics: {str(e)}")
        
        # Log the detected error
        logger.info(
            f"Error detected and classified: {error_id}",
            extra={
                'error_id': error_id,
                'category': category.value,
                'severity': severity.value,
                'status_code': status_code,
                'service': service,
                'endpoint': endpoint
            }
        )
        
        return api_error
    
    def is_critical_error(self, api_error: APIError) -> bool:
        """
        Check if an error is critical and requires immediate attention.
        
        Args:
            api_error: The API error to check
        
        Returns:
            True if error is critical
        """
        return (
            api_error.severity == ErrorSeverity.CRITICAL or
            (api_error.status_code >= 500 and 
             api_error.category in [ErrorCategory.DATABASE, ErrorCategory.AUTHENTICATION])
        )
    
    def should_retry(self, api_error: APIError) -> bool:
        """
        Determine if an error should be retried.
        
        Args:
            api_error: The API error to check
        
Returns:
            True if error should be retried
        """
        # Don't retry client errors (4xx) except for specific cases
        if 400 <= api_error.status_code < 500:
            # Retry authentication errors (token might be refreshable)
            if api_error.category == ErrorCategory.AUTHENTICATION:
                return True
            # Retry rate limiting
            if api_error.category == ErrorCategory.RATE_LIMIT:
                return True
            # Don't retry other 4xx errors
            return False
        
        # Retry server errors (5xx)
        if api_error.status_code >= 500:
            return True
        
        # Retry network and timeout errors
        if api_error.category in [ErrorCategory.NETWORK, ErrorCategory.TIMEOUT]:
            return True
        
        return False
    
    def get_error_statistics(self) -> Dict[str, Any]:
        """
        Get error detection statistics.
        
        Returns:
            Dictionary with error statistics
        """
        return {
            'total_errors_detected': self.error_count,
            'detector_version': '1.0.0',
            'patterns_loaded': len(self.pattern_matcher.compiled_patterns),
            'severity_patterns_loaded': len(self.pattern_matcher.compiled_severity_patterns)
        }


# Global error detector instance
_error_detector: Optional[ErrorDetector] = None


def get_error_detector() -> ErrorDetector:
    """
    Get the global error detector instance.
    
    Returns:
        ErrorDetector instance
    """
    global _error_detector
    if _error_detector is None:
        _error_detector = ErrorDetector()
    return _error_detector


def detect_api_error(
    status_code: int,
    error_message: str,
    service: str,
    endpoint: str,
    request_id: str,
    context: Dict[str, Any],
    user_id: Optional[str] = None,
    stack_trace: Optional[str] = None
) -> APIError:
    """
    Convenience function to detect and classify an API error.
    
    Args:
        status_code: HTTP status code
        error_message: Error message
        service: Service name
        endpoint: API endpoint
        request_id: Request identifier
        context: Additional context
        user_id: Optional user identifier
        stack_trace: Optional stack trace
    
    Returns:
        APIError object with classification
    """
    detector = get_error_detector()
    return detector.detect_and_classify(
        status_code=status_code,
        error_message=error_message,
        service=service,
        endpoint=endpoint,
        request_id=request_id,
        context=context,
        user_id=user_id,
        stack_trace=stack_trace
    )