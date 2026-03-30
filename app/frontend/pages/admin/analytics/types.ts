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
  id?: string | null
  name?: string | null
  domain: string
  timezone: string
  paths: {
    reports?: string
    live?: string
    settings?: string
  }
  hasGoals: boolean
  hasProps: boolean
  funnelsAvailable: boolean
  propsAvailable: boolean
  profilesAvailable: boolean
  segments: Array<{ id: string; name: string }>
  flags: { dbip: boolean }
}

export type GoalDefinition = {
  displayName: string
  eventName?: string | null
  pagePath?: string | null
  scrollThreshold?: number | null
  customProps?: Record<string, string>
}

export type GoalSuggestion = {
  name: string
  recentVisits: number
}

export type GoogleSearchConsoleProperty = {
  identifier: string
  type: string
  permissionLevel: string
  label: string
}

export type GoogleSearchConsoleSettings = {
  available: boolean
  connected: boolean
  configured: boolean
  callbackPath?: string | null
  callbackUrl?: string | null
  accountEmail?: string | null
  propertyIdentifier?: string | null
  propertyType?: string | null
  permissionLevel?: string | null
  connectedAt?: string | null
  lastVerifiedAt?: string | null
  syncStatus?: string | null
  syncError?: string | null
  syncInProgress?: boolean
  syncStale?: boolean
  lastSyncedAt?: string | null
  syncedFrom?: string | null
  syncedTo?: string | null
  refreshWindowFrom?: string | null
  refreshWindowTo?: string | null
  propertiesError?: string | null
  properties: GoogleSearchConsoleProperty[]
}

export type AnalyticsTrackerSnippet = {
  scriptUrl: string
  websiteId: string
  domainHint: string
  snippetHtml: string
}

export type AnalyticsTrackingRules = {
  includePaths: string[]
  excludePaths: string[]
  effectiveIncludePaths: string[]
  effectiveExcludePaths: string[]
}

export type FunnelPageSuggestion = {
  label: string
  value: string
  match: FunnelPageMatch
}

export type FunnelStepType = "page_visit" | "goal"
export type FunnelPageMatch =
  | "equals"
  | "contains"
  | "starts_with"
  | "ends_with"
export type FunnelGoalMatch = "completes"

export type FunnelStepDefinition = {
  name?: string | null
  type?: FunnelStepType | "page" | "event" | null
  match?: FunnelPageMatch | FunnelGoalMatch | "contains" | "equals" | null
  value?: string | null
  goalKey?: string | null
  goal_key?: string | null
  label?: string | null
}

export type AnalyticsSettingsPayload = {
  gscConfigured: boolean
  goals: string[]
  goalDefinitions: GoalDefinition[]
  goalSuggestions: GoalSuggestion[]
  allowedEventProps: string[]
  funnelPageSuggestions: FunnelPageSuggestion[]
  trackingRules: AnalyticsTrackingRules
  tracker?: AnalyticsTrackerSnippet | null
  googleSearchConsole: GoogleSearchConsoleSettings
}

export type AnalyticsSettingsPaths = {
  reports?: string
  live?: string
  settings?: string
  settingsData?: string
  googleSearchConsoleConnect?: string
  googleSearchConsole?: string
  googleSearchConsoleSync?: string
}

export type AnalyticsSettingsSiteOption = {
  id: string
  name: string
  domain?: string | null
  settingsPath: string
}

