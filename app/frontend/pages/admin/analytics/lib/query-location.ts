export type AnalyticsLocationLike = {
  pathname: string
  search: string
}

export function parseLocationFromUrl(
  url: string | undefined
): AnalyticsLocationLike {
  if (!url) return { pathname: "", search: "" }

  const parsed = new URL(url, "http://analytics.test")
  return {
    pathname: parsed.pathname,
    search: parsed.search,
  }
}

export function resolveAnalyticsLocation(
  location: AnalyticsLocationLike,
  fallback: AnalyticsLocationLike
): AnalyticsLocationLike {
  if (location.pathname) return location
  return fallback
}
