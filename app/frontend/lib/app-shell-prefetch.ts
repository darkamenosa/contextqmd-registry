import {
  buildShellPrefetchProps,
  prefetchShellPage,
} from "@/lib/shell-prefetch"

export const ALL_APP_SHELL_CACHE_TAGS = [
  "app-dashboard",
  "app-crawl-requests",
  "app-settings",
  "app-access-tokens",
] as const

function normalizeAppShellPath(url: string): string {
  const path = url.split("?")[0].split("#")[0]

  if (/^\/app\/\d+$/.test(path)) {
    return "/app/dashboard"
  }

  return path.replace(/^\/app\/\d+(?=\/|$)/, "/app")
}

export function appShellCacheTags(url: string): string[] {
  switch (normalizeAppShellPath(url)) {
    case "/app":
    case "/app/dashboard":
      return ["app-dashboard"]
    case "/app/crawl/new":
      return ["app-crawl-requests"]
    case "/app/settings":
      return ["app-settings"]
    case "/app/access_tokens":
      return ["app-access-tokens"]
    default:
      return []
  }
}

export function appShellPrefetchProps(url: string) {
  return buildShellPrefetchProps(appShellCacheTags(url))
}

export function prefetchAppShellPage(url: string) {
  prefetchShellPage(url, appShellCacheTags(url))
}
