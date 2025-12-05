import { useQuery, UseQueryOptions, QueryKey } from '@tanstack/react-query'

/**
 * Custom hook that wraps React Query's useQuery with enhanced error handling
 * and consistent configuration for API calls
 */
export function useApiQuery<TData = unknown, TError = unknown>(
  queryKey: QueryKey,
  queryFn: () => Promise<TData>,
  options?: Omit<UseQueryOptions<TData, TError>, 'queryKey' | 'queryFn'>
) {
  return useQuery<TData, TError>({
    queryKey,
    queryFn,
    ...options,
  })
}

/**
 * Hook for queries that should refetch more frequently (e.g., real-time data)
 */
export function useRealtimeQuery<TData = unknown, TError = unknown>(
  queryKey: QueryKey,
  queryFn: () => Promise<TData>,
  options?: Omit<UseQueryOptions<TData, TError>, 'queryKey' | 'queryFn'>
) {
  return useQuery<TData, TError>({
    queryKey,
    queryFn,
    refetchInterval: 30000, // Refetch every 30 seconds
    refetchIntervalInBackground: false,
    ...options,
  })
}

/**
 * Hook for queries that rarely change (e.g., configuration data)
 */
export function useStaticQuery<TData = unknown, TError = unknown>(
  queryKey: QueryKey,
  queryFn: () => Promise<TData>,
  options?: Omit<UseQueryOptions<TData, TError>, 'queryKey' | 'queryFn'>
) {
  return useQuery<TData, TError>({
    queryKey,
    queryFn,
    staleTime: 30 * 60 * 1000, // 30 minutes
    cacheTime: 60 * 60 * 1000, // 1 hour
    ...options,
  })
}
