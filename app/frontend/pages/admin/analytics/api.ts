import {
  DEFAULT_ANALYTICS_REPORTS_PATH,
  resolveAdminAnalyticsScopePath,
} from "./lib/admin-analytics-host"
import {
  buildQueryParams,
  mergeReportQueryParams,
  parseQueryParams,
  resolveInitialReportQuery,
  sanitizeReportQuery,
} from "./lib/query-codec"
import type {
  AnalyticsQuery,
  BehaviorsPayload,
  DevicesPayload,
  ListPayload,
  MainGraphPayload,
  MapPayload,
  ProfileJourneyPayload,
  ProfileSessionPayload,
  ProfileSessionsListPayload,
  ProfilesPayload,
  SourceDebugPayload,
  TopStatsPayload,
} from "./types"

export {
  buildQueryParams,
  mergeReportQueryParams,
  parseQueryParams,
  resolveInitialReportQuery,
  sanitizeReportQuery,
}

type AnalyticsApiErrorBody = Record<string, unknown> | string | null | undefined
type ScopedPathResolver = (suffix: string) => string

function normalizeScopedSuffix(suffix: string) {
  return suffix.startsWith("/") ? suffix : `/${suffix}`
}

function currentAnalyticsPathname() {
  if (typeof window === "undefined") return DEFAULT_ANALYTICS_REPORTS_PATH
  return window.location.pathname
}

const defaultAnalyticsApi = createAnalyticsApi((suffix) => {
  return `${resolveAdminAnalyticsScopePath(currentAnalyticsPathname())}${normalizeScopedSuffix(suffix)}`
})

export class AnalyticsApiError extends Error {
  status: number
  body: AnalyticsApiErrorBody

  constructor(
    message: string,
    options: { status: number; body?: AnalyticsApiErrorBody }
  ) {
    super(message)
    this.name = "AnalyticsApiError"
    this.status = options.status
    this.body = options.body
  }
}

async function parseResponseBody(
  response: Response
): Promise<AnalyticsApiErrorBody> {
  const text = await response.text()
  if (!text) return null

  try {
    return JSON.parse(text) as AnalyticsApiErrorBody
  } catch {
    return text
  }
}

function analyticsErrorBody(error: unknown): Record<string, unknown> | null {
  if (!(error instanceof AnalyticsApiError)) return null
  if (!error.body || typeof error.body !== "object") return null
  return error.body as Record<string, unknown>
}

export function analyticsApiErrorCode(error: unknown): string | null {
  const body = analyticsErrorBody(error)
  const value = body?.errorCode
  return typeof value === "string" ? value : null
}

export function analyticsApiErrorMessage(error: unknown): string | null {
  if (error instanceof AnalyticsApiError) {
    if (typeof error.body === "string" && error.body.trim()) return error.body

    const body = analyticsErrorBody(error)
    const message = body?.message ?? body?.error
    if (typeof message === "string" && message.trim()) return message
  }

  if (error instanceof Error && error.message.trim()) return error.message
  return null
}

async function fetchJson<T>(
  path: string,
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {},
  signal?: AbortSignal
) {
  const qs = buildQueryParams(query, extras)
  const response = await fetch(`${path}?${qs}`, {
    headers: { Accept: "application/json" },
    signal,
  })
  const body = await parseResponseBody(response)
  if (!response.ok) {
    throw new AnalyticsApiError(
      `Request failed with status ${response.status}`,
      {
        status: response.status,
        body,
      }
    )
  }
  return body as T
}

