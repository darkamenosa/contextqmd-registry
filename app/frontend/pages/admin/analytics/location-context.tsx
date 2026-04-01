import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useSyncExternalStore,
  type ReactNode,
} from "react"

import {
  getAnalyticsLocationSnapshot,
  navigateAnalytics,
  subscribeAnalyticsLocation,
  type AnalyticsLocationSnapshot,
} from "./lib/location-store"
import {
  parseLocationFromUrl,
  resolveAnalyticsLocation,
} from "./lib/query-location"

export type AnalyticsNavigationOptions = {
  history?: "push" | "replace"
}

export type AnalyticsLocationAdapter = {
  getLocation?: () => AnalyticsLocationSnapshot
  subscribe?: (callback: () => void) => () => void
  navigate?: (url: string, options?: AnalyticsNavigationOptions) => void
}

export type AnalyticsLocationContextValue = {
  pathname: string
  search: string
  currentUrl: string
  navigate: (url: string, options?: AnalyticsNavigationOptions) => void
}

const AnalyticsLocationContext =
  createContext<AnalyticsLocationContextValue | null>(null)

export function AnalyticsLocationProvider({
  initialUrl,
  adapter,
  children,
}: {
  initialUrl?: string
  adapter?: AnalyticsLocationAdapter
  children: ReactNode
}) {
  const resolvedAdapter = adapter ?? {}
  const initialLocation = useMemo(
    () => parseLocationFromUrl(initialUrl),
    [initialUrl]
  )
  const subscribe = resolvedAdapter.subscribe ?? subscribeAnalyticsLocation
  const getSnapshot =
    resolvedAdapter.getLocation ?? getAnalyticsLocationSnapshot
  const navigateImpl = resolvedAdapter.navigate ?? navigateAnalytics

  const location = useSyncExternalStore(
    subscribe,
    getSnapshot,
    () => initialLocation
  )
  const resolvedLocation = useMemo(
    () => resolveAnalyticsLocation(location, initialLocation),
    [initialLocation, location]
  )
  const pathname = resolvedLocation.pathname || initialLocation.pathname || ""
  const search = resolvedLocation.search
  const currentUrl = pathname ? `${pathname}${search}` : search

  const navigate = useCallback(
    (url: string, options?: AnalyticsNavigationOptions) => {
      navigateImpl(url, options)
    },
    [navigateImpl]
  )

  const value = useMemo<AnalyticsLocationContextValue>(
    () => ({
      pathname,
      search,
      currentUrl,
      navigate,
    }),
    [currentUrl, navigate, pathname, search]
  )

  return (
    <AnalyticsLocationContext.Provider value={value}>
      {children}
    </AnalyticsLocationContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAnalyticsLocationContext() {
  const context = useContext(AnalyticsLocationContext)
  if (!context) {
    throw new Error(
      "useAnalyticsLocationContext must be used within an AnalyticsLocationProvider"
    )
  }
  return context
}
