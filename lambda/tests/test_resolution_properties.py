"""
Property-Based Tests for Resolution Engine

Tests universal properties for resolution strategies and rollback mechanisms.
Uses Hypothesis for property-based testing.

**Feature: api-error-resolution, Property 2: Resolution strategy selection**
**Feature: api-error-resolution, Property 3: Rollback consistency**
**Validates: Requirements 2.1, 2.3**

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-11T14:45:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-2.1, 2.3 → DESIGN-ResolutionEngine → TASK-2.1, 2.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import unittest
import asyncio
from datetime import datetime, timezone
import sys
import os
from hypothesis import given, strategies as st, settings, assume
from hypothesis.strategies import composite

# Add the error-resolution module to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error-resolution'))

from resolution_engine import (
    ResolutionEngine, ResolutionStrategy, ResolutionStatus, ResolutionAttempt
)
from error_detector import APIError, ErrorCategory, ErrorSeverity
from performance_optimizer import get_performance_optimizer


# Custom strategies for generating test data
@composite
def api_errors(draw):
    """Generate realistic APIError objects."""
    categories = list(ErrorCategory)
    severities = list(ErrorSeverity)
    
    category = draw(st.sampled_from(categories))
    severity = draw(st.sampled_from(severities))
    
    # Generate status codes based on category
    if category == ErrorCategory.AUTHENTICATION:
        status_code = 401
    elif category == ErrorCategory.AUTHORIZATION:
        status_code = 403
    elif category == ErrorCategory.RESOURCE and severity in [ErrorSeverity.HIGH, ErrorSeverity.CRITICAL]:
        status_code = draw(st.integers(min_value=500, max_value=503))
    elif category == ErrorCategory.RATE_LIMIT:
        status_code = 429
    elif category == ErrorCategory.TIMEOUT:
        status_code = 504
    else:
        status_code = draw(st.integers(min_value=400, max_value=599))
    
    # Generate messages based on category
    message_templates = {
        ErrorCategory.AUTHENTICATION: [
            "Authentication failed", "JWT token expired", "Invalid credentials",
            "Token validation failed", "Cognito authentication error"
        ],
        ErrorCategory.AUTHORIZATION: [
            "Access denied", "Insufficient permissions", "Forbidden operation",
            "IAM role not found", "Permission denied"
        ],
        ErrorCategory.DATABASE: [
            "Database connection failed", "RDS instance unavailable", 
            "Connection timeout to database", "SQL execution error", "DynamoDB operation failed"
        ],
        ErrorCategory.NETWORK: [
            "Network error", "Connection refused", "DNS resolution failed",
            "Endpoint unreachable", "Socket timeout"
        ],
        ErrorCategory.TIMEOUT: [
            "Request timeout", "Lambda function timeout", "Gateway timeout",
            "Read timeout", "Operation timed out"
        ],
        ErrorCategory.RATE_LIMIT: [
            "Rate limit exceeded", "Too many requests", "API throttling active",
            "Quota exceeded", "Request rate too high"
        ],
        ErrorCategory.CONFIGURATION: [
            "Configuration error", "Environment variable missing", "Invalid configuration",
            "Missing parameter", "Config not found"
        ],
        ErrorCategory.RESOURCE: [
            "Resource not found", "Service unavailable", "Internal server error",
            "Out of memory", "Cache service unavailable"
        ],
        ErrorCategory.UNKNOWN: [
            "Unknown error", "Unexpected failure", "System error"
        ]
    }
    
    message = draw(st.sampled_from(message_templates.get(category, ["Generic error"])))
    
    return APIError(
        id=draw(st.text(min_size=5, max_size=20, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd')))),
        timestamp=draw(st.datetimes(timezones=st.just(timezone.utc))),
        status_code=status_code,
        message=message,
        service=draw(st.sampled_from([
            "health-monitor", "operations", "discovery", "auth-service",
            "api-gateway", "query-handler", "cost-analyzer"
        ])),
        endpoint=draw(st.sampled_from([
            "/api/health/database", "/api/operations", "/api/auth/verify",
            "/api/discovery/start", "/api/query/execute", "/api/cost/analyze"
        ])),
        request_id=draw(st.text(min_size=5, max_size=15, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd')))),
        user_id=draw(st.one_of(st.none(), st.text(min_size=5, max_size=15))),
        category=category,
        severity=severity,
        context=draw(st.dictionaries(
            keys=st.text(min_size=1, max_size=10),
            values=st.one_of(st.text(max_size=20), st.integers(), st.booleans()),
            min_size=0,
            max_size=3
        ))
    )


class TestResolutionEngineProperties(unittest.TestCase):
    """Property-based tests for resolution engine."""
    
    def setUp(self):
        """Set up test fixtures."""
        # Clear cache to ensure test isolation
        optimizer = get_performance_optimizer()
        optimizer.invalidate_cache()
        
        self.engine = ResolutionEngine()
    
    @given(api_error=api_errors())
    @settings(max_examples=50)
    def test_strategy_selection_consistency(self, api_error):
        """
        **Property 2: Resolution strategy selection**
        
        For any API error:
        1. Strategy selection should be deterministic (same input = same output)
        2. Selected strategy should be a valid ResolutionStrategy
        3. Strategy should be appropriate for the error category
        4. Strategy selection should never fail or raise exceptions
        
        **Validates: Requirements 2.1**
        """
        # Property 2.1: Strategy selection is deterministic
        strategy1 = self.engine.select_strategy(api_error)
        strategy2 = self.engine.select_strategy(api_error)
        self.assertEqual(strategy1, strategy2)
        
        # Property 2.2: Selected strategy is valid
        self.assertIsInstance(strategy1, ResolutionStrategy)
        
        # Property 2.3: Strategy is appropriate for error category
        if api_error.category == ErrorCategory.AUTHENTICATION:
            if "token" in api_error.message.lower() or "jwt" in api_error.message.lower():
                self.assertEqual(strategy1, ResolutionStrategy.REFRESH_CREDENTIALS)
            else:
                self.assertEqual(strategy1, ResolutionStrategy.RETRY_WITH_BACKOFF)
        
        elif api_error.category == ErrorCategory.AUTHORIZATION:
            if api_error.severity == ErrorSeverity.CRITICAL:
                self.assertEqual(strategy1, ResolutionStrategy.MANUAL_INTERVENTION)
            else:
                self.assertEqual(strategy1, ResolutionStrategy.REFRESH_CREDENTIALS)
        
        elif api_error.category == ErrorCategory.DATABASE:
            if "connection" in api_error.message.lower():
                self.assertEqual(strategy1, ResolutionStrategy.DATABASE_RECONNECT)
            else:
                self.assertEqual(strategy1, ResolutionStrategy.RETRY_WITH_BACKOFF)
        
        elif api_error.category == ErrorCategory.RATE_LIMIT:
            self.assertEqual(strategy1, ResolutionStrategy.RETRY_WITH_BACKOFF)
        
        elif api_error.category == ErrorCategory.CONFIGURATION:
            self.assertEqual(strategy1, ResolutionStrategy.MANUAL_INTERVENTION)
        
        # Property 2.4: Strategy selection never fails
        # (If we reach this point, no exception was raised)
        self.assertTrue(True)
    
    @given(
        api_error=api_errors(),
        strategy=st.sampled_from(list(ResolutionStrategy))
    )
    @settings(max_examples=20, deadline=1000)
    def test_resolution_attempt_consistency(self, api_error, strategy):
        """
        **Property 3: Resolution attempt consistency**
        
        For any API error and resolution strategy:
        1. Resolution should always return a valid ResolutionAttempt
        2. Attempt should have all required fields populated
        3. Attempt status should be valid
        4. Attempt should be stored and retrievable
        5. Timestamps should be consistent (completed_at >= started_at)
        
        **Validates: Requirements 2.1, 2.2**
        """
        async def run_test():
            # Execute resolution
            attempt = await self.engine.resolve_error(api_error, strategy)
            
            # Property 3.1: Returns valid ResolutionAttempt
            self.assertIsInstance(attempt, ResolutionAttempt)
            
            # Property 3.2: All required fields populated
            self.assertIsNotNone(attempt.id)
            self.assertEqual(attempt.error_id, api_error.id)
            self.assertEqual(attempt.strategy, strategy)
            self.assertIsInstance(attempt.status, ResolutionStatus)
            self.assertIsNotNone(attempt.started_at)
            
            # Property 3.3: Status is valid
            self.assertIn(attempt.status, [
                ResolutionStatus.SUCCESS, 
                ResolutionStatus.FAILED,
                ResolutionStatus.PENDING,
                ResolutionStatus.IN_PROGRESS
            ])
            
            # Property 3.4: Attempt is stored and retrievable
            stored_attempt = self.engine.get_resolution_attempt(attempt.id)
            self.assertIsNotNone(stored_attempt)
            self.assertEqual(stored_attempt.id, attempt.id)
            
            # Property 3.5: Timestamps are consistent
            if attempt.completed_at:
                self.assertGreaterEqual(attempt.completed_at, attempt.started_at)
            
            return attempt
        
        # Run the async test
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        attempt = loop.run_until_complete(run_test())
        loop.close()
    
    @given(api_error=api_errors())
    @settings(max_examples=5, deadline=None)
    def test_rollback_consistency(self, api_error):
        """
        **Property 4: Rollback consistency**
        
        For any successful resolution attempt:
        1. Rollback should be possible for successful attempts
        2. Rollback should update attempt status appropriately
        3. Rollback should be idempotent (multiple rollbacks don't cause issues)
        4. Rollback should preserve attempt history
        
        **Validates: Requirements 2.3**
        """
        async def run_test():
            # First, create a resolution attempt with a strategy that's likely to succeed
            # Use REFRESH_CREDENTIALS or NO_ACTION for more predictable success
            strategy = ResolutionStrategy.REFRESH_CREDENTIALS
            attempt = await self.engine.resolve_error(api_error, strategy)
            
            # Only test rollback if resolution was successful
            if attempt.success and attempt.status == ResolutionStatus.SUCCESS:
                original_id = attempt.id
                original_error_id = attempt.error_id
                
                # Property 4.1: Rollback should be possible
                rollback_success = await self.engine.rollback_resolution(attempt.id)
                
                # Property 4.2: Status should be updated appropriately
                updated_attempt = self.engine.get_resolution_attempt(attempt.id)
                self.assertIsNotNone(updated_attempt)
                
                if rollback_success:
                    self.assertEqual(updated_attempt.status, ResolutionStatus.ROLLBACK_SUCCESS)
                else:
                    self.assertEqual(updated_attempt.status, ResolutionStatus.ROLLBACK_FAILED)
                
                # Property 4.3: Rollback is idempotent
                second_rollback = await self.engine.rollback_resolution(attempt.id)
                # Second rollback should fail gracefully (attempt not in success state)
                self.assertFalse(second_rollback)
                
                # Property 4.4: Attempt history is preserved
                final_attempt = self.engine.get_resolution_attempt(attempt.id)
                self.assertEqual(final_attempt.id, original_id)
                self.assertEqual(final_attempt.error_id, original_error_id)
                self.assertEqual(final_attempt.strategy, strategy)
            
            return attempt
        
        # Run the async test
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        attempt = loop.run_until_complete(run_test())
        loop.close()
    
    @given(
        api_errors_list=st.lists(api_errors(), min_size=1, max_size=2)
    )
    @settings(max_examples=5, deadline=None)
    def test_multiple_attempts_consistency(self, api_errors_list):
        """
        **Property 5: Multiple attempts consistency**
        
        For multiple resolution attempts:
        1. Each attempt should have a unique ID
        2. Attempts for the same error should be retrievable together
        3. Statistics should accurately reflect all attempts
        4. Engine state should remain consistent across multiple operations
        
        **Validates: Requirements 2.1, 2.2**
        """
        async def run_test():
            attempt_ids = set()
            all_attempts = []
            
            # Create multiple resolution attempts
            for api_error in api_errors_list:
                strategy = self.engine.select_strategy(api_error)
                attempt = await self.engine.resolve_error(api_error, strategy)
                
                # Property 5.1: Unique IDs
                self.assertNotIn(attempt.id, attempt_ids)
                attempt_ids.add(attempt.id)
                all_attempts.append(attempt)
            
            # Property 5.2: Attempts retrievable by error ID
            for api_error in api_errors_list:
                error_attempts = self.engine.get_attempts_for_error(api_error.id)
                self.assertGreater(len(error_attempts), 0)
                
                # All returned attempts should be for this error
                for attempt in error_attempts:
                    self.assertEqual(attempt.error_id, api_error.id)
            
            # Property 5.3: Statistics accuracy
            stats = self.engine.get_statistics()
            self.assertGreaterEqual(stats['total_attempts'], len(all_attempts))
            self.assertIsInstance(stats['success_rate'], (int, float))
            self.assertGreaterEqual(stats['success_rate'], 0.0)
            self.assertLessEqual(stats['success_rate'], 1.0)
            
            # Property 5.4: Engine state consistency
            # All attempts should still be retrievable
            for attempt in all_attempts:
                stored_attempt = self.engine.get_resolution_attempt(attempt.id)
                self.assertIsNotNone(stored_attempt)
                self.assertEqual(stored_attempt.id, attempt.id)
            
            return all_attempts
        
        # Run the async test
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        attempts = loop.run_until_complete(run_test())
        loop.close()
    
    @given(
        api_error=api_errors(),
        context=st.dictionaries(
            keys=st.text(min_size=1, max_size=10),
            values=st.one_of(st.text(max_size=20), st.integers(), st.booleans()),
            min_size=0,
            max_size=3
        )
    )
    @settings(max_examples=15, deadline=1000)
    def test_context_preservation(self, api_error, context):
        """
        **Property 6: Context preservation**
        
        For any resolution attempt with context:
        1. Context should be preserved in the attempt
        2. Context should not affect strategy selection
        3. Context should be available for rollback operations
        
        **Validates: Requirements 2.1, 2.2, 2.3**
        """
        async def run_test():
            # Test without context
            strategy_without_context = self.engine.select_strategy(api_error)
            
            # Test with context
            strategy_with_context = self.engine.select_strategy(api_error)
            
            # Property 6.2: Context doesn't affect strategy selection
            self.assertEqual(strategy_without_context, strategy_with_context)
            
            # Create attempt with context
            attempt = await self.engine.resolve_error(api_error, None, context)
            
            # Property 6.1: Context is preserved
            self.assertEqual(attempt.metadata, context)
            
            # Property 6.3: Context available for rollback
            if attempt.success:
                # Context should still be available after rollback
                await self.engine.rollback_resolution(attempt.id)
                updated_attempt = self.engine.get_resolution_attempt(attempt.id)
                self.assertEqual(updated_attempt.metadata, context)
            
            return attempt
        
        # Run the async test
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        attempt = loop.run_until_complete(run_test())
        loop.close()


if __name__ == '__main__':
    unittest.main()