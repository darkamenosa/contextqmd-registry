import { useEffect, useRef, useState } from "react"

import { geocodeOsm } from "@/lib/geocode"

export function useLiveLocationSearch(initialDistance: number) {
  const [isSearchVisible, setIsSearchVisible] = useState(false)
  const [query, setQuery] = useState("")
  const [suggestions, setSuggestions] = useState<
    Array<{ name: string; lat: number; lng: number }>
  >([])
  const [desktopFocused, setDesktopFocused] = useState(false)
  const [activeIndex, setActiveIndex] = useState(-1)
  const [view, setView] = useState({
    lat: 39,
    lng: -98,
    distance: initialDistance,
  })
  const [isSearching, setIsSearching] = useState(false)
  const searchAbort = useRef<AbortController | null>(null)

  const searchOpen = isSearchVisible || desktopFocused
  const trimmedQuery = query.trim()
  const shouldSearch = searchOpen && trimmedQuery.length >= 2
  const showSearchHint = searchOpen && trimmedQuery.length === 1
  const visibleSuggestions = shouldSearch ? suggestions : []
  const isSearchPending = shouldSearch && isSearching

  useEffect(() => {
    searchAbort.current?.abort()
    if (!shouldSearch) return

    const controller = new AbortController()
    searchAbort.current = controller
    const searchingFrame = requestAnimationFrame(() => {
      setIsSearching(true)
    })

    const timeoutId = window.setTimeout(async () => {
      try {
        const results = await geocodeOsm(
          trimmedQuery,
          { biasLng: view.lng },
          controller.signal
        )
        setSuggestions(results)
        setActiveIndex(results.length ? 0 : -1)
        setIsSearching(false)
      } catch (error) {
        if ((error as Error).name !== "AbortError") {
          setSuggestions([])
          setActiveIndex(-1)
          setIsSearching(false)
        }
      }
    }, 300)

    return () => {
      cancelAnimationFrame(searchingFrame)
      clearTimeout(timeoutId)
      controller.abort()
    }
  }, [shouldSearch, trimmedQuery, view.lng])

  return {
    query,
    setQuery,
    suggestions,
    setSuggestions,
    desktopFocused,
    setDesktopFocused,
    activeIndex,
    setActiveIndex,
    view,
    setView,
    isSearchVisible,
    setIsSearchVisible,
    searchOpen,
    showSearchHint,
    visibleSuggestions,
    isSearchPending,
  }
}