export type AnalyticsInitializationState = {
  mode: string
  initialized: boolean
  singleSite: boolean
  canBootstrap: boolean
  bootstrapPath: string
  suggestedHost?: string | null
  suggestedName?: string | null
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
  | "clicks"
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
  filterValue?: string
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
    searchConsole?: {
      connected: boolean
      configured: boolean
      unsupportedFilters?: boolean
      syncStatus?: string | null
      syncError?: string | null
      syncInProgress?: boolean
      syncStale?: boolean
      lastSyncedAt?: string | null
      syncedFrom?: string | null
      syncedTo?: string | null
      refreshWindowFrom?: string | null
      refreshWindowTo?: string | null
    }
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

export type ProfileListItem = {
  id: string
  publicId: string
  name: string
  status: string
  identified: boolean
  email?: string | null
  firstSeenAt?: string | null
  country?: string | null
  countryCode?: string | null
  city?: string | null
  region?: string | null
  deviceType?: string | null
  os?: string | null
  browser?: string | null
  source?: string | null
  currentPage?: string | null
  lastSeenAt?: string | null
  recentActivity?: number[]
  totalVisits: number
  scopedVisits: number
  totalSessions?: number
  totalPageviews?: number
  totalEvents?: number
  latestContext?: Record<string, unknown>
  devicesUsed?: Array<{
    label: string
    count: number
    lastSeenAt?: string | null
  }>
  browsersUsed?: Array<{
    label: string
    count: number
    lastSeenAt?: string | null
  }>
  osesUsed?: Array<{ label: string; count: number; lastSeenAt?: string | null }>
  sourcesUsed?: Array<{
    label: string
    count: number
    lastSeenAt?: string | null
  }>
  locationsUsed?: Array<{
    label: string
    count: number
    country?: string | null
    countryCode?: string | null
    region?: string | null
    city?: string | null
    lastSeenAt?: string | null
  }>
  topPages?: Array<{ label: string; count: number }>
}

export type ProfilesPayload = {
  kind: "profiles"
  results: ProfileListItem[]
  meta: {
    hasMore: boolean
  }
}

export type ProfileSessionItem = {
  id: number
  visitId: number
  startedAt?: string | null
  lastEventAt?: string | null
  country?: string | null
  countryCode?: string | null
  region?: string | null
  city?: string | null
  deviceType?: string | null
  os?: string | null
  browser?: string | null
  source?: string | null
  entryPage?: string | null
  exitPage?: string | null
  currentPage?: string | null
  durationSeconds: number
  engagedMsTotal: number
  pageviewsCount: number
  eventsCount: number
  pagePaths?: string[]
  eventNames?: string[]
}

export type ProfileJourneyPayload = {
  profile: ProfileListItem
  summary: {
    sessions: number
    pageviews: number
    events: number
  }
  activity: Array<{
    startedAt?: string | null
    count: number
  }>
}

export type ProfileSessionsListPayload = {
  sessions: ProfileSessionItem[]
  hasMore: boolean
}

export type ProfileSessionPayload = {
  session: ProfileSessionItem
  sourceSummary?: {
    sourceLabel: string
    sourceKind?: string | null
    sourceChannel?: string | null
    faviconDomain?: string | null
    referringDomain?: string | null
    referrer?: string | null
    landingPage?: string | null
    utmSource?: string | null
    utmMedium?: string | null
    utmCampaign?: string | null
    trackerParams?: Array<{ key: string; value: string }>
    searchTerms?: Array<{ label: string; probability: number }>
  }
  events: Array<{
    id: number
    visitId?: number
    eventName: string
    label: string
    occurredAt: string
    page?: string | null
    properties?: Record<string, unknown>
  }>
}

export type BottomPanelPayload = BehaviorsPayload | ProfilesPayload

export type AnalyticsDashboardBoot = {
  topStats: TopStatsPayload
  mainGraph: MainGraphPayload
  sources: ListPayload
  pages: ListPayload
  locations: MapPayload | ListPayload
  devices: DevicesPayload
  behaviors: BottomPanelPayload | null
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
  query: AnalyticsQuery
  defaultQuery: AnalyticsQuery
  boot: AnalyticsDashboardBoot
}

export type AnalyticsSettingsPageProps = {
  site: SiteContextValue | null
  sites: AnalyticsSettingsSiteOption[]
  initialization: AnalyticsInitializationState
  user: {
    role: string
    email?: string | null
  }
  funnels: Array<{
    name: string
    steps: FunnelStepDefinition[]
  }>
  settings: AnalyticsSettingsPayload
  paths: AnalyticsSettingsPaths
}
