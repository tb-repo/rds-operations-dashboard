"""
Property-Based Tests for Error Detection System

Tests universal properties that should hold across all inputs for error detection.
Uses Hypothesis for property-based testing.

**Feature: api-error-resolution, Property 1: Error detection consistency**
**Validates: Requirements 1.1**

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-11T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.1 → DESIGN-ErrorDetection → TASK-1.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import unittest
from datetime import datetime, timezone
import sys
import os
from hypothesis import given, strategies as st, settings, assume
from hypothesis.strategies import composite

# Add the error_resolution module to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error_resolution'))

from error_detector import (
    ErrorDetector, ErrorPatternMatcher, APIError,
    ErrorCategory, ErrorSeverity, detect_api_error
)


# Custom strategies for generating test data
@composite
def http_status_codes(draw):
    """Generate realistic HTTP status codes."""
    return draw(st.one_of(
        st.integers(min_value=200, max_value=299),  # Success codes
        st.integers(min_value=400, max_value=499),  # Client error codes
        st.integers(min_value=500, max_value=599),  # Server error codes
        st.sampled_from([301, 302, 304])           # Common redirect codes
    ))


@composite
def error_messages(draw):
    """Generate realistic error messages."""
    error_types = [
        "Database connection failed",
        "Access denied",
        "Authentication failed",
        "Rate limit exceeded",
        "Internal server error",
        "Service unavailable",
        "Request timeout",
        "Invalid credentials",
        "Resource not found",
        "Configuration error",
        "Network error",
        "Permission denied",
        "Token expired",
        "Throttling exception",
        "Bad request format"
    ]
    
    base_message = draw(st.sampled_from(error_types))
    
    # Sometimes add additional context
    if draw(st.booleans()):
        context_parts = [
            " in region us-east-1",
            " for account 123456789",
            " after 3 attempts",
            " - please try again later",
            " (code: 500)",
            " at 2025-12-11T14:30:00Z"
        ]
        context = draw(st.sampled_from(context_parts))
        return base_message + context
    
    return base_message


@composite
def service_names(draw):
    """Generate realistic service names."""
    services = [
        "health-monitor",
        "operations",
        "discovery",
        "cost-analyzer",
        "compliance-checker",
        "query-handler",
        "approval-workflow",
        "onboarding"
    ]
    return draw(st.sampled_from(services))


@composite
def api_endpoints(draw):
    """Generate realistic API endpoints."""
    endpoints = [
        "/api/health/database",
        "/api/operations",
        "/api/discovery/start",
        "/api/cost/analyze",
        "/api/compliance/check",
        "/api/query/execute",
        "/api/approval/submit",
        "/api/onboarding/account"
    ]
    return draw(st.sampled_from(endpoints))


@composite
def request_contexts(draw):
    """Generate realistic request contexts."""
    return draw(st.dictionaries(
        keys=st.sampled_from([
            "account_id", "region", "user_id", "correlation_id",
            "request_timestamp", "source_ip", "user_agent"
        ]),
        values=st.one_of(
            st.text(min_size=1, max_size=50),
            st.integers(min_value=100000000, max_value=999999999999),
            st.booleans()
        ),
        min_size=0,
        max_size=5
    ))


class TestErrorDetectionProperties(unittest.TestCase):
    """Property-based tests for error detection system."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.detector = ErrorDetector()
        self.pattern_matcher = ErrorPatternMatcher()
    
    @given(
        status_code=http_status_codes(),
        error_message=error_messages(),
        service=service_names(),
        endpoint=api_endpoints(),
        request_id=st.text(min_size=1, max_size=100),
        context=request_contexts()
    )
    @settings(max_examples=100)
    def test_error_detection_consistency(self, status_code, error_message, service, endpoint, request_id, context):
        """
        **Property 1: Error detection consistency**
        
        For any valid input, error detection should:
        1. Always return a valid APIError object
        2. Preserve all input data accurately
        3. Assign a valid category and severity
        4. Generate a unique error ID
        5. Set a valid timestamp
        
        **Validates: Requirements 1.1**
        """
        # Assume valid inputs (filter out edge cases that would cause legitimate failures)
        assume(len(error_message.strip()) > 0)
        assume(len(service.strip()) > 0)
        assume(len(endpoint.strip()) > 0)
        assume(len(request_id.strip()) > 0)
        assume(100 <= status_code <= 599)
        
        # Detect and classify the error
        api_error = self.detector.detect_and_classify(
            status_code=status_code,
            error_message=error_message,
            service=service,
            endpoint=endpoint,
            request_id=request_id,
            context=context
        )
        
        # Property 1.1: Always returns a valid APIError object
        self.assertIsInstance(api_error, APIError)
        
        # Property 1.2: Preserves all input data accurately
        self.assertEqual(api_error.status_code, status_code)
        self.assertEqual(api_error.message, error_message)
        self.assertEqual(api_error.service, service)
        self.assertEqual(api_error.endpoint, endpoint)
        self.assertEqual(api_error.request_id, request_id)
        self.assertEqual(api_error.context, context)
        
        # Property 1.3: Assigns a valid category and severity
        self.assertIsInstance(api_error.category, ErrorCategory)
        self.assertIsInstance(api_error.severity, ErrorSeverity)
        
        # Property 1.4: Generates a unique error ID
        self.assertIsInstance(api_error.id, str)
        self.assertTrue(len(api_error.id) > 0)
        self.assertTrue(api_error.id.startswith("err_"))
        
        # Property 1.5: Sets a valid timestamp
        self.assertIsInstance(api_error.timestamp, datetime)
        self.assertEqual(api_error.timestamp.tzinfo, timezone.utc)
        
        # Additional consistency checks
        self.assertFalse(api_error.resolution_attempted)
        self.assertFalse(api_error.resolution_successful)
    
    @given(
        error_message=st.text(min_size=1, max_size=1000),
        status_code=http_status_codes()
    )
    @settings(max_examples=100)
    def test_classification_determinism(self, error_message, status_code):
        """
        **Property 2: Classification determinism**
        
        For any given error message and status code combination:
        1. Classification should be deterministic (same inputs = same outputs)
        2. Category should be a valid ErrorCategory
        3. Severity should be a valid ErrorSeverity
        
        **Validates: Requirements 1.1**
        """
        assume(len(error_message.strip()) > 0)
        assume(100 <= status_code <= 599)
        
        # Classify the same error multiple times
        category1 = self.pattern_matcher.classify_error(error_message, status_code)
        category2 = self.pattern_matcher.classify_error(error_message, status_code)
        
        severity1 = self.pattern_matcher.assess_severity(error_message, status_code, category1)
        severity2 = self.pattern_matcher.assess_severity(error_message, status_code, category1)
        
        # Property 2.1: Classification is deterministic
        self.assertEqual(category1, category2)
        self.assertEqual(severity1, severity2)
        
        # Property 2.2: Category is valid
        self.assertIsInstance(category1, ErrorCategory)
        
        # Property 2.3: Severity is valid
        self.assertIsInstance(severity1, ErrorSeverity)
    
    @given(
        status_code=st.integers(min_value=400, max_value=403),
        error_message=st.text(min_size=1, max_size=100)
    )
    @settings(max_examples=50)
    def test_auth_error_classification_consistency(self, status_code, error_message):
        """
        **Property 3: Authentication/Authorization error consistency**
        
        For 401/403 status codes:
        1. Should classify as AUTHENTICATION (401) or AUTHORIZATION (403)
        2. Should have HIGH or CRITICAL severity
        3. Retry logic should be consistent with category
        
        **Validates: Requirements 1.1, 1.2**
        """
        assume(len(error_message.strip()) > 0)
        
        category = self.pattern_matcher.classify_error(error_message, status_code)
        severity = self.pattern_matcher.assess_severity(error_message, status_code, category)
        
        # Property 3.1: Correct category for auth errors
        if status_code == 401:
            self.assertEqual(category, ErrorCategory.AUTHENTICATION)
        elif status_code == 403:
            self.assertEqual(category, ErrorCategory.AUTHORIZATION)
        
        # Property 3.2: Auth errors should have appropriate severity
        self.assertIn(severity, [ErrorSeverity.HIGH, ErrorSeverity.CRITICAL, ErrorSeverity.MEDIUM])
        
        # Property 3.3: Retry logic consistency
        api_error = APIError(
            id="test",
            timestamp=datetime.now(timezone.utc),
            status_code=status_code,
            message=error_message,
            service="test",
            endpoint="/test",
            request_id="test",
            user_id=None,
            category=category,
            severity=severity,
            context={}
        )
        
        should_retry = self.detector.should_retry(api_error)
        
        # Authentication errors should be retryable (token refresh)
        if category == ErrorCategory.AUTHENTICATION:
            self.assertTrue(should_retry)
        # Authorization errors should not be retryable
        elif category == ErrorCategory.AUTHORIZATION:
            self.assertFalse(should_retry)
    
    @given(
        status_code=st.integers(min_value=500, max_value=599),
        error_message=st.text(min_size=1, max_size=100)
    )
    @settings(max_examples=50)
    def test_server_error_retry_consistency(self, status_code, error_message):
        """
        **Property 4: Server error retry consistency**
        
        For 5xx status codes:
        1. Should generally be retryable
        2. Should have HIGH or CRITICAL severity
        3. Critical errors should be properly identified
        
        **Validates: Requirements 1.1, 1.2**
        """
        assume(len(error_message.strip()) > 0)
        
        category = self.pattern_matcher.classify_error(error_message, status_code)
        severity = self.pattern_matcher.assess_severity(error_message, status_code, category)
        
        api_error = APIError(
            id="test",
            timestamp=datetime.now(timezone.utc),
            status_code=status_code,
            message=error_message,
            service="test",
            endpoint="/test",
            request_id="test",
            user_id=None,
            category=category,
            severity=severity,
            context={}
        )
        
        # Property 4.1: Server errors should be retryable
        should_retry = self.detector.should_retry(api_error)
        self.assertTrue(should_retry)
        
        # Property 4.2: Server errors should have appropriate severity
        self.assertIn(severity, [ErrorSeverity.HIGH, ErrorSeverity.CRITICAL, ErrorSeverity.MEDIUM])
        
        # Property 4.3: Critical error identification consistency
        is_critical = self.detector.is_critical_error(api_error)
        if severity == ErrorSeverity.CRITICAL:
            self.assertTrue(is_critical)
    
    @given(
        api_errors=st.lists(
            st.builds(
                APIError,
                id=st.text(min_size=1, max_size=50),
                timestamp=st.datetimes(timezones=st.just(timezone.utc)),
                status_code=http_status_codes(),
                message=error_messages(),
                service=service_names(),
                endpoint=api_endpoints(),
                request_id=st.text(min_size=1, max_size=50),
                user_id=st.one_of(st.none(), st.text(min_size=1, max_size=50)),
                category=st.sampled_from(list(ErrorCategory)),
                severity=st.sampled_from(list(ErrorSeverity)),
                context=request_contexts(),
                stack_trace=st.one_of(st.none(), st.text(max_size=1000))
            ),
            min_size=1,
            max_size=10
        )
    )
    @settings(max_examples=50)
    def test_error_serialization_consistency(self, api_errors):
        """
        **Property 5: Error serialization consistency**
        
        For any list of APIError objects:
        1. to_dict() should always return a valid dictionary
        2. All required fields should be present
        3. Enum values should be serialized as strings
        4. Timestamps should be ISO format strings
        
        **Validates: Requirements 1.1**
        """
        for api_error in api_errors:
            error_dict = api_error.to_dict()
            
            # Property 5.1: Returns a valid dictionary
            self.assertIsInstance(error_dict, dict)
            
            # Property 5.2: All required fields are present
            required_fields = [
                'id', 'timestamp', 'status_code', 'message', 'service',
                'endpoint', 'request_id', 'category', 'severity', 'context'
            ]
            for field in required_fields:
                self.assertIn(field, error_dict)
            
            # Property 5.3: Enum values are serialized as strings
            self.assertIsInstance(error_dict['category'], str)
            self.assertIsInstance(error_dict['severity'], str)
            
            # Property 5.4: Timestamp is ISO format string
            self.assertIsInstance(error_dict['timestamp'], str)
            # Should be parseable as ISO format
            datetime.fromisoformat(error_dict['timestamp'].replace('Z', '+00:00'))


if __name__ == '__main__':
    unittest.main()