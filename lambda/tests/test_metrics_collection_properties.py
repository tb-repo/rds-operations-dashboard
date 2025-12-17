"""
Property-Based Tests for Metrics Collection System

Tests the correctness properties of the error metrics collection system
to ensure accurate data collection and aggregation.

**Feature: api-error-resolution, Property 4: Metrics accuracy**
**Validates: Requirements 3.1**

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-13T14:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-3.1 → DESIGN-MonitoringDashboard → TASK-3.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, MagicMock
import sys
import os

# Add the monitoring module to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'monitoring'))
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from metrics_collector import MetricsCollector, ErrorMetric, MetricType, AggregatedMetric


# Test data generators
@st.composite
def error_metric_data(draw):
    """Generate valid error metric data."""
    service = draw(st.text(min_size=1, max_size=50, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Pc'))))
    endpoint = draw(st.text(min_size=1, max_size=100, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Pc', 'Pd'))))
    error_type = draw(st.sampled_from(['database', 'permission', 'timeout', 'network', 'validation']))
    severity = draw(st.sampled_from(['low', 'medium', 'high', 'critical']))
    count = draw(st.integers(min_value=1, max_value=1000))
    response_time_ms = draw(st.one_of(st.none(), st.floats(min_value=0.1, max_value=30000.0)))
    
    return {
        'service': service,
        'endpoint': endpoint,
        'error_type': error_type,
        'severity': severity,
        'count': count,
        'response_time_ms': response_time_ms
    }


@st.composite
def multiple_error_metrics(draw):
    """Generate a list of error metrics."""
    metrics_count = draw(st.integers(min_value=1, max_value=20))
    metrics = []
    
    for _ in range(metrics_count):
        metric_data = draw(error_metric_data())
        metrics.append(metric_data)
    
    return metrics


class TestMetricsCollectionProperties:
    """Property-based tests for metrics collection accuracy."""
    
    @pytest.fixture(autouse=True)
    def setup_method(self):
        """Set up test fixtures."""
        self.collector = self.create_test_collector()
    
    def create_test_collector(self):
        """Create a fresh collector instance for each test."""
        # Mock DynamoDB and CloudWatch
        mock_dynamodb = Mock()
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        mock_metrics_publisher = Mock()
        mock_metrics_publisher.__enter__ = Mock(return_value=mock_metrics_publisher)
        mock_metrics_publisher.__exit__ = Mock(return_value=None)
        
        # Create collector with mocked dependencies
        with patch('boto3.resource', return_value=mock_dynamodb), \
             patch('monitoring.metrics_collector.MetricsPublisher', return_value=mock_metrics_publisher):
            collector = MetricsCollector(f"test-table-{id(self)}")  # Unique table name
            collector.metrics_cache.clear()  # Ensure clean state
            return collector
    
    @given(error_metric_data())
    @settings(max_examples=50, deadline=None)
    def test_property_4_metrics_accuracy_single_metric(self, metric_data):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any valid error metric data, collecting the metric should
        preserve all data accurately and make it retrievable.
        """
        # Arrange
        assume(len(metric_data['service']) > 0)
        assume(len(metric_data['endpoint']) > 0)
        
        collector = self.create_test_collector()
        
        # Act - Collect the metric
        collected_metric = collector.collect_error_metric(
            service=metric_data['service'],
            endpoint=metric_data['endpoint'],
            error_type=metric_data['error_type'],
            severity=metric_data['severity'],
            count=metric_data['count'],
            response_time_ms=metric_data['response_time_ms']
        )
        
        # Assert - All data should be preserved accurately
        assert collected_metric.service == metric_data['service']
        assert collected_metric.endpoint == metric_data['endpoint']
        assert collected_metric.error_type == metric_data['error_type']
        assert collected_metric.severity == metric_data['severity']
        assert collected_metric.count == metric_data['count']
        assert collected_metric.response_time_ms == metric_data['response_time_ms']
        
        # Timestamp should be recent (within last minute)
        time_diff = datetime.utcnow() - collected_metric.timestamp
        assert time_diff.total_seconds() < 60
        
        # Metric should be in cache
        cache_key = f"{metric_data['service']}:{metric_data['endpoint']}:{metric_data['error_type']}"
        assert cache_key in collector.metrics_cache
        assert len(collector.metrics_cache[cache_key]) >= 1  # Allow for multiple metrics with same key
        assert collected_metric in collector.metrics_cache[cache_key]
    
    @given(multiple_error_metrics())
    @settings(max_examples=20, deadline=None)
    def test_property_4_metrics_accuracy_aggregation_consistency(self, metrics_list):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any collection of error metrics, the sum of individual
        metric counts should equal the total count in aggregated metrics.
        """
        # Arrange
        assume(len(metrics_list) > 0)
        
        # Filter out invalid data
        valid_metrics = []
        for metric_data in metrics_list:
            if len(metric_data['service']) > 0 and len(metric_data['endpoint']) > 0:
                valid_metrics.append(metric_data)
        
        assume(len(valid_metrics) > 0)
        
        collector = self.create_test_collector()
        
        # Act - Collect all metrics
        collected_metrics = []
        expected_total_count = 0
        
        for metric_data in valid_metrics:
            collected_metric = collector.collect_error_metric(
                service=metric_data['service'],
                endpoint=metric_data['endpoint'],
                error_type=metric_data['error_type'],
                severity=metric_data['severity'],
                count=metric_data['count'],
                response_time_ms=metric_data['response_time_ms']
            )
            collected_metrics.append(collected_metric)
            expected_total_count += metric_data['count']
        
        # Get real-time metrics
        real_time_metrics = collector.get_real_time_metrics()
        
        # Assert - Total count should match sum of individual counts
        assert real_time_metrics['total_errors'] == expected_total_count
        
        # Assert - Service-level aggregation should be consistent
        expected_service_counts = {}
        for metric_data in valid_metrics:
            service = metric_data['service']
            if service not in expected_service_counts:
                expected_service_counts[service] = 0
            expected_service_counts[service] += metric_data['count']
        
        actual_service_counts = real_time_metrics['errors_by_service']
        assert actual_service_counts == expected_service_counts
    
    @given(st.text(min_size=1, max_size=50), st.integers(min_value=1, max_value=60), st.integers(min_value=0, max_value=10))
    @settings(max_examples=20, deadline=None)
    def test_property_4_metrics_accuracy_error_rate_bounds(self, service_name, time_window_minutes, error_count):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any service and time window, the calculated error rate
        should always be between 0 and 100 percent.
        """
        # Arrange
        assume(len(service_name.strip()) > 0)
        
        collector = self.create_test_collector()
        
        # Add some random error metrics for the service
        for i in range(error_count):
            collector.collect_error_metric(
                service=service_name,
                endpoint=f"/api/endpoint{i}",
                error_type="database",
                severity="medium",
                count=1
            )
        
        # Act - Calculate error rate
        error_rate = collector.get_error_rate(service_name, time_window_minutes)
        
        # Assert - Error rate should be within valid bounds
        assert 0.0 <= error_rate <= 100.0
        assert isinstance(error_rate, float)
    
    @given(st.lists(st.sampled_from(list(MetricType)), min_size=1, max_size=4, unique=True))
    @settings(max_examples=10, deadline=None)
    def test_property_4_metrics_accuracy_aggregation_types(self, metric_types):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any list of metric types, aggregated metrics should
        only contain the requested types and have valid values.
        """
        # Arrange - Clear cache and add some test data
        self.collector.metrics_cache.clear()
        self.collector.collect_error_metric(
            service="test-service",
            endpoint="/api/test",
            error_type="database",
            severity="high",
            count=5
        )
        
        # Act - Get aggregated metrics
        aggregated_metrics = self.collector.get_aggregated_metrics(
            metric_types=metric_types,
            time_window_minutes=5,
            group_by_service=True
        )
        
        # Assert - Only requested metric types should be present
        actual_types = {metric.metric_type for metric in aggregated_metrics}
        requested_types = set(metric_types)
        
        # All actual types should be in requested types
        assert actual_types.issubset(requested_types)
        
        # All metrics should have valid values
        for metric in aggregated_metrics:
            assert isinstance(metric.value, (int, float))
            assert metric.value >= 0  # Metrics should be non-negative
            assert isinstance(metric.dimensions, dict)
            assert isinstance(metric.unit, str)
            assert len(metric.unit) > 0
    
    @given(st.integers(min_value=1, max_value=100))
    @settings(max_examples=10, deadline=None)
    def test_property_4_metrics_accuracy_cache_consistency(self, metric_count):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any number of metrics collected, the cache should
        maintain consistency with the collected data until TTL expires.
        """
        # Arrange - Clear cache to ensure clean state
        self.collector.metrics_cache.clear()
        services = ["service-a", "service-b", "service-c"]
        collected_metrics = []
        
        # Act - Collect multiple metrics
        for i in range(metric_count):
            service = services[i % len(services)]
            metric = self.collector.collect_error_metric(
                service=service,
                endpoint=f"/api/endpoint{i}",
                error_type="timeout",
                severity="medium",
                count=1
            )
            collected_metrics.append(metric)
        
        # Assert - Cache should contain all metrics
        total_cached_metrics = 0
        for cache_key, cached_metrics in self.collector.metrics_cache.items():
            total_cached_metrics += len(cached_metrics)
        
        assert total_cached_metrics == metric_count
        
        # Assert - Real-time metrics should reflect all collected data
        real_time_metrics = self.collector.get_real_time_metrics()
        assert real_time_metrics['total_errors'] == metric_count
        
        # Assert - Each service should have correct count
        expected_service_counts = {}
        for metric in collected_metrics:
            service = metric.service
            if service not in expected_service_counts:
                expected_service_counts[service] = 0
            expected_service_counts[service] += metric.count
        
        assert real_time_metrics['errors_by_service'] == expected_service_counts
    
    @given(st.integers(min_value=6, max_value=10))  # Ensure old metrics are definitely outside TTL
    @settings(max_examples=3, deadline=None, suppress_health_check=[HealthCheck.too_slow])
    def test_property_4_metrics_accuracy_time_window_filtering(self, minutes_ago):
        """
        **Feature: api-error-resolution, Property 4: Metrics accuracy**
        **Validates: Requirements 3.1**
        
        Property: For any time window, metrics outside the window should
        not affect calculations within the window.
        """
        # Arrange - Clear cache first for test isolation
        self.collector.metrics_cache.clear()
        
        # Create metrics with different timestamps
        current_time = datetime.utcnow()
        old_time = current_time - timedelta(minutes=minutes_ago)  # Outside TTL window (5 minutes)
        
        # Manually add old metric to cache (simulating expired data)
        old_metric = ErrorMetric(
            timestamp=old_time,
            service="test-service",
            endpoint="/api/old",
            error_type="database",
            severity="low",
            count=100  # Large count to detect if it's incorrectly included
        )
        
        cache_key = f"{old_metric.service}:{old_metric.endpoint}:{old_metric.error_type}"
        self.collector.metrics_cache[cache_key] = [old_metric]
        
        # Add recent metric
        recent_metric = self.collector.collect_error_metric(
            service="test-service",
            endpoint="/api/recent",
            error_type="database",
            severity="medium",
            count=5
        )
        
        # Act - Get real-time metrics (should filter out old data)
        real_time_metrics = self.collector.get_real_time_metrics()
        
        # Assert - Only recent metrics should be included
        # The cache cleaning should remove old metrics
        assert real_time_metrics['total_errors'] == 5  # Only recent metric
        
        # Old metric should be cleaned from cache
        assert cache_key not in self.collector.metrics_cache or \
               len(self.collector.metrics_cache[cache_key]) == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])