"""
Retry Logic with Exponential Backoff

Provides configurable retry decorator with exponential backoff and jitter
to prevent thundering herd problems.

Metadata:
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-04T10:15:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-7.2 → DESIGN-RetryLogic → TASK-6.2",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
"""

import time
import random
from typing import Callable, Type, Tuple, Optional
from functools import wraps
import logging

logger = logging.getLogger(__name__)


class RetryExhausted(Exception):
    """Raised when all retry attempts have been exhausted."""
    pass


def retry(
    max_attempts: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    on_retry: Optional[Callable] = None
):
    """
    Decorator that retries a function with exponential backoff.
    
    Args:
        max_attempts: Maximum number of attempts (including initial call)
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        exponential_base: Base for exponential backoff (typically 2)
        jitter: Whether to add random jitter to prevent thundering herd
        exceptions: Tuple of exception types to retry on
        on_retry: Optional callback function called on each retry
    
    Returns:
        Decorated function
    
    Example:
        @retry(max_attempts=5, base_delay=2.0, exceptions=(ConnectionError, TimeoutError))
        def fetch_data():
            # Your code here
            pass
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempt = 0
            last_exception = None
            
            while attempt < max_attempts:
                try:
                    # Attempt the function call
                    return func(*args, **kwargs)
                    
                except exceptions as e:
                    attempt += 1
                    last_exception = e
                    
                    # If we've exhausted all attempts, raise
                    if attempt >= max_attempts:
                        logger.error(
                            f"Retry exhausted for {func.__name__} after {max_attempts} attempts",
                            extra={
                                'function': func.__name__,
                                'attempts': attempt,
                                'error': str(e)
                            }
                        )
                        raise RetryExhausted(
                            f"Failed after {max_attempts} attempts. Last error: {str(e)}"
                        ) from e
                    
                    # Calculate delay with exponential backoff
                    delay = min(base_delay * (exponential_base ** (attempt - 1)), max_delay)
                    
                    # Add jitter if enabled (random value between 0 and delay)
                    if jitter:
                        delay = delay * (0.5 + random.random() * 0.5)
                    
                    logger.warning(
                        f"Retry attempt {attempt}/{max_attempts} for {func.__name__} after {delay:.2f}s",
                        extra={
                            'function': func.__name__,
                            'attempt': attempt,
                            'max_attempts': max_attempts,
                            'delay': delay,
                            'error': str(e)
                        }
                    )
                    
                    # Call retry callback if provided
                    if on_retry:
                        try:
                            on_retry(attempt, delay, e)
                        except Exception as callback_error:
                            logger.error(f"Error in retry callback: {callback_error}")
                    
                    # Wait before retrying
                    time.sleep(delay)
            
            # This should never be reached, but just in case
            if last_exception:
                raise last_exception
                
        return wrapper
    return decorator


def retry_with_backoff(
    func: Callable,
    max_attempts: int = 3,
    base_delay: float = 1.0,
    exceptions: Tuple[Type[Exception], ...] = (Exception,)
) -> any:
    """
    Functional interface for retry logic (non-decorator version).
    
    Args:
        func: Function to retry
        max_attempts: Maximum number of attempts
        base_delay: Initial delay in seconds
        exceptions: Tuple of exception types to retry on
    
    Returns:
        Result of the function call
    
    Example:
        result = retry_with_backoff(
            lambda: risky_operation(),
            max_attempts=5,
            exceptions=(ConnectionError,)
        )
    """
    decorated = retry(
        max_attempts=max_attempts,
        base_delay=base_delay,
        exceptions=exceptions
    )(func)
    
    return decorated()


# Common retry configurations for different scenarios

def retry_aws_api(func: Callable) -> Callable:
    """
    Retry configuration optimized for AWS API calls.
    Handles throttling and transient errors.
    """
    return retry(
        max_attempts=5,
        base_delay=1.0,
        max_delay=30.0,
        exponential_base=2.0,
        jitter=True,
        exceptions=(Exception,)  # AWS SDK exceptions
    )(func)


def retry_database(func: Callable) -> Callable:
    """
    Retry configuration optimized for database operations.
    Handles connection errors and timeouts.
    """
    return retry(
        max_attempts=3,
        base_delay=0.5,
        max_delay=10.0,
        exponential_base=2.0,
        jitter=True,
        exceptions=(Exception,)  # Database exceptions
    )(func)


def retry_http(func: Callable) -> Callable:
    """
    Retry configuration optimized for HTTP requests.
    Handles network errors and 5xx responses.
    """
    return retry(
        max_attempts=4,
        base_delay=2.0,
        max_delay=60.0,
        exponential_base=2.0,
        jitter=True,
        exceptions=(Exception,)  # HTTP exceptions
    )(func)
