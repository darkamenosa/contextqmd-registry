import { navigateAnalytics } from "./location-store"

const BEHAVIORS_SEARCH_PARAMS = {
  funnel: "behaviors_funnel",
  property: "behaviors_property",
} as const

type HistoryMode = "push" | "replace"

type UpdateSearchOptions = {
  history?: HistoryMode
  pathname?: string
}

function normalizeSearchValue(value: string | null | undefined) {
  if (value == null) return null
  if (value === "undefined" || value === "null" || value === "") return null
  return value
}

function hasFilterValue(params: URLSearchParams, dimension: string) {
  return params
    .getAll("f")
    .some((entry) => entry.split(",", 3)[1] === dimension)
}

export function getGraphMetricFromSearch(
  search: string,
  legacyMetric?: string
) {
  const params = new URLSearchParams(search)
  return (
    normalizeSearchValue(params.get("graph_metric")) ??
    normalizeSearchValue(params.get("metric")) ??
    normalizeSearchValue(legacyMetric) ??
    null
  )
}

export function getGraphIntervalFromSearch(
  search: string,
  legacyInterval?: string
) {
  const params = new URLSearchParams(search)
  return (
    normalizeSearchValue(params.get("graph_interval")) ??
    normalizeSearchValue(params.get("interval")) ??
    normalizeSearchValue(legacyInterval) ??
    null
  )
}

export function canonicalizeDashboardSearchParams(
  input: URLSearchParams | string
) {
  const params =
    typeof input === "string"
      ? new URLSearchParams(input)
      : new URLSearchParams(input.toString())

  params.delete("metric")
  params.delete("interval")
  params.delete("mode")
  params.delete("funnel")
  params.delete("dialog")
  params.delete("graph_interval")

  const period = params.get("period") ?? "day"
  if (period === "day") {
    params.delete("period")
  }

  if (params.get("with_imported") === "false") {
    params.delete("with_imported")
  }

  const behaviorsMode = normalizeSearchValue(params.get("behaviors_mode"))
  if (behaviorsMode !== "props") {
    params.delete(BEHAVIORS_SEARCH_PARAMS.property)
  }
  if (behaviorsMode !== "funnels") {
    params.delete(BEHAVIORS_SEARCH_PARAMS.funnel)
  }

  if (normalizeSearchValue(params.get("pages_mode")) === "pages") {
    params.delete("pages_mode")
  }

  if (normalizeSearchValue(params.get("locations_mode")) === "map") {
    params.delete("locations_mode")
  }

  if (normalizeSearchValue(params.get("devices_mode")) === "browsers") {
    params.delete("devices_mode")
  }

  const sourcesMode = normalizeSearchValue(params.get("sources_mode"))
  if (sourcesMode === "all" && !hasFilterValue(params, "channel")) {
    params.delete("sources_mode")
  }

  if (sourcesMode === "channels" && !hasFilterValue(params, "channel")) {
    params.delete("sources_mode")
  }

  return params
}

export function updateDashboardSearchParams(
  mutator: (params: URLSearchParams) => void,
  options?: UpdateSearchOptions
) {
  if (typeof window === "undefined") return

  const params = new URLSearchParams(window.location.search)
  mutator(params)
  const qs = canonicalizeDashboardSearchParams(params).toString()
  const pathname = options?.pathname ?? window.location.pathname
  const url = qs ? `${pathname}?${qs}` : pathname

  navigateAnalytics(url, { history: options?.history })
}

export function getBehaviorsFunnelFromSearch(
  search: string,
  legacyFunnel?: string
) {
  const params = new URLSearchParams(search)
  return (
    normalizeSearchValue(params.get(BEHAVIORS_SEARCH_PARAMS.funnel)) ??
    normalizeSearchValue(params.get("funnel")) ??
    normalizeSearchValue(legacyFunnel) ??
    null
  )
}

export function getBehaviorsPropertyFromSearch(search: string) {
  const params = new URLSearchParams(search)
  return normalizeSearchValue(params.get(BEHAVIORS_SEARCH_PARAMS.property))
}

export function setBehaviorsFunnelSearchParam(
  params: URLSearchParams,
  funnel?: string | null
) {
  const value = normalizeSearchValue(funnel)
  if (value) {
    params.set(BEHAVIORS_SEARCH_PARAMS.funnel, value)
  } else {
    params.delete(BEHAVIORS_SEARCH_PARAMS.funnel)
  }
  return params
}

export function setBehaviorsPropertySearchParam(
  params: URLSearchParams,
  property?: string | null
) {
  const value = normalizeSearchValue(property)
  if (value) {
    params.set(BEHAVIORS_SEARCH_PARAMS.property, value)
  } else {
    params.delete(BEHAVIORS_SEARCH_PARAMS.property)
  }
  return params
}

export function syncBehaviorsFunnelInUrl(
  funnel?: string | null,
  options?: UpdateSearchOptions
) {
  updateDashboardSearchParams((params) => {
    setBehaviorsFunnelSearchParam(params, funnel)
  }, options)
}

export function syncBehaviorsPropertyInUrl(
  property?: string | null,
  options?: UpdateSearchOptions
) {
  updateDashboardSearchParams((params) => {
    setBehaviorsPropertySearchParam(params, property)
  }, options)
}
