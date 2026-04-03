import type { CacheForOption, LinkPrefetchOption } from "@inertiajs/core"
import { router } from "@inertiajs/react"

const DEFAULT_LINK_PREFETCH: LinkPrefetchOption[] = ["mount", "hover"]
const DEFAULT_LINK_CACHE_FOR: CacheForOption[] = ["15s", "1m"]
const DEFAULT_PROGRAMMATIC_CACHE_FOR: CacheForOption = "1m"

export interface ShellLinkPrefetchProps {
  prefetch: LinkPrefetchOption[]
  cacheFor: CacheForOption | CacheForOption[]
  cacheTags: string[]
}

interface ShellPrefetchOptions {
  linkPrefetch?: LinkPrefetchOption[]
  linkCacheFor?: CacheForOption | CacheForOption[]
  programmaticCacheFor?: CacheForOption
}

export function buildShellPrefetchProps(
  cacheTags: string[],
  options: ShellPrefetchOptions = {}
): Partial<ShellLinkPrefetchProps> {
  if (cacheTags.length === 0) return {}

  return {
    prefetch: options.linkPrefetch ?? DEFAULT_LINK_PREFETCH,
    cacheFor: options.linkCacheFor ?? DEFAULT_LINK_CACHE_FOR,
    cacheTags,
  }
}

export function prefetchShellPage(
  url: string,
  cacheTags: string[],
  options: ShellPrefetchOptions = {}
) {
  if (cacheTags.length === 0) return

  router.prefetch(
    url,
    {},
    {
      cacheFor: options.programmaticCacheFor ?? DEFAULT_PROGRAMMATIC_CACHE_FOR,
      cacheTags,
    }
  )
}
