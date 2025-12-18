"""
Performance Integration Tests

Tests the integration of performance optimizations across the error resolution system.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-17T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-7.1, 7.2 → DESIGN-Performance → TASK-8",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
import time
import sys
import os

# Add error_resolution module to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'error_resolution'))
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'monitoring'))

from error_detector import get_error_detector
from resolution_engine import get_resolution_engine
from metrics_collector import get_metrics_collector
from performance_optimizer import get_performance_optimizer


class TestPerformanceIntegration:
    """Test integration of performance optimizations."""
    
    def test_performance_optimizer_initialization(self):
        """Test that performance optimizer initializes correctly."""
        optimizer = get_performance_optimizer()
        
        assert optimizer is not None
        assert optimizer.cache is not None
        assert optimizer.strategy_cache is not None
        assert optimizer.pattern_cache is not None
        assert optimizer.query_optimizer is not None
        
        # Test cache statistics
        stats = optimizer.get_performance_stats()
        assert 'uptime_seconds' in stats
        assert 'cache_stats' in stats
        assert 'optimization_enabled' in stats
    
    def test_error_detection_with_caching(self):
        """Test error detection performance with caching enabled."""
        detector = get_error_detector()
        
        # First detection (cache miss)
        start_time = time.perf_counter()
        error1 = detector.detect_and_classify(
            status_code=500,
            error_message="Database connection failed",
            service="test-service",
            endpoint="/api/test",
            request_id="req-1",
            context={}
        )
        first_time = time.perf_counter() - start_time
        
        # Second detection with same parameters (should be faster due to caching)
        start_time = time.perf_counter()
        error2 = detector.detect_and_classify(
            status_code=500,
            error_message="Database connection failed",
            service="test-service",
            endpoint="/api/test",
            request_id="req-2",
            context={}
        )
        second_time = time.perf_counter() - start_time
        
        # Verify both errors are classified correctly
        assert error1.category.value == "database"
        assert error2.category.value == "database"
        
        # Performance should be reasonable
        assert first_time < 1.0, f"First detection took {first_time:.3f}s"
        assert second_time < 1.0, f"Second detection took {second_time:.3f}s"
    
    def test_resolution_strategy_caching(self):
        """Test resolution strategy caching functionality."""
        engine = get_resolution_engine()
        optimizer = get_performance_optimizer()
        
        # Create test error
        from error_detector import APIError, ErrorCategory, ErrorSeverity
        from datetime import datetime, timezone
        
        api_error = APIError(
            id="test-error-cache",
            timestamp=datetime.now(timezone.utc),
            status_code=500,
            message="Database connection failed",
            service="cache-test-service",
            endpoint="/api/cache-test",
            request_id="req-cache-test",
            user_id=None,
            category=ErrorCategory.DATABASE,
            severity=ErrorSeverity.HIGH,
            context={}
        )
        
        # First strategy selection (cache miss)
        start_time = time.perf_counter()
        strategy1 = engine.select_strategy(api_error)
        first_time = time.perf_counter() - start_time
        
        # Second strategy selection (should hit cache)
        start_time = time.perf_counter()
        strategy2 = engine.select_strategy(api_error)
        second_time = time.perf_counter() - start_time
        
        # Verify strategies are the same
        assert strategy1 == strategy2
        
        # Performance should be reasonable
        assert first_time < 0.1, f"First strategy selection took {first_time:.3f}s"
        assert second_time < 0.1, f"Second strategy selection took {second_time:.3f}s"
        
        # Verify caching is working by checking optimizer stats
        stats = optimizer.get_performance_stats()
        assert stats['cache_stats']['size'] > 0
    
    def test_metrics_collection_performance(self):
        """Test metrics collection performance with batching."""
        collector = get_metrics_collector()
        
        # Collect multiple metrics quickly
        start_time = time.perf_counter()
        
        for i in range(10):
            collector.collect_error_metric(
                service=f"perf-test-service-{i % 3}",
                endpoint=f"/api/endpoint-{i}",
                error_type="performance_test",
                severity="medium",
                count=1
            )
        
        total_time = time.perf_counter() - start_time
        
        # Performance should be reasonable
        assert total_time < 2.0, f"Collecting 10 metrics took {total_time:.3f}s"
        
        # Verify metrics were collected
        stats = collector.get_performance_stats()
        assert stats['total_metrics_collected'] >= 10
    
    def test_query_optimization(self):
        """Test database query optimization functionality."""
        optimizer = get_performance_optimizer()
        
        # Test query optimization
        filters = {
            'service': 'test-service',
            'timestamp': '2025-12-17T12:00:00Z',  # Add timestamp to trigger index hint
            'start_time': '2025-12-17T00:00:00Z',
            'end_time': '2025-12-17T23:59:59Z',
            'limit': 50000  # Large limit that should be optimized
        }
        
        optimized_filters = optimizer.optimize_query(filters)
        
        # Verify optimization occurred
        assert 'limit' in optimized_filters
        assert optimized_filters['limit'] <= 10000  # Should be capped
        
        # Check if index hint was added (depends on filter combination)
        if 'service' in filters and 'timestamp' in filters:
            assert '_index_hint' in optimized_filters  # Should add index hint
    
    def test_cache_invalidation(self):
        """Test cache invalidation functionality."""
        optimizer = get_performance_optimizer()
        
        # Add some data to cache
        optimizer.cache_strategy(
            error_category="test",
            error_severity="high",
            status_code=500,
            service="test-service",
            strategy="test_strategy"
        )
        
        # Verify cache has data
        initial_stats = optimizer.get_performance_stats()
        assert initial_stats['cache_stats']['size'] > 0
        
        # Invalidate cache
        optimizer.invalidate_cache()
        
        # Verify cache is cleared
        final_stats = optimizer.get_performance_stats()
        assert final_stats['cache_stats']['size'] == 0
    
    def test_performance_monitoring(self):
        """Test performance monitoring and statistics collection."""
        optimizer = get_performance_optimizer()
        detector = get_error_detector()
        collector = get_metrics_collector()
        
        # Perform some operations to generate statistics
        for i in range(5):
            detector.detect_and_classify(
                status_code=500,
                error_message=f"Test error {i}",
                service="monitoring-test",
                endpoint=f"/api/test-{i}",
                request_id=f"req-{i}",
                context={}
            )
        
        # Get comprehensive performance statistics
        optimizer_stats = optimizer.get_performance_stats()
        detector_stats = detector.get_error_statistics()
        collector_stats = collector.get_performance_stats()
        
        # Verify statistics are available
        assert 'uptime_seconds' in optimizer_stats
        assert 'cache_stats' in optimizer_stats
        assert 'total_errors_detected' in detector_stats
        assert 'total_metrics_collected' in collector_stats
        
        # Verify statistics are reasonable
        assert optimizer_stats['uptime_seconds'] > 0
        assert detector_stats['total_errors_detected'] >= 5
        assert collector_stats['total_metrics_collected'] >= 5


if __name__ == "__main__":
    # Run integration tests
    pytest.main([__file__, "-v", "--tb=short"])