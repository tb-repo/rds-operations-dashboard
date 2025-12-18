"""
Performance Optimization Module

Implements caching, query optimization, and performance enhancements
for the API error resolution system.

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

import time
import json
import hashlib
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional, Tuple, Callable
from dataclasses import dataclass, asdict
from enum import Enum
import logging
import threading
from collections import OrderedDict, defaultdict
import weakref

logger = logging.getLogger(__name__)


class CacheType(Enum):
    """Types of caches available."""
    RESOLUTION_STRATEGY = "resolution_strategy"
    ERROR_PATTERN = "error_pattern"
    METRICS_QUERY = "metrics_query"
    CIRCUIT_BREAKER_STATE = "circuit_breaker_state"


@dataclass
class CacheEntry:
    """Represents a cache entry with metadata."""
    key: str
    value: Any
    created_at: datetime
    last_accessed: datetime
    access_count: int
    ttl_seconds: int
    cache_type: CacheType
    
    def is_expired(self) -> bool:
        """Check if cache entry is expired."""
        if self.ttl_seconds <= 0:
            return False  # No expiration
        
        age_seconds = (datetime.now(timezone.utc) - self.created_at).total_seconds()
        return age_seconds > self.ttl_seconds
    
    def touch(self):
        """Update last accessed time and increment access count."""
        self.last_accessed = datetime.now(timezone.utc)
        self.access_count += 1


class LRUCache:
    """
    Thread-safe LRU (Least Recently Used) cache implementation.
    
    Features:
    - TTL (Time To Live) support
    - Thread-safe operations
    - Memory-efficient with size limits
    - Access statistics
    """
    
    def __init__(self, max_size: int = 1000, default_ttl: int = 300):
        """
        Initialize LRU cache.
        
        Args:
            max_size: Maximum number of entries
            default_ttl: Default TTL in seconds (0 = no expiration)
        """
        self.max_size = max_size
        self.default_ttl = default_ttl
        self._cache: OrderedDict[str, CacheEntry] = OrderedDict()
        self._lock = threading.RLock()
        self._stats = {
            'hits': 0,
            'misses': 0,
            'evictions': 0,
            'expirations': 0
        }
    
    def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache.
        
        Args:
            key: Cache key
        
        Returns:
            Cached value or None if not found/expired
        """
        with self._lock:
            entry = self._cache.get(key)
            
            if entry is None:
                self._stats['misses'] += 1
                return None
            
            # Check if expired
            if entry.is_expired():
                del self._cache[key]
                self._stats['expirations'] += 1
                self._stats['misses'] += 1
                return None
            
            # Move to end (most recently used)
            self._cache.move_to_end(key)
            entry.touch()
            self._stats['hits'] += 1
            
            return entry.value
    
    def put(self, key: str, value: Any, ttl: Optional[int] = None, cache_type: CacheType = CacheType.RESOLUTION_STRATEGY):
        """
        Put value in cache.
        
        Args:
            key: Cache key
            value: Value to cache
            ttl: TTL in seconds (None = use default)
            cache_type: Type of cache entry
        """
        with self._lock:
            ttl = ttl if ttl is not None else self.default_ttl
            
            entry = CacheEntry(
                key=key,
                value=value,
                created_at=datetime.now(timezone.utc),
                last_accessed=datetime.now(timezone.utc),
                access_count=1,
                ttl_seconds=ttl,
                cache_type=cache_type
            )
            
            # Remove existing entry if present
            if key in self._cache:
                del self._cache[key]
            
            # Add new entry
            self._cache[key] = entry
            
            # Evict oldest entries if over size limit
            while len(self._cache) > self.max_size:
                oldest_key = next(iter(self._cache))
                del self._cache[oldest_key]
                self._stats['evictions'] += 1
    
    def invalidate(self, key: str) -> bool:
        """
        Invalidate a cache entry.
        
        Args:
            key: Cache key to invalidate
        
        Returns:
            True if key was found and removed
        """
        with self._lock:
            if key in self._cache:
                del self._cache[key]
                return True
            return False
    
    def clear(self, cache_type: Optional[CacheType] = None):
        """
        Clear cache entries.
        
        Args:
            cache_type: If specified, only clear entries of this type
        """
        with self._lock:
            if cache_type is None:
                self._cache.clear()
            else:
                keys_to_remove = [
                    key for key, entry in self._cache.items()
                    if entry.cache_type == cache_type
                ]
                for key in keys_to_remove:
                    del self._cache[key]
    
    def cleanup_expired(self) -> int:
        """
        Remove expired entries.
        
        Returns:
            Number of entries removed
        """
        with self._lock:
            expired_keys = [
                key for key, entry in self._cache.items()
                if entry.is_expired()
            ]
            
            for key in expired_keys:
                del self._cache[key]
                self._stats['expirations'] += 1
            
            return len(expired_keys)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        with self._lock:
            total_requests = self._stats['hits'] + self._stats['misses']
            hit_rate = self._stats['hits'] / total_requests if total_requests > 0 else 0
            
            return {
                'size': len(self._cache),
                'max_size': self.max_size,
                'hit_rate': hit_rate,
                'hits': self._stats['hits'],
                'misses': self._stats['misses'],
                'evictions': self._stats['evictions'],
                'expirations': self._stats['expirations'],
                'total_requests': total_requests
            }


