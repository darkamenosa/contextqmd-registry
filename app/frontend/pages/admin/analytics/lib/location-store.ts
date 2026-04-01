export const ANALYTICS_LOCATION_CHANGE_EVENT = "analytics:location-change"

export type AnalyticsLocationSnapshot = {
  pathname: string
  search: string
}

export const EMPTY_ANALYTICS_LOCATION_SNAPSHOT: AnalyticsLocationSnapshot = {
  pathname: "",
  search: "",
}

let cachedSnapshot = EMPTY_ANALYTICS_LOCATION_SNAPSHOT

export function getAnalyticsLocationSnapshot(): AnalyticsLocationSnapshot {
  if (typeof window === "undefined") return EMPTY_ANALYTICS_LOCATION_SNAPSHOT

  const pathname = window.location.pathname
  const search = window.location.search

  if (
    cachedSnapshot.pathname === pathname &&
    cachedSnapshot.search === search
  ) {
    return cachedSnapshot
  }

  cachedSnapshot = { pathname, search }
  return cachedSnapshot
}

export function subscribeAnalyticsLocation(callback: () => void) {
  if (typeof window === "undefined") {
    return () => {}
  }

  window.addEventListener("popstate", callback)
  window.addEventListener(ANALYTICS_LOCATION_CHANGE_EVENT, callback)

  return () => {
    window.removeEventListener("popstate", callback)
    window.removeEventListener(ANALYTICS_LOCATION_CHANGE_EVENT, callback)
  }
}

export function navigateAnalytics(
  url: string,
  options?: { history?: "push" | "replace" }
) {
  if (typeof window === "undefined") return

  if (options?.history === "replace") {
    window.history.replaceState({}, "", url)
  } else {
    window.history.pushState({}, "", url)
  }

  cachedSnapshot = {
    pathname: window.location.pathname,
    search: window.location.search,
  }

  window.dispatchEvent(new Event(ANALYTICS_LOCATION_CHANGE_EVENT))
}
