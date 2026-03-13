/**
 * Format a library's source display string.
 * Git-based sources (github, gitlab, bitbucket, git) show namespace/name
 * since the platform icon already identifies the host.
 * Web-based sources (website, llms_txt, openapi) show the URL domain + path.
 */
const GIT_SOURCE_TYPES = new Set([
  "github",
  "github_markdown",
  "gitlab",
  "bitbucket",
  "git",
])

export function formatSource(lib: {
  namespace: string
  name: string
  sourceType?: string | null
  homepageUrl?: string | null
}): string {
  if (GIT_SOURCE_TYPES.has(lib.sourceType ?? "") || !lib.homepageUrl) {
    return `${lib.namespace}/${lib.name}`
  }
  try {
    const u = new URL(lib.homepageUrl)
    return u.hostname + (u.pathname === "/" ? "" : u.pathname)
  } catch {
    return `${lib.namespace}/${lib.name}`
  }
}
