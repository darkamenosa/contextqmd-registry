export type AnalyticsQuery = {
  period:
    | "realtime"
    | "day"
    | "7d"
    | "28d"
    | "30d"
    | "91d"
    | "month"
    | "year"
    | "12mo"
    | "all"
    | "custom"
  comparison?: "previous_period" | "year_over_year" | "custom" | null
  filters: Record<string, string>
  // Optional human-readable labels for some filter keys (country/region/city)
  labels?: Record<string, string>
  // Advanced filters encoded as Plausible-style tuples, serialized into repeated f= entries.
  // Each entry: [operation, dimension, clause]
  // Supported operations client-side: 'is_not', 'contains'.
  advancedFilters?: Array<[string, string, string]>
  withImported: boolean
  metric?: string
  interval?: string
  mode?: string
  funnel?: string
  // Date helpers for month/year/custom periods
  date?: string | null
  from?: string | null
  to?: string | null
  // Compare helpers
  compareFrom?: string | null
  compareTo?: string | null
  matchDayOfWeek?: boolean
  // Optional UI-only hint so dialogs can deep-link and restore open state
  dialog?: string
}

export type SiteContextValue = {
  domain: string
  timezone: string
  hasGoals: boolean
  hasProps: boolean
  funnelsAvailable: boolean
  propsAvailable: boolean
  segments: Array<{ id: string; name: string }>
  flags: { dbip: boolean }
}

export type UserContextValue = {
  role: "super_admin" | "owner" | "admin" | "editor" | "viewer"
  email: string
}

export type TopStat = {
  name: string
  value: number
  graphMetric?: string
  change?: number | null
  comparisonValue?: number | null
}

export type TopStatsPayload = {
  topStats: TopStat[]
  graphableMetrics: string[]
  meta: {
    metricWarnings: Record<string, { code: string; message?: string }>
    importsIncluded: boolean
  }
  interval: string
  includesImported: boolean
  withImportedSwitch: {
    visible: boolean
    togglable: boolean
    tooltipMsg: string | null
  }
  samplePercent: number
  from: string
  to: string
  comparingFrom?: string | null
  comparingTo?: string | null
}

export type MainGraphPayload = {
  metric: string
  plot: number[]
  labels: string[]
  comparisonPlot?: number[] | null
  comparisonLabels?: string[] | null
  presentIndex?: number | null
  interval: string
  fullIntervals?: Record<string, boolean> | null
}

export type ListMetricKey =
  | "visitors"
  | "visits"
  | "percentage"
  | "uniques"
  | "total"
  | "conversionRate"
  | "exitRate"
  | "bounceRate"
  | "visitDuration"
  | "scrollDepth"
  | "timeOnPage"
  | "pageviews"
  // Google Search Console style metrics (used by Search Terms dialog)
  | "impressions"
  | "ctr"
  | "position"

export type ListItem = Record<string, string | number | null | undefined> & {
  name: string
}

export type ListPayload = {
  results: ListItem[]
  metrics: ListMetricKey[]
  meta: {
    hasMore: boolean
    skipImportedReason: string | null
    metricLabels?: Record<string, string>
  }
}

export type MapPayload = {
  map: {
    results: Array<{
      alpha3: string
      alpha2?: string
      numeric?: string
      code?: string
      name: string
      visitors: number
    }>
    meta: Record<string, unknown>
  }
}

export type DevicesPayload = ListPayload

export type BehaviorsPayload =
  | {
      list: ListPayload
      goalHighlighted?: string | null
    }
  | {
      funnels: string[]
      active: {
        name: string
        steps: Array<{
          name: string
          visitors: number
          conversionRate: number
        }>
      }
    }
  | ListPayload

export type AnalyticsPageProps = {
  site: SiteContextValue
  user: UserContextValue
  query: AnalyticsQuery
  defaultQuery: AnalyticsQuery
}
