"""
Circuit Breaker Pattern Implementation

Prevents cascading failures by stopping requests to failing services.
Implements three states: CLOSED (normal), OPEN (failing), HALF_OPEN (testing recovery).

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-04T10:30:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-7.3 → DESIGN-CircuitBreaker → TASK-6.3",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import time
import threading
from typing import Callable, Optional, Dict, Any
from functools import wraps
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class CircuitState(Enum):
    """Circuit breaker states."""
    CLOSED = "closed"      # Normal operation, requests pass through
    OPEN = "open"          # Circuit is open, requests fail immediately
    HALF_OPEN = "half_open"  # Testing if service has recovered


class CircuitBreakerError(Exception):
    """Raised when circuit breaker is open."""
    pass


class CircuitBreaker:
    """
    Circuit breaker implementation with configurable thresholds.
    
    States:
    - CLOSED: Normal operation, all requests pass through
    - OPEN: Too many failures, all requests fail immediately
    - HALF_OPEN: Testing recovery, limited requests pass through
    
    Transitions:
    - CLOSED -> OPEN: When failure threshold is exceeded
    - OPEN -> HALF_OPEN: After timeout period
    - HALF_OPEN -> CLOSED: When success threshold is met
    - HALF_OPEN -> OPEN: When any failure occurs
    """
    
    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        success_threshold: int = 2,
        timeout: float = 60.0,
        expected_exception: type = Exception,
        on_state_change: Optional[Callable] = None
    ):
        """
        Initialize circuit breaker.
        
        Args:
            name: Identifier for this circuit breaker
            failure_threshold: Number of failures before opening circuit
            success_threshold: Number of successes in HALF_OPEN before closing
            timeout: Seconds to wait before transitioning from OPEN to HALF_OPEN
            expected_exception: Exception type that triggers circuit breaker
            on_state_change: Callback function called on state changes
        """
        self.name = name
        self.failure_threshold = failure_threshold
        self.success_threshold = success_threshold
        self.timeout = timeout
        self.expected_exception = expected_exception
        self.on_state_change = on_state_change
        
        # State tracking
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = None
        self._lock = threading.Lock()
        
        # Metrics
        self._total_calls = 0
        self._total_failures = 0
        self._total_successes = 0
        self._state_changes = 0
    
    @property
    def state(self) -> CircuitState:
        """Get current circuit state."""
        with self._lock:
            # Check if we should transition from OPEN to HALF_OPEN
            if self._state == CircuitState.OPEN:
                if self._last_failure_time and (time.time() - self._last_failure_time) >= self.timeout:
                    self._transition_to(CircuitState.HALF_OPEN)
            
            return self._state
    
    def _transition_to(self, new_state: CircuitState):
        """Transition to a new state."""
        old_state = self._state
        self._state = new_state
        self._state_changes += 1
        
        # Reset counters on state change
        if new_state == CircuitState.HALF_OPEN:
            self._success_count = 0
            self._failure_count = 0
        elif new_state == CircuitState.CLOSED:
            self._failure_count = 0
            self._success_count = 0
        
        logger.info(
            f"Circuit breaker '{self.name}' state change: {old_state.value} -> {new_state.value}",
            extra={
                'circuit_breaker': self.name,
                'old_state': old_state.value,
                'new_state': new_state.value,
                'failure_count': self._failure_count,
                'success_count': self._success_count
            }
        )
        
        # Call state change callback if provided
        if self.on_state_change:
            try:
                self.on_state_change(self.name, old_state, new_state)
            except Exception as e:
                logger.error(f"Error in circuit breaker state change callback: {e}")
    
    def call(self, func: Callable, *args, **kwargs) -> Any:
        """
        Execute function through circuit breaker.
        
        Args:
            func: Function to execute
            *args: Positional arguments for function
            **kwargs: Keyword arguments for function
        
        Returns:
            Result of function call
        
        Raises:
            CircuitBreakerError: If circuit is open
        """
        with self._lock:
            self._total_calls += 1
            current_state = self.state
            
            # If circuit is OPEN, fail immediately
            if current_state == CircuitState.OPEN:
                raise CircuitBreakerError(
                    f"Circuit breaker '{self.name}' is OPEN. "
                    f"Service is unavailable. Will retry after {self.timeout}s."
                )
        
        # Try to execute the function
        try:
            result = func(*args, **kwargs)
            self._on_success()
            return result
            
        except self.expected_exception as e:
            self._on_failure()
            raise
    
    def _on_success(self):
        """Handle successful call."""
        with self._lock:
            self._total_successes += 1
            self._failure_count = 0  # Reset failure count on success
            
            if self._state == CircuitState.HALF_OPEN:
                self._success_count += 1
                
                # If we've had enough successes, close the circuit
                if self._success_count >= self.success_threshold:
                    self._transition_to(CircuitState.CLOSED)
    
    def _on_failure(self):
        """Handle failed call."""
        with self._lock:
            self._total_failures += 1
            self._failure_count += 1
            self._last_failure_time = time.time()
            
            # If in HALF_OPEN, any failure opens the circuit again
            if self._state == CircuitState.HALF_OPEN:
                self._transition_to(CircuitState.OPEN)
            
            # If in CLOSED, check if we've exceeded failure threshold
            elif self._state == CircuitState.CLOSED:
                if self._failure_count >= self.failure_threshold:
                    self._transition_to(CircuitState.OPEN)
    
    def reset(self):
        """Manually reset circuit breaker to CLOSED state."""
        with self._lock:
            self._transition_to(CircuitState.CLOSED)
            self._failure_count = 0
            self._success_count = 0
            self._last_failure_time = None
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get circuit breaker metrics."""
        with self._lock:
            return {
                'name': self.name,
                'state': self._state.value,
                'total_calls': self._total_calls,
                'total_successes': self._total_successes,
                'total_failures': self._total_failures,
                'failure_count': self._failure_count,
                'success_count': self._success_count,
                'state_changes': self._state_changes,
                'failure_threshold': self.failure_threshold,
                'success_threshold': self.success_threshold,
                'timeout': self.timeout
            }


