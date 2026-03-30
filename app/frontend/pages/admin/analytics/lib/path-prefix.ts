const DEFAULT_ANALYTICS_SCOPE_PATH = "/admin/analytics/sites/current"
const DEFAULT_ANALYTICS_REPORTS_PATH = "/admin/analytics"

function currentPathname() {
  if (typeof window === "undefined") return DEFAULT_ANALYTICS_REPORTS_PATH
  return window.location.pathname
}

export function analyticsScopePath(pathname = currentPathname()) {
  const match = pathname.match(/^\/admin\/analytics\/sites\/([^/]+)/)
  return match
    ? `/admin/analytics/sites/${match[1]}`
    : DEFAULT_ANALYTICS_SCOPE_PATH
}

export function analyticsReportsPath(pathname = currentPathname()) {
  const match = pathname.match(/^\/admin\/analytics\/sites\/([^/]+)/)
  return match
    ? `/admin/analytics/sites/${match[1]}`
    : DEFAULT_ANALYTICS_REPORTS_PATH
}

export function analyticsScopedPath(
  suffix: string,
  pathname = currentPathname()
) {
  const normalizedSuffix = suffix.startsWith("/") ? suffix : `/${suffix}`
  return `${analyticsScopePath(pathname)}${normalizedSuffix}`
}
