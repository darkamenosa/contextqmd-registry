import {
  buildShellPrefetchProps,
  prefetchShellPage,
} from "@/lib/shell-prefetch"

function normalizeAdminShellPath(url: string): string {
  const path = url.split("?")[0].split("#")[0]

  if (path === "/admin" || path === "/admin/") {
    return "/admin/dashboard"
  }

  return path.replace(/\/+$/, "")
}

export function adminShellCacheTags(url: string): string[] {
  switch (normalizeAdminShellPath(url)) {
    case "/admin/dashboard":
      return ["admin-dashboard"]
    case "/admin/libraries":
      return ["admin-libraries"]
    case "/admin/crawl_requests":
      return ["admin-crawl-requests"]
    case "/admin/users":
      return ["admin-users"]
    case "/admin/analytics":
      return ["admin-analytics-reports"]
    case "/admin/analytics/live":
      return ["admin-analytics-live"]
    case "/admin/proxy_configs":
      return ["admin-proxy-configs"]
    case "/admin/webhooks":
      return ["admin-webhooks"]
    case "/admin/settings":
      return ["admin-settings"]
    case "/admin/settings/team":
      return ["admin-settings-team"]
    case "/admin/settings/analytics":
      return ["admin-settings-analytics"]
    default:
      return []
  }
}

export function adminShellPrefetchProps(url: string) {
  return buildShellPrefetchProps(adminShellCacheTags(url))
}

export function prefetchAdminShellPage(url: string) {
  prefetchShellPage(url, adminShellCacheTags(url))
}
