import type { AnalyticsQuery } from "../types"
import { updateDashboardSearchParams } from "./dashboard-url-state"

export const PANEL_MODE_SEARCH_PARAMS = {
  sources: "sources_mode",
  pages: "pages_mode",
  locations: "locations_mode",
  devices: "devices_mode",
  behaviors: "behaviors_mode",
} as const

export type PanelModeSearchKey = keyof typeof PANEL_MODE_SEARCH_PARAMS

export const SOURCES_MODES = [
  "channels",
  "all",
  "utm-medium",
  "utm-source",
  "utm-campaign",
  "utm-content",
  "utm-term",
] as const

export const PAGES_MODES = ["pages", "entry", "exit"] as const

export const LOCATIONS_MODES = [
  "map",
  "countries",
  "regions",
  "cities",
] as const

export const DEVICES_MODES = [
  "browsers",
  "browser-versions",
  "operating-systems",
  "operating-system-versions",
  "screen-sizes",
] as const

export const BEHAVIORS_MODES = [
  "conversions",
  "props",
  "funnels",
  "visitors",
] as const

function isAllowedMode<T extends string>(
  mode: string | undefined,
  allowed: readonly T[]
): mode is T {
  return Boolean(mode && allowed.includes(mode as T))
}

function getModeFromSearch<T extends string>(
  search: string,
  panel: PanelModeSearchKey,
  allowed: readonly T[]
) {
  const params = new URLSearchParams(search)
  const mode = params.get(PANEL_MODE_SEARCH_PARAMS[panel]) ?? params.get("mode")
  return isAllowedMode(mode || undefined, allowed) ? mode : null
}

export function hasPanelModeSearchParam(
  search: string,
  panel: PanelModeSearchKey
) {
  const params = new URLSearchParams(search)
  return params.has(PANEL_MODE_SEARCH_PARAMS[panel]) || params.has("mode")
}

export function getPagesMode(mode: string | undefined) {
  return isAllowedMode(mode, PAGES_MODES) ? mode : null
}

export function getPagesModeFromSearch(search: string, legacyMode?: string) {
  return (
    getModeFromSearch(search, "pages", PAGES_MODES) ?? getPagesMode(legacyMode)
  )
}

export function getLocationsMode(mode: string | undefined) {
  return isAllowedMode(mode, LOCATIONS_MODES) ? mode : null
}

export function getLocationsModeFromSearch(
  search: string,
  legacyMode?: string
) {
  return (
    getModeFromSearch(search, "locations", LOCATIONS_MODES) ??
    getLocationsMode(legacyMode)
  )
}

export function getDevicesMode(mode: string | undefined) {
  return isAllowedMode(mode, DEVICES_MODES) ? mode : null
}

export function getDevicesModeFromSearch(search: string, legacyMode?: string) {
  return (
    getModeFromSearch(search, "devices", DEVICES_MODES) ??
    getDevicesMode(legacyMode)
  )
}

export function getBehaviorsMode(
  mode: string | undefined,
  profilesAvailable = true,
  propsAvailable = true,
  funnelsAvailable = true
) {
  const available = BEHAVIORS_MODES.filter(
    (value) => profilesAvailable || value !== "visitors"
  )
    .filter((value) => propsAvailable || value !== "props")
    .filter((value) => funnelsAvailable || value !== "funnels")
  return isAllowedMode(mode, available) ? mode : null
}

export function getBehaviorsModeFromSearch(
  search: string,
  legacyMode: string | undefined,
  profilesAvailable = true,
  propsAvailable = true,
  funnelsAvailable = true
) {
  const available = BEHAVIORS_MODES.filter(
    (value) => profilesAvailable || value !== "visitors"
  )
    .filter((value) => propsAvailable || value !== "props")
    .filter((value) => funnelsAvailable || value !== "funnels")
  return (
    getModeFromSearch(search, "behaviors", available) ??
    getBehaviorsMode(
      legacyMode,
      profilesAvailable,
      propsAvailable,
      funnelsAvailable
    )
  )
}

export function inferSourcesModeFromFilters(
  filters: AnalyticsQuery["filters"]
) {
  const activeFilters = filters || {}
  if (activeFilters.utm_medium) return "utm-medium"
  if (activeFilters.utm_source) return "utm-source"
  if (activeFilters.utm_campaign) return "utm-campaign"
  if (activeFilters.utm_content) return "utm-content"
  if (activeFilters.utm_term) return "utm-term"
  return null
}

export function inferDevicesModeFromFilters(
  baseMode: string,
  filters: AnalyticsQuery["filters"]
) {
  const activeFilters = filters || {}
  if (
    baseMode === "browsers" &&
    (activeFilters.browser || activeFilters.browser_version)
  ) {
    return "browser-versions"
  }
  if (
    baseMode === "operating-systems" &&
    (activeFilters.os || activeFilters.os_version)
  ) {
    return "operating-system-versions"
  }
  return baseMode
}

export function getLocationsModeAfterFilterChange(
  currentMode: string,
  previousFilters: AnalyticsQuery["filters"],
  nextFilters: AnalyticsQuery["filters"],
  countriesRestoreMode: string | null
) {
  const before = previousFilters || {}
  const after = nextFilters || {}

  if (currentMode === "cities" && before.region && !after.region) {
    return "regions"
  }

  if (currentMode === "regions" && before.country && !after.country) {
    return countriesRestoreMode || "countries"
  }

  return null
}

export function getSourcesModeFromQuery(
  query: Pick<AnalyticsQuery, "mode" | "filters">
) {
  if (isAllowedMode(query.mode, SOURCES_MODES)) return query.mode
  return inferSourcesModeFromFilters(query.filters)
}

export function getSourcesModeFromSearch(
  search: string,
  query: Pick<AnalyticsQuery, "mode" | "filters">
) {
  return (
    getModeFromSearch(search, "sources", SOURCES_MODES) ??
    getSourcesModeFromQuery(query)
  )
}

export function getSourcesMode(
  query: Pick<AnalyticsQuery, "mode" | "filters">
) {
  const queryMode = getSourcesModeFromQuery(query)
  if (queryMode) return queryMode
  return "all"
}

export function setPanelModeSearchParam(
  params: URLSearchParams,
  panel: PanelModeSearchKey,
  mode: string
) {
  params.set(PANEL_MODE_SEARCH_PARAMS[panel], mode)
  return params
}

export function copyPanelModeSearchParams(
  source: URLSearchParams,
  target: URLSearchParams
) {
  for (const param of Object.values(PANEL_MODE_SEARCH_PARAMS)) {
    const value = source.get(param)
    if (value) {
      target.set(param, value)
    } else {
      target.delete(param)
    }
  }
  return target
}

export function syncPanelModeInUrl(
  panel: PanelModeSearchKey,
  mode: string,
  options?: {
    history?: "push" | "replace"
    pathname?: string
  }
) {
  updateDashboardSearchParams((params) => {
    setPanelModeSearchParam(params, panel, mode)
  }, options)
}

export function readStoredMode<T extends string>(
  storageKey: string,
  allowed: readonly T[]
) {
  if (typeof window === "undefined") return null
  const stored = localStorage.getItem(storageKey)
  return isAllowedMode(stored || undefined, allowed) ? stored : null
}
