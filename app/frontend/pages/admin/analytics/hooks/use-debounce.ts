import { useCallback, useEffect, useRef } from "react"

const DEBOUNCE_DELAY = 300

/**
 * Debounce hook following Plausible's pattern.
 * Delays function execution until after the specified delay has passed
 * since the last time it was invoked.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function useDebounce<T extends (...args: any[]) => any>(
  fn: T,
  delay = DEBOUNCE_DELAY
): T {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current)
      }
    }
  }, [])

  return useCallback(
    ((...args: Parameters<T>) => {
      if (timerRef.current) {
        clearTimeout(timerRef.current)
      }

      timerRef.current = setTimeout(() => {
        fn(...args)
      }, delay)
    }) as T,
    [fn, delay]
  )
}