class ResolutionStrategyCache:
    """
    Specialized cache for resolution strategies with intelligent key generation.
    """
    
    def __init__(self, cache: LRUCache):
        """Initialize with underlying cache."""
        self.cache = cache
    
    def _generate_strategy_key(self, error_category: str, error_severity: str, 
                             status_code: int, service: str) -> str:
        """
        Generate cache key for resolution strategy.
        
        Args:
            error_category: Error category
            error_severity: Error severity
            status_code: HTTP status code
            service: Service name
        
        Returns:
            Cache key string
        """
        key_data = f"{error_category}:{error_severity}:{status_code}:{service}"
        return f"strategy:{hashlib.md5(key_data.encode()).hexdigest()}"
    
    def get_strategy(self, error_category: str, error_severity: str, 
                    status_code: int, service: str) -> Optional[str]:
        """
        Get cached resolution strategy.
        
        Args:
            error_category: Error category
            error_severity: Error severity
            status_code: HTTP status code
            service: Service name
        
        Returns:
            Cached strategy name or None
        """
        key = self._generate_strategy_key(error_category, error_severity, status_code, service)
        return self.cache.get(key)
    
    def cache_strategy(self, error_category: str, error_severity: str, 
                      status_code: int, service: str, strategy: str, ttl: int = 600):
        """
        Cache resolution strategy.
        
        Args:
            error_category: Error category
            error_severity: Error severity
            status_code: HTTP status code
            service: Service name
            strategy: Strategy name to cache
            ttl: TTL in seconds
        """
        key = self._generate_strategy_key(error_category, error_severity, status_code, service)
        self.cache.put(key, strategy, ttl, CacheType.RESOLUTION_STRATEGY)


class ErrorPatternCache:
    """
    Cache for compiled error patterns to avoid repeated regex compilation.
    """
    
    def __init__(self, cache: LRUCache):
        """Initialize with underlying cache."""
        self.cache = cache
    
    def get_compiled_pattern(self, pattern: str):
        """
        Get compiled regex pattern from cache.
        
        Args:
            pattern: Regex pattern string
        
        Returns:
            Compiled regex pattern or None
        """
        key = f"pattern:{hashlib.md5(pattern.encode()).hexdigest()}"
        return self.cache.get(key)
    
    def cache_compiled_pattern(self, pattern: str, compiled_pattern, ttl: int = 3600):
        """
        Cache compiled regex pattern.
        
        Args:
            pattern: Original pattern string
            compiled_pattern: Compiled regex object
            ttl: TTL in seconds
        """
        key = f"pattern:{hashlib.md5(pattern.encode()).hexdigest()}"
        self.cache.put(key, compiled_pattern, ttl, CacheType.ERROR_PATTERN)


