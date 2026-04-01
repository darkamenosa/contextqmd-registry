export const DEFAULT_ANALYTICS_SCOPE_PATH = "/admin/analytics/sites/current"
export const DEFAULT_ANALYTICS_REPORTS_PATH = "/admin/analytics"

function resolveAdminAnalyticsSitePath(pathname: string) {
  const match = pathname.match(/^\/admin\/analytics\/sites\/([^/]+)/)
  return match ? `/admin/analytics/sites/${match[1]}` : null
}

export function resolveAdminAnalyticsScopePath(pathname: string) {
  return resolveAdminAnalyticsSitePath(pathname) ?? DEFAULT_ANALYTICS_SCOPE_PATH
}

export function resolveAdminAnalyticsReportsPath(pathname: string) {
  return (
    resolveAdminAnalyticsSitePath(pathname) ?? DEFAULT_ANALYTICS_REPORTS_PATH
  )
}