export function createAnalyticsApi(scopedPath: ScopedPathResolver) {
  return {
    fetchTopStats(query: AnalyticsQuery, signal?: AbortSignal) {
      return fetchJson<TopStatsPayload>(
        scopedPath("/top_stats"),
        query,
        {},
        signal
      )
    },

    fetchMainGraph(
      query: AnalyticsQuery,
      extras: { metric?: string; interval?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<MainGraphPayload>(
        scopedPath("/main_graph"),
        query,
        extras,
        signal
      )
    },

    fetchSources(
      query: AnalyticsQuery,
      extras: { mode?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<ListPayload>(
        scopedPath("/sources"),
        query,
        extras,
        signal
      )
    },

    fetchReferrers(
      query: AnalyticsQuery,
      extras: { source: string },
      signal?: AbortSignal
    ) {
      return fetchJson<ListPayload>(
        scopedPath("/referrers"),
        query,
        extras,
        signal
      )
    },

    fetchSourceDebug(
      query: AnalyticsQuery,
      extras: { source: string },
      signal?: AbortSignal
    ) {
      return fetchJson<SourceDebugPayload>(
        scopedPath("/source_debug"),
        query,
        extras,
        signal
      )
    },

    fetchSearchTerms(
      query: AnalyticsQuery,
      extras: Record<string, unknown> = {},
      signal?: AbortSignal
    ) {
      return fetchJson<ListPayload>(
        scopedPath("/search_terms"),
        query,
        extras,
        signal
      )
    },

    fetchPages(
      query: AnalyticsQuery,
      extras: { mode?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<ListPayload>(scopedPath("/pages"), query, extras, signal)
    },

    fetchLocations(
      query: AnalyticsQuery,
      extras: { mode?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<MapPayload | ListPayload>(
        scopedPath("/locations"),
        query,
        extras,
        signal
      )
    },

    fetchDevices(
      query: AnalyticsQuery,
      extras: { mode?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<DevicesPayload>(
        scopedPath("/devices"),
        query,
        extras,
        signal
      )
    },

    fetchBehaviors(
      query: AnalyticsQuery,
      extras: { mode?: string; funnel?: string; property?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<BehaviorsPayload>(
        scopedPath("/behaviors"),
        query,
        extras,
        signal
      )
    },

    fetchProfiles(
      query: AnalyticsQuery,
      extras: { limit?: number; page?: number; search?: string } = {},
      signal?: AbortSignal
    ) {
      return fetchJson<ProfilesPayload>(
        scopedPath("/profiles"),
        query,
        extras,
        signal
      )
    },

    fetchProfileJourney(
      profileId: string,
      query: AnalyticsQuery,
      signal?: AbortSignal
    ) {
      return fetchJson<ProfileJourneyPayload>(
        scopedPath(`/profiles/${encodeURIComponent(profileId)}`),
        query,
        {},
        signal
      )
    },

    async fetchProfileSessions(
      profileId: string,
      extras: { limit?: number; page?: number; date?: string } = {},
      signal?: AbortSignal
    ) {
      const params = new URLSearchParams()
      if (extras.limit) params.set("limit", String(extras.limit))
      if (extras.page) params.set("page", String(extras.page))
      if (extras.date) params.set("date", extras.date)
      const url = `${scopedPath(`/profiles/${encodeURIComponent(profileId)}/sessions`)}?${params}`
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal,
      })
      if (!response.ok) throw new Error(`Request failed: ${response.status}`)
      return (await response.json()) as ProfileSessionsListPayload
    },

    fetchProfileSession(
      profileId: string,
      visitId: number,
      query: AnalyticsQuery,
      signal?: AbortSignal
    ) {
      return fetchJson<ProfileSessionPayload>(
        scopedPath(
          `/profiles/${encodeURIComponent(profileId)}/sessions/${visitId}`
        ),
        query,
        {},
        signal
      )
    },

    async fetchBehaviorPropertyKeys(
      query: AnalyticsQuery,
      signal?: AbortSignal
    ) {
      const payload = await fetchJson<BehaviorsPayload>(
        scopedPath("/behaviors"),
        query,
        {
          mode: "props",
          limit: "1",
          page: "1",
        },
        signal
      )

      return "list" in payload && Array.isArray(payload.propertyKeys)
        ? payload.propertyKeys
        : []
    },

    async fetchBehaviorPropertyValues(
      query: AnalyticsQuery,
      property: string,
      search = "",
      signal?: AbortSignal
    ) {
      const payload = await fetchJson<BehaviorsPayload>(
        scopedPath("/behaviors"),
        query,
        {
          mode: "props",
          property,
          limit: "20",
          page: "1",
          search,
        },
        signal
      )

      if (!("list" in payload)) return []

      return payload.list.results.map((item) => ({
        label: String(item.name),
        value: String(item.name),
      }))
    },
  }
}

export const fetchTopStats = defaultAnalyticsApi.fetchTopStats
export const fetchMainGraph = defaultAnalyticsApi.fetchMainGraph
export const fetchSources = defaultAnalyticsApi.fetchSources
export const fetchReferrers = defaultAnalyticsApi.fetchReferrers
export const fetchSourceDebug = defaultAnalyticsApi.fetchSourceDebug
export const fetchSearchTerms = defaultAnalyticsApi.fetchSearchTerms
export const fetchPages = defaultAnalyticsApi.fetchPages
export const fetchLocations = defaultAnalyticsApi.fetchLocations
export const fetchDevices = defaultAnalyticsApi.fetchDevices
export const fetchBehaviors = defaultAnalyticsApi.fetchBehaviors
export const fetchProfiles = defaultAnalyticsApi.fetchProfiles
export const fetchProfileJourney = defaultAnalyticsApi.fetchProfileJourney
export const fetchProfileSessions = defaultAnalyticsApi.fetchProfileSessions
export const fetchProfileSession = defaultAnalyticsApi.fetchProfileSession
export const fetchBehaviorPropertyKeys =
  defaultAnalyticsApi.fetchBehaviorPropertyKeys
export const fetchBehaviorPropertyValues =
  defaultAnalyticsApi.fetchBehaviorPropertyValues

// Generic paginated list fetcher for Details modals
export async function fetchListPage(
  path: string,
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {},
  opts: {
    limit?: number
    page?: number
    search?: string
    orderBy?: unknown[][]
  } = {},
  signal?: AbortSignal
) {
  const params: Record<string, unknown> = { ...extras }
  if (typeof opts.limit === "number") params.limit = String(opts.limit)
  if (typeof opts.page === "number") params.page = String(opts.page)
  if (typeof opts.search === "string") params.search = opts.search
  // Send order_by as JSON string following Plausible's pattern: [["metric", "direction"]]
  if (opts.orderBy && Array.isArray(opts.orderBy)) {
    params.order_by = JSON.stringify(opts.orderBy)
  }
  return fetchJson<ListPayload>(path, query, params, signal)
}
