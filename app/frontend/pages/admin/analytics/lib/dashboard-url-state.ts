const GRAPH_SEARCH_PARAMS = {
  metric: "graph_metric",
  interval: "graph_interval",
} as const

const BEHAVIORS_SEARCH_PARAMS = {
  funnel: "behaviors_funnel",
  property: "behaviors_property",
} as const

const PANEL_MODE_DEFAULTS = {
  sources_mode: "all",
  pages_mode: "pages",
  locations_mode: "map",
  devices_mode: "browsers",
} as const

const GRAPH_DEFAULT_INTERVALS: Record<string, string> = {
  realtime: "minute",
  day: "hour",
  "7d": "day",
  "28d": "day",
  "30d": "day",
  "91d": "day",
  month: "day",
  "6mo": "month",
  "12mo": "month",
  year: "month",
}

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

function hasFilterKey(params: URLSearchParams, key: string) {
  return params.getAll("f").some((token) => {
    const parts = token.split(",")
    return parts[1] === key
  })
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

  const period = params.get("period") ?? "day"
  if (period === "day") {
    params.delete("period")
  }

  if (params.get("with_imported") === "false") {
    params.delete("with_imported")
  }

  const graphMetric = normalizeSearchValue(
    params.get(GRAPH_SEARCH_PARAMS.metric)
  )
  if (graphMetric === "visitors") {
    params.delete(GRAPH_SEARCH_PARAMS.metric)
  }

  const defaultGraphInterval = GRAPH_DEFAULT_INTERVALS[period]
  const graphInterval = normalizeSearchValue(
    params.get(GRAPH_SEARCH_PARAMS.interval)
  )
  if (graphInterval && defaultGraphInterval === graphInterval) {
    params.delete(GRAPH_SEARCH_PARAMS.interval)
  }

  for (const [key, value] of Object.entries(PANEL_MODE_DEFAULTS)) {
    if (
      key === "sources_mode" &&
      value === "all" &&
      hasFilterKey(params, "channel")
    ) {
      continue
    }
    if (params.get(key) === value) {
      params.delete(key)
    }
  }

  const behaviorsMode = normalizeSearchValue(params.get("behaviors_mode"))
  if (behaviorsMode !== "props") {
    params.delete(BEHAVIORS_SEARCH_PARAMS.property)
  }
  if (behaviorsMode !== "funnels") {
    params.delete(BEHAVIORS_SEARCH_PARAMS.funnel)
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

  if (options?.history === "replace") {
    window.history.replaceState({}, "", url)
  } else {
    window.history.pushState({}, "", url)
  }
}

export function getGraphMetricFromSearch(
  search: string,
  legacyMetric?: string
) {
  const params = new URLSearchParams(search)
  return (
    params.get(GRAPH_SEARCH_PARAMS.metric) ??
    params.get("metric") ??
    legacyMetric ??
    null
  )
}

export function getGraphIntervalFromSearch(
  search: string,
  legacyInterval?: string
) {
  const params = new URLSearchParams(search)
  return (
    params.get(GRAPH_SEARCH_PARAMS.interval) ??
    params.get("interval") ??
    legacyInterval ??
    null
  )
}

export function setGraphMetricSearchParam(
  params: URLSearchParams,
  metric: string
) {
  params.set(GRAPH_SEARCH_PARAMS.metric, metric)
  return params
}

export function setGraphIntervalSearchParam(
  params: URLSearchParams,
  interval: string
) {
  params.set(GRAPH_SEARCH_PARAMS.interval, interval)
  return params
}

export function syncGraphMetricInUrl(
  metric: string,
  options?: UpdateSearchOptions
) {
  updateDashboardSearchParams((params) => {
    setGraphMetricSearchParam(params, metric)
  }, options)
}

export function syncGraphIntervalInUrl(
  interval: string,
  options?: UpdateSearchOptions
) {
  updateDashboardSearchParams((params) => {
    setGraphIntervalSearchParam(params, interval)
  }, options)
}

export function syncGraphControlsInUrl(
  graph: { metric: string; interval: string },
  options?: UpdateSearchOptions
) {
  updateDashboardSearchParams((params) => {
    setGraphMetricSearchParam(params, graph.metric)
    setGraphIntervalSearchParam(params, graph.interval)
  }, options)
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
