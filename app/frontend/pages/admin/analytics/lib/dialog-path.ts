// Central helpers for building and parsing analytics dialog deep-links

import { analyticsReportsPath } from "./path-prefix"

export type SourcesMode =
  | "channels"
  | "all"
  | "utm-medium"
  | "utm-source"
  | "utm-campaign"
  | "utm-content"
  | "utm-term"

export type DialogSegment =
  | "channels"
  | "sources"
  | "utm_mediums"
  | "utm_sources"
  | "utm_campaigns"
  | "utm_contents"
  | "utm_terms"
  | "pages"
  | "seo-pages"
  | "entry-pages"
  | "exit-pages"
  | "browsers"
  | "operating-systems"
  | "screen-sizes"
  | "countries"
  | "regions"
  | "cities"
  | "devices"
  | "locations"
  | "behaviors"

const MODE_TO_SEGMENT: Record<SourcesMode, DialogSegment> = {
  channels: "channels",
  all: "sources",
  "utm-medium": "utm_mediums",
  "utm-source": "utm_sources",
  "utm-campaign": "utm_campaigns",
  "utm-content": "utm_contents",
  "utm-term": "utm_terms",
}

// Accepts underscore/hyphen and singular/plural variants
const SEGMENT_NORMALIZE: Record<string, DialogSegment> = {
  channels: "channels",
  sources: "sources",
  // mediums
  "utm-medium": "utm_mediums",
  utm_medium: "utm_mediums",
  "utm-mediums": "utm_mediums",
  utm_mediums: "utm_mediums",
  // sources
  "utm-source": "utm_sources",
  utm_source: "utm_sources",
  "utm-sources": "utm_sources",
  utm_sources: "utm_sources",
  // campaigns
  "utm-campaign": "utm_campaigns",
  utm_campaign: "utm_campaigns",
  "utm-campaigns": "utm_campaigns",
  utm_campaigns: "utm_campaigns",
  // contents
  "utm-content": "utm_contents",
  utm_content: "utm_contents",
  "utm-contents": "utm_contents",
  utm_contents: "utm_contents",
  // terms
  "utm-term": "utm_terms",
  utm_term: "utm_terms",
  "utm-terms": "utm_terms",
  utm_terms: "utm_terms",
  // other panels
  pages: "pages",
  "seo-pages": "seo-pages",
  seo_pages: "seo-pages",
  seo: "seo-pages",
  "entry-pages": "entry-pages",
  entry_pages: "entry-pages",
  entry: "entry-pages",
  "exit-pages": "exit-pages",
  exit_pages: "exit-pages",
  exit: "exit-pages",
  // devices
  browsers: "browsers",
  "operating-systems": "operating-systems",
  operating_systems: "operating-systems",
  "screen-sizes": "screen-sizes",
  screen_sizes: "screen-sizes",
  // locations
  countries: "countries",
  regions: "regions",
  cities: "cities",
  devices: "devices",
  locations: "locations",
  behaviors: "behaviors",
}

export function dialogSegmentForMode(mode: SourcesMode): DialogSegment {
  return MODE_TO_SEGMENT[mode] || "sources"
}

export type ParsedDialog =
  | { type: "segment"; segment: DialogSegment }
  | { type: "referrers"; source: string }
  | { type: "none" }

export function parseDialogFromPath(pathname: string): ParsedDialog {
  // Canonical:
  //   /admin/analytics/_/referrers/:source
  //   /admin/analytics/sites/:site/_/referrers/:source
  // Legacy:
  //   /admin/analytics/reports/_/referrers/:source
  //   /admin/analytics/sites/:site/reports/_/referrers/:source
  const ref = pathname.match(
    /\/admin\/analytics(?:\/sites\/[^/]+)?(?:\/reports)?\/_\/referrers\/(.+)$/
  )
  if (ref && ref[1]) {
    try {
      return { type: "referrers", source: decodeURIComponent(ref[1]) }
    } catch {
      return { type: "referrers", source: ref[1] }
    }
  }
  const m = pathname.match(
    /\/admin\/analytics(?:\/sites\/[^/]+)?(?:\/reports)?\/_\/([a-z0-9_-]+)$/
  )
  if (m && m[1]) {
    const raw = m[1]
    const seg = SEGMENT_NORMALIZE[raw]
    if (seg) return { type: "segment", segment: seg }
  }
  return { type: "none" }
}

export function buildDialogPath(
  segment: DialogSegment,
  qs: string = "",
  pathname?: string
): string {
  const base = `${analyticsReportsPath(pathname)}/_/${segment}`
  return qs ? `${base}?${qs}` : base
}

export function buildReferrersPath(
  source: string,
  qs: string = "",
  pathname?: string
): string {
  const base = `${analyticsReportsPath(pathname)}/_/referrers/${encodeURIComponent(source)}`
  return qs ? `${base}?${qs}` : base
}

export function baseAnalyticsPath(qs: string = "", pathname?: string): string {
  const reportsPath = analyticsReportsPath(pathname)
  return qs ? `${reportsPath}?${qs}` : reportsPath
}

// Map dialog segment back to the Sources panel mode
export function modeForSegment(segment: DialogSegment): SourcesMode | null {
  switch (segment) {
    case "channels":
      return "channels"
    case "sources":
      return "all"
    case "utm_mediums":
      return "utm-medium"
    case "utm_sources":
      return "utm-source"
    case "utm_campaigns":
      return "utm-campaign"
    case "utm_contents":
      return "utm-content"
    case "utm_terms":
      return "utm-term"
    default:
      return null
  }
}

// Pages mapping helpers
export type PagesMode = "pages" | "seo" | "entry" | "exit"

export function pagesSegmentForMode(mode: PagesMode): DialogSegment {
  switch (mode) {
    case "seo":
      return "seo-pages"
    case "entry":
      return "entry-pages"
    case "exit":
      return "exit-pages"
    case "pages":
    default:
      return "pages"
  }
}

export function pagesModeForSegment(segment: DialogSegment): PagesMode | null {
  switch (segment) {
    case "pages":
      return "pages"
    case "seo-pages":
      return "seo"
    case "entry-pages":
      return "entry"
    case "exit-pages":
      return "exit"
    default:
      return null
  }
}

// Devices mapping helpers
export type DevicesMode = "browsers" | "operating-systems" | "screen-sizes"

export function devicesSegmentForMode(mode: DevicesMode): DialogSegment {
  switch (mode) {
    case "operating-systems":
      return "operating-systems"
    case "screen-sizes":
      return "screen-sizes"
    case "browsers":
    default:
      return "browsers"
  }
}

export function devicesModeForSegment(
  segment: DialogSegment
): DevicesMode | null {
  switch (segment) {
    case "browsers":
      return "browsers"
    case "operating-systems":
      return "operating-systems"
    case "screen-sizes":
      return "screen-sizes"
    default:
      return null
  }
}

// Locations mapping helpers
export type LocationsMode = "map" | "countries" | "regions" | "cities"

export function locationsSegmentForMode(mode: LocationsMode): DialogSegment {
  switch (mode) {
    case "regions":
      return "regions"
    case "cities":
      return "cities"
    case "countries":
    case "map":
    default:
      return "countries" // default dialog for locations
  }
}

export function locationsModeForSegment(
  segment: DialogSegment
): Exclude<LocationsMode, "map"> | null {
  switch (segment) {
    case "countries":
      return "countries"
    case "regions":
      return "regions"
    case "cities":
      return "cities"
    default:
      return null
  }
}
