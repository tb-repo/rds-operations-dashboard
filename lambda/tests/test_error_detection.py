"""
Unit Tests for Error Detection Service

Tests error pattern matching, classification logic, and severity assessment.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-11T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.1, 1.2 → DESIGN-ErrorDetection → TASK-1.2",
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

# Add the error-resolution module to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error-resolution'))

from error_detector import (
    ErrorDetector, ErrorPatternMatcher, APIError,
    ErrorCategory, ErrorSeverity, detect_api_error
)


class TestErrorPatternMatcher(unittest.TestCase):
    """Test error pattern matching functionality."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.matcher = ErrorPatternMatcher()
    
    def test_authentication_error_classification(self):
        """Test classification of authentication errors."""
        test_cases = [
            ("Authentication failed", 401, ErrorCategory.AUTHENTICATION),
            ("Invalid credentials provided", 401, ErrorCategory.AUTHENTICATION),
            ("JWT token expired", 401, ErrorCategory.AUTHENTICATION),
            ("Cognito authentication error", 401, ErrorCategory.AUTHENTICATION),
            ("Unauthorized access", 401, ErrorCategory.AUTHENTICATION)
        ]
        
        for message, status_code, expected_category in test_cases:
            with self.subTest(message=message):
                category = self.matcher.classify_error(message, status_code)
                self.assertEqual(category, expected_category)
    
    def test_authorization_error_classification(self):
        """Test classification of authorization errors."""
        test_cases = [
            ("Access denied", 403, ErrorCategory.AUTHORIZATION),
            ("Forbidden operation", 403, ErrorCategory.AUTHORIZATION),
            ("Insufficient permissions", 403, ErrorCategory.AUTHORIZATION),
            ("IAM role not found", 403, ErrorCategory.AUTHORIZATION),
            ("AssumeRole operation failed", 403, ErrorCategory.AUTHORIZATION)
        ]
        
        for message, status_code, expected_category in test_cases:
            with self.subTest(message=message):
                category = self.matcher.classify_error(message, status_code)
                self.assertEqual(category, expected_category)
    
    def test_database_error_classification(self):
        """Test classification of database errors."""
        test_cases = [
            ("Database connection failed", 500, ErrorCategory.DATABASE),
            ("RDS instance unavailable", 500, ErrorCategory.DATABASE),
            ("Connection timeout to database", 500, ErrorCategory.DATABASE),
            ("SQL execution error", 500, ErrorCategory.DATABASE),
            ("DynamoDB operation failed", 500, ErrorCategory.DATABASE)
        ]
        
        for message, status_code, expected_category in test_cases:
            with self.subTest(message=message):
                category = self.matcher.classify_error(message, status_code)
                if category != expected_category:
                    print(f"MISMATCH: '{message}' -> {category}, expected {expected_category}")
                self.assertEqual(category, expected_category)
    
    def test_timeout_error_classification(self):
        """Test classification of timeout errors."""
        test_cases = [
            ("Request timed out", 504, ErrorCategory.TIMEOUT),
            ("Lambda function timeout", 504, ErrorCategory.TIMEOUT),
            ("Gateway timeout occurred", 504, ErrorCategory.TIMEOUT),
            ("Read timeout", 504, ErrorCategory.TIMEOUT)
        ]
        
        for message, status_code, expected_category in test_cases:
            with self.subTest(message=message):
                category = self.matcher.classify_error(message, status_code)
                self.assertEqual(category, expected_category)
    
    def test_rate_limit_error_classification(self):
        """Test classification of rate limiting errors."""
        test_cases = [
            ("Rate limit exceeded", 429, ErrorCategory.RATE_LIMIT),
            ("Too many requests", 429, ErrorCategory.RATE_LIMIT),
            ("API throttling active", 429, ErrorCategory.RATE_LIMIT),
            ("Quota exceeded", 429, ErrorCategory.RATE_LIMIT)
        ]
        
        for message, status_code, expected_category in test_cases:
            with self.subTest(message=message):
                category = self.matcher.classify_error(message, status_code)
                self.assertEqual(category, expected_category)
    
    def test_severity_assessment_critical(self):
        """Test critical severity assessment."""
        test_cases = [
            ("Critical system failure", 500, ErrorCategory.DATABASE, ErrorSeverity.CRITICAL),
            ("Database unavailable", 500, ErrorCategory.DATABASE, ErrorSeverity.CRITICAL),
            ("Authentication system down", 500, ErrorCategory.AUTHENTICATION, ErrorSeverity.CRITICAL)
        ]
        
        for message, status_code, category, expected_severity in test_cases:
            with self.subTest(message=message):
                severity = self.matcher.assess_severity(message, status_code, category)
                self.assertEqual(severity, expected_severity)
    
    def test_severity_assessment_high(self):
        """Test high severity assessment."""
        test_cases = [
            ("Internal server error", 500, ErrorCategory.RESOURCE, ErrorSeverity.HIGH),
            ("Service unavailable", 503, ErrorCategory.RESOURCE, ErrorSeverity.HIGH),
            ("Access denied", 403, ErrorCategory.AUTHORIZATION, ErrorSeverity.HIGH)
        ]
        
        for message, status_code, category, expected_severity in test_cases:
            with self.subTest(message=message):
                severity = self.matcher.assess_severity(message, status_code, category)
                self.assertEqual(severity, expected_severity)
    
    def test_severity_assessment_medium(self):
        """Test medium severity assessment."""
        test_cases = [
            ("Request timeout", 408, ErrorCategory.TIMEOUT, ErrorSeverity.MEDIUM),
            ("Rate limit exceeded", 429, ErrorCategory.RATE_LIMIT, ErrorSeverity.MEDIUM),
            ("Bad request format", 400, ErrorCategory.UNKNOWN, ErrorSeverity.MEDIUM)
        ]
        
        for message, status_code, category, expected_severity in test_cases:
            with self.subTest(message=message):
                severity = self.matcher.assess_severity(message, status_code, category)
                self.assertEqual(severity, expected_severity)
    
    def test_severity_assessment_low(self):
        """Test low severity assessment."""
        test_cases = [
            ("Resource not found", 404, ErrorCategory.RESOURCE, ErrorSeverity.LOW),
            ("Validation error", 400, ErrorCategory.UNKNOWN, ErrorSeverity.LOW),
            ("Invalid input provided", 400, ErrorCategory.UNKNOWN, ErrorSeverity.LOW)
        ]
        
        for message, status_code, category, expected_severity in test_cases:
            with self.subTest(message=message):
                severity = self.matcher.assess_severity(message, status_code, category)
                self.assertEqual(severity, expected_severity)
    
    def test_unknown_error_classification(self):
        """Test classification of unknown errors."""
        message = "Some unknown error occurred"
        status_code = 418  # I'm a teapot
        
        category = self.matcher.classify_error(message, status_code)
        self.assertEqual(category, ErrorCategory.UNKNOWN)