class QueryOptimizer:
    """
    Database query optimization utilities.
    """
    
    def __init__(self):
        """Initialize query optimizer."""
        self.query_cache = {}
        self.query_stats = defaultdict(lambda: {'count': 0, 'total_time': 0, 'avg_time': 0})
    
    def optimize_error_query(self, filters: Dict[str, Any]) -> Dict[str, Any]:
        """
        Optimize error query based on filters.
        
        Args:
            filters: Query filters
        
        Returns:
            Optimized query parameters
        """
        optimized = filters.copy()
        
        # Add index hints for common queries
        if 'service' in filters and 'timestamp' in filters:
            optimized['_index_hint'] = 'service_timestamp_idx'
        elif 'error_type' in filters and 'severity' in filters:
            optimized['_index_hint'] = 'error_type_severity_idx'
        elif 'timestamp' in filters:
            optimized['_index_hint'] = 'timestamp_idx'
        
        # Optimize time range queries
        if 'start_time' in filters and 'end_time' in filters:
            # Ensure time range is reasonable
            start_time = filters['start_time']
            end_time = filters['end_time']
            
            if isinstance(start_time, str):
                start_time = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
            if isinstance(end_time, str):
                end_time = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
            
            time_diff = end_time - start_time
            
            # Limit query range to prevent performance issues
            max_range = timedelta(days=7)
            if time_diff > max_range:
                optimized['end_time'] = start_time + max_range
                logger.warning(f"Query time range limited to {max_range.days} days for performance")
        
        # Add pagination for large result sets
        if 'limit' not in optimized:
            optimized['limit'] = 1000  # Default limit
        
        # Ensure limit is reasonable
        if optimized.get('limit', 0) > 10000:
            optimized['limit'] = 10000
            logger.warning("Query limit capped at 10000 for performance")
        
        return optimized
    
    def track_query_performance(self, query_type: str, execution_time: float):
        """
        Track query performance for optimization.
        
        Args:
            query_type: Type of query
            execution_time: Execution time in seconds
        """
        stats = self.query_stats[query_type]
        stats['count'] += 1
        stats['total_time'] += execution_time
        stats['avg_time'] = stats['total_time'] / stats['count']
    
    def get_slow_queries(self, threshold_seconds: float = 1.0) -> List[Dict[str, Any]]:
        """
        Get queries that are performing slowly.
        
        Args:
            threshold_seconds: Threshold for slow queries
        
        Returns:
            List of slow query statistics
        """
        slow_queries = []
        
        for query_type, stats in self.query_stats.items():
            if stats['avg_time'] > threshold_seconds:
                slow_queries.append({
                    'query_type': query_type,
                    'avg_time': stats['avg_time'],
                    'count': stats['count'],
                    'total_time': stats['total_time']
                })
        
        return sorted(slow_queries, key=lambda x: x['avg_time'], reverse=True)


