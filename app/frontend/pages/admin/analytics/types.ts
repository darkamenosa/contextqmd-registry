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
  | "events"
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

export type CountBreakdownRow = {
  value: string
  count: number
}

export type SourceRowSourceInfo = {
  filterValue: string
  normalizedName: string
  topReferringDomain?: string | null
  topUtmSource?: string | null
  topRuleId?: string | null
  topMatchStrategy?: string | null
  rawReferringDomains?: CountBreakdownRow[]
  rawUtmSources?: CountBreakdownRow[]
  matchedRules?: CountBreakdownRow[]
  matchStrategies?: CountBreakdownRow[]
}

export type SourceDebugPayload = {
  source: {
    requestedValue: string
    normalizedValue: string
    kind: string
    faviconDomain: string | null
    visitors: number
    visits: number
    fallbackCount: number
  }
  channels: CountBreakdownRow[]
  matchedRules: CountBreakdownRow[]
  matchStrategies: CountBreakdownRow[]
  rawReferringDomains: CountBreakdownRow[]
  rawUtmSources: CountBreakdownRow[]
  rawReferrers: CountBreakdownRow[]
  latestSamples: Array<{
    startedAt: string | null
    referringDomain: string | null
    utmSource: string | null
    utmMedium: string | null
    referrer: string | null
    ruleId: string | null
    matchStrategy: string | null
  }>
}

export type ListItem = Record<string, unknown> & {
  name: string
  comparison?: Record<string, unknown>
  sourceInfo?: SourceRowSourceInfo
}

export type ListPayload = {
  results: ListItem[]
  metrics: ListMetricKey[]
  meta: {
    hasMore: boolean
    skipImportedReason: string | null
    metricLabels?: Record<string, string>
    dateRangeLabel?: string
    comparisonDateRangeLabel?: string
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
      propertyKeys?: string[]
      activeProperty?: string | null
    }
  | {
      funnels: string[]
      active: {
        name: string
        conversionRate: number
        enteringVisitors: number
        enteringVisitorsPercentage: number
        neverEnteringVisitors: number
        neverEnteringVisitorsPercentage: number
        steps: Array<{
          name: string
          visitors: number
          conversionRate: number
          conversionRateStep: number
          dropoff: number
          dropoffPercentage: number
        }>
      }
    }
  | ListPayload

export type AnalyticsDashboardBoot = {
  topStats: TopStatsPayload
  mainGraph: MainGraphPayload
  sources: ListPayload
  pages: ListPayload
  locations: MapPayload | ListPayload
  devices: DevicesPayload
  behaviors: BehaviorsPayload | null
  ui: {
    graphMetric: string
    graphInterval: string
    sourcesMode: string
    pagesMode: string
    locationsMode: string
    devicesBaseMode: string
    devicesMode: string
    behaviorsMode?: string | null
    behaviorsFunnel?: string | null
    behaviorsProperty?: string | null
  }
}

export type AnalyticsPageProps = {
  site: SiteContextValue
  user: UserContextValue
  query: AnalyticsQuery
  defaultQuery: AnalyticsQuery
  boot: AnalyticsDashboardBoot
}