# Global registry of circuit breakers
_circuit_breakers: Dict[str, CircuitBreaker] = {}
_registry_lock = threading.Lock()


def get_circuit_breaker(
    name: str,
    failure_threshold: int = 5,
    success_threshold: int = 2,
    timeout: float = 60.0,
    expected_exception: type = Exception
) -> CircuitBreaker:
    """
    Get or create a circuit breaker by name.
    
    Args:
        name: Circuit breaker identifier
        failure_threshold: Number of failures before opening
        success_threshold: Number of successes before closing
        timeout: Seconds before transitioning to HALF_OPEN
        expected_exception: Exception type to catch
    
    Returns:
        CircuitBreaker instance
    """
    with _registry_lock:
        if name not in _circuit_breakers:
            _circuit_breakers[name] = CircuitBreaker(
                name=name,
                failure_threshold=failure_threshold,
                success_threshold=success_threshold,
                timeout=timeout,
                expected_exception=expected_exception
            )
        return _circuit_breakers[name]


def circuit_breaker(
    name: str,
    failure_threshold: int = 5,
    success_threshold: int = 2,
    timeout: float = 60.0,
    expected_exception: type = Exception
):
    """
    Decorator to wrap a function with circuit breaker protection.
    
    Args:
        name: Circuit breaker identifier
        failure_threshold: Number of failures before opening
        success_threshold: Number of successes before closing
        timeout: Seconds before transitioning to HALF_OPEN
        expected_exception: Exception type to catch
    
    Example:
        @circuit_breaker(name='external_api', failure_threshold=3, timeout=30.0)
        def call_external_api():
            # Your code here
            pass
    """
    def decorator(func: Callable) -> Callable:
        cb = get_circuit_breaker(
            name=name,
            failure_threshold=failure_threshold,
            success_threshold=success_threshold,
            timeout=timeout,
            expected_exception=expected_exception
        )
        
        @wraps(func)
        def wrapper(*args, **kwargs):
            return cb.call(func, *args, **kwargs)
        
        return wrapper
    return decorator


def get_all_circuit_breaker_metrics() -> Dict[str, Dict[str, Any]]:
    """
    Get metrics for all registered circuit breakers.
    
    Returns:
        Dictionary mapping circuit breaker names to their metrics
    """
    with _registry_lock:
        return {
            name: cb.get_metrics()
            for name, cb in _circuit_breakers.items()
        }


def reset_all_circuit_breakers():
    """Reset all circuit breakers to CLOSED state."""
    with _registry_lock:
        for cb in _circuit_breakers.values():
            cb.reset()