class TestErrorDetector(unittest.TestCase):
    """Test error detector functionality."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.detector = ErrorDetector()
    
    def test_detect_and_classify_basic(self):
        """Test basic error detection and classification."""
        api_error = self.detector.detect_and_classify(
            status_code=500,
            error_message="Database connection failed",
            service="health-monitor",
            endpoint="/api/health/database",
            request_id="req-123",
            context={"account_id": "123456789"},
            user_id="user-456"
        )
        
        self.assertIsInstance(api_error, APIError)
        self.assertEqual(api_error.status_code, 500)
        self.assertEqual(api_error.message, "Database connection failed")
        self.assertEqual(api_error.service, "health-monitor")
        self.assertEqual(api_error.endpoint, "/api/health/database")
        self.assertEqual(api_error.request_id, "req-123")
        self.assertEqual(api_error.user_id, "user-456")
        self.assertEqual(api_error.category, ErrorCategory.DATABASE)
        self.assertEqual(api_error.severity, ErrorSeverity.CRITICAL)
        self.assertIsInstance(api_error.timestamp, datetime)
        self.assertTrue(api_error.id.startswith("err_"))
    
    def test_detect_and_classify_without_optional_fields(self):
        """Test error detection without optional fields."""
        api_error = self.detector.detect_and_classify(
            status_code=403,
            error_message="Access denied",
            service="operations",
            endpoint="/api/operations",
            request_id="req-456",
            context={}
        )
        
        self.assertEqual(api_error.status_code, 403)
        self.assertEqual(api_error.category, ErrorCategory.AUTHORIZATION)
        self.assertEqual(api_error.severity, ErrorSeverity.HIGH)
        self.assertIsNone(api_error.user_id)
        self.assertIsNone(api_error.stack_trace)
    
    def test_is_critical_error(self):
        """Test critical error identification."""
        # Critical database error
        critical_error = APIError(
            id="err_1",
            timestamp=datetime.now(timezone.utc),
            status_code=500,
            message="Database unavailable",
            service="test",
            endpoint="/test",
            request_id="req-1",
            user_id=None,
            category=ErrorCategory.DATABASE,
            severity=ErrorSeverity.CRITICAL,
            context={}
        )
        
        self.assertTrue(self.detector.is_critical_error(critical_error))
        
        # Non-critical error
        non_critical_error = APIError(
            id="err_2",
            timestamp=datetime.now(timezone.utc),
            status_code=404,
            message="Not found",
            service="test",
            endpoint="/test",
            request_id="req-2",
            user_id=None,
            category=ErrorCategory.RESOURCE,
            severity=ErrorSeverity.LOW,
            context={}
        )
        
        self.assertFalse(self.detector.is_critical_error(non_critical_error))
    
    def test_should_retry_logic(self):
        """Test retry logic for different error types."""
        # Should retry: Server error
        server_error = APIError(
            id="err_1",
            timestamp=datetime.now(timezone.utc),
            status_code=500,
            message="Internal server error",
            service="test",
            endpoint="/test",
            request_id="req-1",
            user_id=None,
            category=ErrorCategory.RESOURCE,
            severity=ErrorSeverity.HIGH,
            context={}
        )
        
        self.assertTrue(self.detector.should_retry(server_error))
        
        # Should retry: Authentication error (token refresh)
        auth_error = APIError(
            id="err_2",
            timestamp=datetime.now(timezone.utc),
            status_code=401,
            message="Token expired",
            service="test",
            endpoint="/test",
            request_id="req-2",
            user_id=None,
            category=ErrorCategory.AUTHENTICATION,
            severity=ErrorSeverity.MEDIUM,
            context={}
        )
        
        self.assertTrue(self.detector.should_retry(auth_error))
        
        # Should retry: Rate limiting
        rate_limit_error = APIError(
            id="err_3",
            timestamp=datetime.now(timezone.utc),
            status_code=429,
            message="Rate limit exceeded",
            service="test",
            endpoint="/test",
            request_id="req-3",
            user_id=None,
            category=ErrorCategory.RATE_LIMIT,
            severity=ErrorSeverity.MEDIUM,
            context={}
        )
        
        self.assertTrue(self.detector.should_retry(rate_limit_error))
        
        # Should NOT retry: Client error
        client_error = APIError(
            id="err_4",
            timestamp=datetime.now(timezone.utc),
            status_code=400,
            message="Bad request",
            service="test",
            endpoint="/test",
            request_id="req-4",
            user_id=None,
            category=ErrorCategory.UNKNOWN,
            severity=ErrorSeverity.MEDIUM,
            context={}
        )
        
        self.assertFalse(self.detector.should_retry(client_error))
        
        # Should NOT retry: Authorization error
        authz_error = APIError(
            id="err_5",
            timestamp=datetime.now(timezone.utc),
            status_code=403,
            message="Access denied",
            service="test",
            endpoint="/test",
            request_id="req-5",
            user_id=None,
            category=ErrorCategory.AUTHORIZATION,
            severity=ErrorSeverity.HIGH,
            context={}
        )
        
        self.assertFalse(self.detector.should_retry(authz_error))
    
    def test_get_error_statistics(self):
        """Test error statistics retrieval."""
        # Detect a few errors to populate statistics
        for i in range(3):
            self.detector.detect_and_classify(
                status_code=500,
                error_message=f"Test error {i}",
                service="test",
                endpoint="/test",
                request_id=f"req-{i}",
                context={}
            )
        
        stats = self.detector.get_error_statistics()
        
        self.assertIsInstance(stats, dict)
        self.assertIn('total_errors_detected', stats)
        self.assertIn('detector_version', stats)
        self.assertIn('patterns_loaded', stats)
        self.assertIn('severity_patterns_loaded', stats)
        self.assertGreaterEqual(stats['total_errors_detected'], 3)
    
    def test_api_error_to_dict(self):
        """Test APIError serialization to dictionary."""
        api_error = APIError(
            id="err_test",
            timestamp=datetime.now(timezone.utc),
            status_code=500,
            message="Test error",
            service="test-service",
            endpoint="/test",
            request_id="req-test",
            user_id="user-test",
            category=ErrorCategory.DATABASE,
            severity=ErrorSeverity.HIGH,
            context={"key": "value"},
            stack_trace="Test stack trace"
        )
        
        error_dict = api_error.to_dict()
        
        self.assertIsInstance(error_dict, dict)
        self.assertEqual(error_dict['id'], "err_test")
        self.assertEqual(error_dict['status_code'], 500)
        self.assertEqual(error_dict['message'], "Test error")
        self.assertEqual(error_dict['service'], "test-service")
        self.assertEqual(error_dict['endpoint'], "/test")
        self.assertEqual(error_dict['request_id'], "req-test")
        self.assertEqual(error_dict['user_id'], "user-test")
        self.assertEqual(error_dict['category'], "database")
        self.assertEqual(error_dict['severity'], "high")
        self.assertEqual(error_dict['context'], {"key": "value"})
        self.assertEqual(error_dict['stack_trace'], "Test stack trace")
        self.assertIn('timestamp', error_dict)


class TestConvenienceFunctions(unittest.TestCase):
    """Test convenience functions."""
    
    def test_detect_api_error_function(self):
        """Test the detect_api_error convenience function."""
        api_error = detect_api_error(
            status_code=403,
            error_message="Access denied",
            service="operations",
            endpoint="/api/operations",
            request_id="req-test",
            context={"account_id": "123456789"}
        )
        
        self.assertIsInstance(api_error, APIError)
        self.assertEqual(api_error.status_code, 403)
        self.assertEqual(api_error.category, ErrorCategory.AUTHORIZATION)
        self.assertEqual(api_error.severity, ErrorSeverity.HIGH)


if __name__ == '__main__':
    unittest.main()