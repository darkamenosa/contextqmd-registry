import { router } from "@inertiajs/react"

import { buildShellPrefetchProps } from "@/lib/shell-prefetch"

export const ALL_PUBLIC_SHELL_CACHE_TAGS = [
  "public-home",
  "public-libraries",
  "public-rankings",
  "public-crawl-requests",
  "public-about",
  "public-contact",
  "public-privacy",
  "public-terms",
  "public-login",
  "public-register",
] as const

function normalizePublicShellPath(url: string): string {
  const path = url.split("?")[0].split("#")[0]

  if (path === "" || path === "/") {
    return "/"
  }

  return path.replace(/\/+$/, "")
}

export function publicShellCacheTags(url: string): string[] {
  switch (normalizePublicShellPath(url)) {
    case "/":
      return ["public-home"]
    case "/libraries":
      return ["public-libraries"]
    case "/rankings":
      return ["public-rankings"]
    case "/crawl":
      return ["public-crawl-requests"]
    case "/about":
      return ["public-about"]
    case "/contact":
      return ["public-contact"]
    case "/privacy":
      return ["public-privacy"]
    case "/terms":
      return ["public-terms"]
    case "/login":
      return ["public-login"]
    case "/register":
      return ["public-register"]
    default:
      return []
  }
}

export function publicShellPrefetchProps(url: string) {
  return buildShellPrefetchProps(publicShellCacheTags(url), {
    linkCacheFor: ["10s", "30s"],
    programmaticCacheFor: "30s",
  })
}

export function flushPublicShellCache() {
  router.flushByCacheTags([...ALL_PUBLIC_SHELL_CACHE_TAGS])
}
