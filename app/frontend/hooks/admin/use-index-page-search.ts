import { useCallback, useEffect, useRef, useState } from "react"
import { router } from "@inertiajs/react"

interface UseIndexPageSearchOptions {
  initialQuery?: string
  routePath: string
  preserveFilters?: Record<string, string | number | boolean | undefined>
  debounceMs?: number
}

interface UseIndexPageSearchReturn {
  queryValue: string
  handleQueryChange: (value: string) => void
  handleQueryClear: () => void
}

export function useIndexPageSearch({
  initialQuery = "",
  routePath,
  preserveFilters = {},
  debounceMs = 400,
}: UseIndexPageSearchOptions): UseIndexPageSearchReturn {
  const [queryValue, setQueryValue] = useState(initialQuery)
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined)

  const performSearch = useCallback(
    (query: string) => {
      const params: Record<string, string | number | boolean> = {}
      for (const [key, value] of Object.entries(preserveFilters)) {
        if (value !== undefined) params[key] = value
      }
      if (query) params.q = query

      router.get(routePath, params, {
        preserveState: true,
        preserveScroll: true,
      })
    },
    [routePath, preserveFilters]
  )

  const handleQueryChange = useCallback(
    (value: string) => {
      setQueryValue(value)
      if (debounceRef.current) clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => performSearch(value), debounceMs)
    },
    [performSearch, debounceMs]
  )

  const handleQueryClear = useCallback(() => {
    setQueryValue("")
    if (debounceRef.current) clearTimeout(debounceRef.current)
    performSearch("")
  }, [performSearch])

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [])

  return { queryValue, handleQueryChange, handleQueryClear }
}