class PerformanceOptimizer:
    """
    Main performance optimization coordinator.
    """
    
    def __init__(self, cache_size: int = 2000, default_ttl: int = 300):
        """
        Initialize performance optimizer.
        
        Args:
            cache_size: Maximum cache size
            default_ttl: Default TTL in seconds
        """
        self.cache = LRUCache(max_size=cache_size, default_ttl=default_ttl)
        self.strategy_cache = ResolutionStrategyCache(self.cache)
        self.pattern_cache = ErrorPatternCache(self.cache)
        self.query_optimizer = QueryOptimizer()
        
        # Performance monitoring
        self.performance_stats = {
            'cache_enabled': True,
            'optimization_enabled': True,
            'start_time': datetime.now(timezone.utc)
        }
        
        # Background cleanup thread
        self._cleanup_thread = None
        self._start_cleanup_thread()
    
    def _start_cleanup_thread(self):
        """Start background cleanup thread."""
        def cleanup_worker():
            while True:
                try:
                    time.sleep(60)  # Run every minute
                    expired_count = self.cache.cleanup_expired()
                    if expired_count > 0:
                        logger.debug(f"Cleaned up {expired_count} expired cache entries")
                except Exception as e:
                    logger.error(f"Cache cleanup error: {str(e)}")
        
        self._cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
        self._cleanup_thread.start()
    
    def optimize_error_detection(self, detector_func: Callable) -> Callable:
        """
        Decorator to optimize error detection with caching.
        
        Args:
            detector_func: Error detection function to optimize
        
        Returns:
            Optimized function
        """
        def optimized_detector(*args, **kwargs):
            # Generate cache key for error detection
            cache_key = f"detection:{hashlib.md5(str(args + tuple(kwargs.items())).encode()).hexdigest()}"
            
            # Try to get from cache first
            cached_result = self.cache.get(cache_key)
            if cached_result is not None:
                return cached_result
            
            # Execute original function
            start_time = time.perf_counter()
            result = detector_func(*args, **kwargs)
            execution_time = time.perf_counter() - start_time
            
            # Cache result (short TTL for error detection)
            self.cache.put(cache_key, result, ttl=60, cache_type=CacheType.ERROR_PATTERN)
            
            # Track performance
            self.query_optimizer.track_query_performance('error_detection', execution_time)
            
            return result
        
        return optimized_detector
    
    def get_cached_strategy(self, error_category: str, error_severity: str, 
                           status_code: int, service: str) -> Optional[str]:
        """Get cached resolution strategy."""
        return self.strategy_cache.get_strategy(error_category, error_severity, status_code, service)
    
    def cache_strategy(self, error_category: str, error_severity: str, 
                      status_code: int, service: str, strategy: str):
        """Cache resolution strategy."""
        self.strategy_cache.cache_strategy(error_category, error_severity, status_code, service, strategy)
    
    def optimize_query(self, filters: Dict[str, Any]) -> Dict[str, Any]:
        """Optimize database query."""
        return self.query_optimizer.optimize_error_query(filters)
    
    def invalidate_cache(self, cache_type: Optional[CacheType] = None):
        """Invalidate cache entries."""
        self.cache.clear(cache_type)
    
    def get_performance_stats(self) -> Dict[str, Any]:
        """
        Get comprehensive performance statistics.
        
        Returns:
            Performance statistics dictionary
        """
        cache_stats = self.cache.get_stats()
        slow_queries = self.query_optimizer.get_slow_queries()
        
        uptime = (datetime.now(timezone.utc) - self.performance_stats['start_time']).total_seconds()
        
        return {
            'uptime_seconds': uptime,
            'cache_stats': cache_stats,
            'slow_queries': slow_queries,
            'optimization_enabled': self.performance_stats['optimization_enabled'],
            'cache_enabled': self.performance_stats['cache_enabled'],
            'query_stats': dict(self.query_optimizer.query_stats)
        }
    
    def enable_optimization(self, enabled: bool = True):
        """Enable or disable optimization features."""
        self.performance_stats['optimization_enabled'] = enabled
        if not enabled:
            self.cache.clear()
    
    def warm_cache(self, common_patterns: List[Dict[str, Any]]):
        """
        Warm up cache with common patterns.
        
        Args:
            common_patterns: List of common error patterns to pre-cache
        """
        logger.info(f"Warming cache with {len(common_patterns)} patterns")
        
        for pattern in common_patterns:
            if 'strategy' in pattern:
                self.cache_strategy(
                    error_category=pattern.get('category', 'unknown'),
                    error_severity=pattern.get('severity', 'medium'),
                    status_code=pattern.get('status_code', 500),
                    service=pattern.get('service', 'default'),
                    strategy=pattern['strategy']
                )


# Global performance optimizer instance
_performance_optimizer: Optional[PerformanceOptimizer] = None


def get_performance_optimizer() -> PerformanceOptimizer:
    """
    Get the global performance optimizer instance.
    
    Returns:
        PerformanceOptimizer instance
    """
    global _performance_optimizer
    if _performance_optimizer is None:
        _performance_optimizer = PerformanceOptimizer()
    return _performance_optimizer


def optimize_error_detection(func: Callable) -> Callable:
    """
    Decorator to optimize error detection functions.
    
    Args:
        func: Function to optimize
    
    Returns:
        Optimized function
    """
    optimizer = get_performance_optimizer()
    return optimizer.optimize_error_detection(func)


def cache_resolution_strategy(error_category: str, error_severity: str, 
                            status_code: int, service: str, strategy: str):
    """
    Cache a resolution strategy for future use.
    
    Args:
        error_category: Error category
        error_severity: Error severity
        status_code: HTTP status code
        service: Service name
        strategy: Strategy to cache
    """
    optimizer = get_performance_optimizer()
    optimizer.cache_strategy(error_category, error_severity, status_code, service, strategy)


def get_cached_resolution_strategy(error_category: str, error_severity: str, 
                                 status_code: int, service: str) -> Optional[str]:
    """
    Get cached resolution strategy.
    
    Args:
        error_category: Error category
        error_severity: Error severity
        status_code: HTTP status code
        service: Service name
    
    Returns:
        Cached strategy name or None
    """
    optimizer = get_performance_optimizer()
    return optimizer.get_cached_strategy(error_category, error_severity, status_code, service)