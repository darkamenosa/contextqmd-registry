import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { Bug, Mail } from "lucide-react"

import { Button } from "@/components/ui/button"

import {
  analyticsApiErrorCode,
  analyticsApiErrorMessage,
  fetchReferrers,
  fetchSearchTerms,
  fetchSources,
} from "../api"
import { usePanelData } from "../hooks/use-panel-data"
import {
  getReportsDialogSearch,
  openReportsDialogRoute,
  syncReportsDialogRoute,
  useCloseReportsDialogRoute,
} from "../hooks/use-reports-dialog-route"
import { pickCardMetrics } from "../lib/card-metrics"
import {
  buildDialogPath,
  buildReferrersPath,
  dialogSegmentForMode,
  modeForSegment,
  parseDialogFromPath,
  type SourcesMode,
} from "../lib/dialog-path"
import { navigateAnalytics } from "../lib/location-store"
import {
  getSourcesModeFromSearch,
  hasPanelModeSearchParam,
  inferSourcesModeFromFilters,
} from "../lib/panel-mode"
import {
  analyticsPreferenceKey,
  writeAnalyticsPreference,
} from "../lib/preferences"
import { useScopedQuery } from "../lib/query-scope"
import {
  getSourceFaviconDomain,
  normalizeSourceKey,
  sourceNeedsLightBackground,
} from "../lib/source-visuals"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type { ListItem, ListMetricKey, ListPayload } from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabDropdown, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"
import SourceDebugDialog from "./source-debug-dialog"

const CAMPAIGN_OPTIONS: Array<{ value: string; label: string }> = [
  { value: "utm-medium", label: "UTM Mediums" },
  { value: "utm-source", label: "UTM Sources" },
  { value: "utm-campaign", label: "UTM Campaigns" },
  { value: "utm-content", label: "UTM Contents" },
  { value: "utm-term", label: "UTM Terms" },
]

const TITLE_FOR_MODE: Record<string, string> = {
  channels: "Top Channels",
  all: "Top Sources",
  "utm-medium": "UTM Mediums",
  "utm-source": "UTM Sources",
  "utm-campaign": "UTM Campaigns",
  "utm-content": "UTM Contents",
  "utm-term": "UTM Terms",
}

const STORAGE_PREFIX = "admin.analytics.sources"

type SourcesPanelProps = {
  initialData: ListPayload
  initialMode: string
}

export default function SourcesPanel({
  initialData,
  initialMode,
}: SourcesPanelProps) {
  const { query, pathname, search, updateQuery } = useQueryContext()
  const site = useSiteContext()
  const explicitSearchMode = hasPanelModeSearchParam(search, "sources")
    ? getSourcesModeFromSearch(search, query)
    : null

  const [debugOpen, setDebugOpen] = useState(false)
  const [preferredMode, setPreferredMode] = useState(
    () => explicitSearchMode ?? initialMode
  )
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const parsedDialog = useMemo(() => parseDialogFromPath(pathname), [pathname])
  const dialogMode = useMemo(() => {
    if (parsedDialog.type === "referrers") return "all"
    if (parsedDialog.type === "segment")
      return modeForSegment(parsedDialog.segment)
    return null
  }, [parsedDialog])
  const derivedModeFromFilters = useMemo(
    () => inferSourcesModeFromFilters(query.filters),
    [query.filters]
  )
  const mode = dialogMode ?? derivedModeFromFilters ?? preferredMode
  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const detailsOpen =
    parsedDialog.type === "segment" ||
    (parsedDialog.type === "referrers" && /^google$/i.test(parsedDialog.source))
  const refDetailsOpen =
    parsedDialog.type === "referrers" && !/^google$/i.test(parsedDialog.source)
  const initialRequestKey = useMemo(
    () => JSON.stringify([baseQuery, initialMode]),
    [baseQuery, initialMode]
  )
  const requestKey = useMemo(
    () => JSON.stringify([baseQuery, mode]),
    [baseQuery, mode]
  )
  const closeDialog = useCloseReportsDialogRoute()
  const panelState = usePanelData({
    initialData,
    initialRequestKey,
    requestKey,
    fetchData: (controller) =>
      fetchSources(baseQuery, { mode }, controller.signal),
  })
  const data = panelState.data
  const loading = panelState.loading

  const setAndStoreMode = useCallback(
    (value: string) => {
      setPreferredMode(value)
      writeAnalyticsPreference(storageKey, value)
    },
    [storageKey]
  )

  const applyFilter = useCallback(
    (key: string, value: string) => {
      updateQuery((current) => ({
        ...current,
        filters: { ...current.filters, [key]: value },
      }))
    },
    [updateQuery]
  )

  // Drilldown for a selected source (when mode === 'all')
  const activeSource =
    parsedDialog.type === "referrers"
      ? parsedDialog.source
      : query.filters?.source
  const isGoogleActive = useMemo(
    () => !!(activeSource && /google/i.test(String(activeSource))),
    [activeSource]
  )
  // Allow takeover even for Direct / None (matches Plausible behavior for referrers card)
  const takeOverWithReferrers = useMemo(
    () => mode === "all" && !!activeSource && !isGoogleActive,
    [mode, activeSource, isGoogleActive]
  )
  const [refData, setRefData] = useState<ListPayload | null>(null)
  const [refLoading, setRefLoading] = useState(false)
  const [termsData, setTermsData] = useState<ListPayload | null>(null)
  const [termsLoading, setTermsLoading] = useState(false)
  const [termsError, setTermsError] = useState<string | null>(null)
  const refRequestIdRef = useRef(0)
  const termsRequestIdRef = useRef(0)

  useEffect(() => {
    if (mode !== "all" || !activeSource) {
      startTransition(() => setRefData(null))
      startTransition(() => setRefLoading(false))
      return
    }
    const controller = new AbortController()
    const requestId = refRequestIdRef.current + 1
    refRequestIdRef.current = requestId
    startTransition(() => setRefLoading(true))
    fetchReferrers(baseQuery, { source: activeSource }, controller.signal)
      .then((payload) => {
        if (refRequestIdRef.current !== requestId) return
        setRefData(payload)
      })
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (refRequestIdRef.current !== requestId) return
        setRefLoading(false)
      })
    return () => controller.abort()
  }, [activeSource, baseQuery, mode])

  // Fetch search terms when Google is active
  useEffect(() => {
    if (mode !== "all" || !isGoogleActive) {
      startTransition(() => setTermsData(null))
      startTransition(() => setTermsError(null))
      startTransition(() => setTermsLoading(false))
      return
    }
    const controller = new AbortController()
    const requestId = termsRequestIdRef.current + 1
    termsRequestIdRef.current = requestId
    startTransition(() => setTermsLoading(true))
    startTransition(() => setTermsError(null))
    fetchSearchTerms(baseQuery, {}, controller.signal)
      .then((payload) => {
        if (termsRequestIdRef.current !== requestId) return
        setTermsData(payload)
        setTermsError(null)
      })
      .catch((error) => {
        if (error.name !== "AbortError") {
          if (termsRequestIdRef.current !== requestId) return
          setTermsData(null)
          setTermsError(searchTermsErrorMessage(error))
          console.error(error)
        }
      })
      .finally(() => {
        if (termsRequestIdRef.current !== requestId) return
        setTermsLoading(false)
      })
    return () => controller.abort()
  }, [baseQuery, isGoogleActive, mode])

  const highlightMetric = useMemo(
    () => (data.metrics.includes("visitors") ? "visitors" : data.metrics[0]),
    [data.metrics]
  )

  // Card title follows Plausible: "Top Channels" on card, but modal uses
  // "Top Acquisition Channels". For other tabs, both are identical.
  const cardTitle = useMemo(() => {
    if (mode === "channels") return "Top Channels"
    if (mode === "all" && isGoogleActive) return "Search Terms"
    if (takeOverWithReferrers) return "Top Referrers"
    return TITLE_FOR_MODE[mode] ?? "Top Sources"
  }, [mode, isGoogleActive, takeOverWithReferrers])

  const dialogTitle = useMemo(() => {
    if (mode === "channels") return "Top Acquisition Channels"
    return TITLE_FOR_MODE[mode] ?? "Top Sources"
  }, [mode])
  const campaignActive = useMemo(
    () => CAMPAIGN_OPTIONS.some((option) => option.value === mode),
    [mode]
  )
  const campaignLabel = useMemo(() => {
    if (!campaignActive) return "Campaigns"
    const activeOption = CAMPAIGN_OPTIONS.find(
      (option) => option.value === mode
    )
    return activeOption?.label ?? "Campaigns"
  }, [campaignActive, mode])

  const firstColumnLabel = useMemo(() => {
    if (mode === "channels") return "Channel"
    if (mode.startsWith("utm-")) {
      const label =
        CAMPAIGN_OPTIONS.find((opt) => opt.value === mode)?.label || "Campaign"
      return label.replace(/s$/, "") // Remove trailing 's' for singular
    }
    return "Source"
  }, [mode])

  // Limit card view to top 9 by the first metric; Details keeps full list
  const limitedData = useMemo((): ListPayload => {
    const metricKey = data.metrics[0] ?? "visitors"
    const sorted = [...data.results].sort((a, b) => {
      const av = Number(a[metricKey] ?? 0)
      const bv = Number(b[metricKey] ?? 0)
      if (av === bv) return String(a.name).localeCompare(String(b.name))
      return bv - av
    })
    const sliced = sorted.slice(0, 9)
    return {
      ...data,
      metrics: pickCardMetrics(data.metrics),
      results: sliced,
      meta: { ...data.meta, hasMore: data.results.length > 9 },
    }
  }, [data])

  // Treat UTM tabs with mostly "(none)" as no usable data, so we don't display a meaningless list
  const isUtmMode = useMemo(() => mode.startsWith("utm-"), [mode])
  const utmHasUsableData = useMemo(() => {
    if (!isUtmMode) return true
    if (!data || !data.results) return false
    const rows = data.results
    const total = rows.reduce((sum, r) => sum + Number(r.visitors ?? 0), 0)
    const nonNone = rows.filter((r) => {
      const name = String(r.name ?? "").trim()
      return (
        name !== "" && name !== "(none)" && name.toLowerCase() !== "(not set)"
      )
    })
    const nonNoneTotal = nonNone.reduce(
      (sum, r) => sum + Number(r.visitors ?? 0),
      0
    )
    if (nonNone.length === 0) return false
    // Hide when non-tagged dominates (>= 90% is (none))
    return nonNoneTotal / Math.max(total, 1) >= 0.1
  }, [isUtmMode, data])

  return (
    <section
      className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4"
      data-testid="sources-panel"
    >
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-medium">{cardTitle}</h2>
        {/* Hide tabs when referrer or search-terms take over, to match Plausible */}
        {takeOverWithReferrers || (mode === "all" && isGoogleActive) ? null : (
          <PanelTabs>
            <PanelTab
              active={mode === "channels"}
              onClick={() => setAndStoreMode("channels")}
            >
              Channels
            </PanelTab>
            <PanelTab
              active={mode === "all"}
              onClick={() => setAndStoreMode("all")}
            >
              Sources
            </PanelTab>
            <PanelTabDropdown
              active={campaignActive}
              label={campaignLabel}
              options={CAMPAIGN_OPTIONS}
              onSelect={setAndStoreMode}
            />
          </PanelTabs>
        )}
      </header>

      {loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : takeOverWithReferrers ? (
        refLoading ? (
          <PanelListSkeleton firstColumnLabel="Referrer" />
        ) : !refData || refData.results.length === 0 ? (
          <PanelEmptyState />
        ) : (
          <>
            <MetricTable
              data={{ ...refData, metrics: ["visitors"] as ListMetricKey[] }}
              firstColumnLabel="Referrer"
              renderLeading={renderSourceIcon}
              displayBars={false}
              barColorTheme="cyan"
              testId="referrers"
              onRowClick={(item) => {
                if (String(item.name) === "Direct / None") return
                applyFilter("referrer", String(item.name))
              }}
            />
            <div className="mt-auto flex justify-center pt-3">
              <DetailsButton
                data-testid="sources-details-btn"
                onClick={() => {
                  try {
                    if (activeSource) {
                      openReportsDialogRoute((search) =>
                        buildReferrersPath(activeSource, search)
                      )
                    }
                  } catch {
                    // Ignore history errors when opening the details route.
                  }
                }}
              >
                Details
              </DetailsButton>
            </div>
          </>
        )
      ) : mode === "all" && isGoogleActive ? (
        termsLoading ? (
          <PanelListSkeleton firstColumnLabel="Search term" />
        ) : termsData && termsData.results.length > 0 ? (
          <>
            <MetricTable
              data={{ ...termsData, metrics: ["visitors"] as ListMetricKey[] }}
              firstColumnLabel="Search term"
              displayBars={false}
              barColorTheme="cyan"
              testId="search-terms"
            />
            <div className="mt-auto flex justify-center pt-3">
              <DetailsButton
                onClick={() => {
                  try {
                    // For Google Search Terms, mirror Plausible route
                    openReportsDialogRoute((search) =>
                      buildReferrersPath("Google", search)
                    )
                  } catch {
                    // Ignore history errors when opening the details route.
                  }
                }}
              >
                Details
              </DetailsButton>
            </div>
          </>
        ) : termsError ? (
          <PanelEmptyState>
            <div className="flex flex-col items-center gap-4 text-center">
              <div className="text-lg font-semibold text-foreground">
                Search Terms
              </div>
              <div className="max-w-prose text-sm text-muted-foreground">
                {termsError}
              </div>
            </div>
          </PanelEmptyState>
        ) : (
          <PanelEmptyState>
            <div className="flex flex-col items-center gap-4 text-center">
              <div className="text-lg font-semibold text-foreground">
                Search Terms
              </div>
              <div className="max-w-prose text-sm text-muted-foreground">
                No search terms found for this period. This feature is in
                development.
              </div>
            </div>
          </PanelEmptyState>
        )
      ) : data.results.length === 0 || (isUtmMode && !utmHasUsableData) ? (
        <PanelEmptyState />
      ) : (
        <>
          <MetricTable
            data={limitedData}
            highlightedMetric={highlightMetric ?? "visitors"}
            onRowClick={(item) => {
              const name = String(item.name)
              if (mode === "channels") {
                // Follow Plausible: clicking a channel switches to Sources tab with channel filter; no dialog.
                setAndStoreMode("all")
                updateQuery((current) => ({
                  ...current,
                  filters: { ...current.filters, channel: name },
                }))
                return
              }
              const filterKey = filterKeyForMode(mode)
              applyFilter(filterKey, name)
            }}
            renderLeading={shouldShowIcon(mode) ? renderSourceIcon : undefined}
            displayBars={false}
            firstColumnLabel={firstColumnLabel}
            barColorTheme="cyan"
            testId="sources"
          />
          {!isUtmMode || utmHasUsableData ? (
            <div className="mt-auto flex justify-center pt-3">
              <div className="flex items-center gap-2">
                {mode === "all" && activeSource ? (
                  <Button
                    variant="outline"
                    size="sm"
                    className="gap-2"
                    onClick={() => setDebugOpen(true)}
                  >
                    <Bug className="size-3.5" />
                    Inspect
                  </Button>
                ) : null}
                <DetailsButton
                  data-testid="sources-details-btn"
                  onClick={() => {
                    // If a specific source is active, open Referrer Details instead of Sources
                    if (mode === "all" && activeSource && !isGoogleActive) {
                      try {
                        if (activeSource) {
                          openReportsDialogRoute((search) =>
                            buildReferrersPath(String(activeSource), search)
                          )
                        }
                      } catch {
                        // Ignore history errors when opening referrer details.
                      }
                    } else {
                      try {
                        const seg = dialogSegmentForMode(mode as SourcesMode)
                        openReportsDialogRoute((search) =>
                          buildDialogPath(seg, search)
                        )
                      } catch {
                        // Ignore history errors when opening source details.
                      }
                    }
                  }}
                >
                  Details
                </DetailsButton>
              </div>
            </div>
          ) : null}
        </>
      )}

      {/* Search Terms takes over the card when Google is the active source; no inline drilldown below */}

      {/* Referrer drilldown card - disabled because main card takes over. */}
      <RemoteDetailsDialog
        open={detailsOpen}
        onOpenChange={(open) => {
          try {
            if (open) {
              if (isGoogleActive) {
                // Keep Google keywords route when Search Terms modal is open
                syncReportsDialogRoute(open, (search) =>
                  buildReferrersPath("Google", search)
                )
              } else {
                const seg = dialogSegmentForMode(mode as SourcesMode)
                syncReportsDialogRoute(open, (search) =>
                  buildDialogPath(seg, search)
                )
              }
            } else {
              syncReportsDialogRoute(open, (search) =>
                buildDialogPath(
                  dialogSegmentForMode(mode as SourcesMode),
                  search
                )
              )
            }
          } catch {
            // Ignore history errors when syncing modal state.
          }
        }}
        title={isGoogleActive ? "Google Search Terms" : dialogTitle}
        endpoint={
          isGoogleActive
            ? "/admin/analytics/search_terms"
            : "/admin/analytics/sources"
        }
        extras={isGoogleActive ? {} : { mode }}
        firstColumnLabel={isGoogleActive ? "Search term" : firstColumnLabel}
        defaultSortKey={isGoogleActive ? undefined : "visitors"}
        onRowClick={(item) => {
          const filterKey = filterKeyForMode(mode)
          applyFilter(filterKey, String(item.name))
          closeDialog()
        }}
        renderLeading={
          isGoogleActive
            ? undefined
            : shouldShowIcon(mode)
              ? renderSourceIcon
              : undefined
        }
        sortable={!isGoogleActive}
      />

      {/* Referrer Details modal */}
      {mode === "all" && activeSource ? (
        <RemoteDetailsDialog
          open={refDetailsOpen}
          onOpenChange={(open) => {
            try {
              const qs = getReportsDialogSearch()
              if (open && activeSource) {
                navigateAnalytics(buildReferrersPath(String(activeSource), qs))
              } else if (!open) {
                syncReportsDialogRoute(open, (search) =>
                  buildReferrersPath(String(activeSource), search)
                )
              }
            } catch (e) {
              console.warn("Failed to push dialog path", e)
            }
          }}
          title={"Referrer Drilldown"}
          endpoint={"/admin/analytics/referrers"}
          extras={{ source: activeSource }}
          firstColumnLabel={"Referrer"}
          defaultSortKey={"visitors"}
          onRowClick={(item) => {
            if (String(item.name) === "Direct / None") return
            applyFilter("referrer", String(item.name))
            closeDialog()
          }}
          renderLeading={renderSourceIcon}
          getExternalLinkUrl={(item) => {
            const name = String(item.name)
            if (!name || name === "Direct / None" || name.startsWith("("))
              return null
            // If it already looks like a URL with scheme, use as is. Else prefix https://
            return /^(https?:)?\/\//i.test(name)
              ? name.startsWith("http")
                ? name
                : `https:${name}`
              : `https://${name}`
          }}
        />
      ) : null}

      <SourceDebugDialog
        open={debugOpen}
        onOpenChange={setDebugOpen}
        source={mode === "all" ? activeSource || null : null}
      />
    </section>
  )
}

function searchTermsErrorMessage(error: unknown) {
  switch (analyticsApiErrorCode(error)) {
    case "not_configured":
      return "Google Search Console is not configured yet. Enable it in analytics settings to load search terms."
    case "unsupported_filters":
      return "Search terms do not support the current filters. Remove source, referrer, UTM, or page filters and try again."
    case "period_too_recent":
      return "Search terms are not available for very recent periods. Try a date range that starts at least three days ago."
    default:
      return analyticsApiErrorMessage(error) ?? "Failed to load search terms."
  }
}

function shouldShowIcon(mode: string) {
  return mode === "all" || mode === "utm-source"
}

function filterKeyForMode(mode: string) {
  switch (mode) {
    case "channels":
      return "channel"
    case "utm-medium":
      return "utm_medium"
    case "utm-source":
      return "utm_source"
    case "utm-campaign":
      return "utm_campaign"
    case "utm-content":
      return "utm_content"
    case "utm-term":
      return "utm_term"
    case "all":
    default:
      return "source"
  }
}

function renderSourceIcon(item: ListItem) {
  const name = String(item.name ?? "").trim()
  return <SourceIcon name={name} />
}

function SourceIcon({ name }: { name: string }) {
  const [error, setError] = useState(false)
  const slug = name.toLowerCase()
  const normalizedName = normalizeSourceKey(name)

  // Traffic category sources (no real domain) - use emojis directly
  const CATEGORY_EMOJIS: Record<string, string> = {
    "Direct / None": "↩️",
    "Organic Search": "🔍",
    "Organic Social": "👥",
    "Paid Search": "💰",
    Email: "✉️",
    Referral: "🔗",
  }

  const renderIconBadge = (icon: ReactNode, className: string) => (
    <span
      className={`flex size-6 items-center justify-center rounded-full ${className}`}
      aria-hidden
    >
      {icon}
    </span>
  )

  const knownLocalIcon = () => {
    if (
      normalizedName === "newsletter" ||
      normalizedName === "email" ||
      normalizedName === "emails"
    ) {
      return renderIconBadge(
        <Mail className="size-3.5" strokeWidth={2.1} />,
        "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300"
      )
    }
    return null
  }

  const fallbackEmoji = (): string | null => {
    if (slug.includes("google")) return "🔍"
    if (slug.includes("perplexity") || slug.includes("chatgpt")) return "🤖"
    if (slug.includes("facebook")) return "📘"
    if (slug.includes("twitter") || slug.includes("x.com")) return "🐦"
    if (slug.includes("github")) return "🐙"
    if (slug.includes("bing")) return "🅱️"
    if (slug.includes("brave")) return "🦁"
    if (slug.includes("duck")) return "🦆"
    if (slug.includes("slack")) return "💬"
    if (slug.includes("product hunt") || slug.includes("producthunt"))
      return "🚀"
    if (slug.includes("teams")) return "👥"
    if (slug.includes("wikipedia")) return "📚"
    if (slug.includes("email")) return "✉️"
    if (slug.includes("direct") || slug.includes("none")) return "↩️"
    if (slug.includes("linkedin")) return "💼"
    if (slug.includes("youtube")) return "📺"
    if (slug.includes("reddit")) return "🤖"
    if (slug.includes("instagram")) return "📷"
    if (slug.includes("search")) return "🔍"
    if (slug.includes("social")) return "👥"
    if (slug.includes("referral") || slug.includes("link")) return "🔗"
    return null
  }

  if (!name) {
    return fallbackBadge("#")
  }

  // Check if this is a traffic category (not a real domain)
  if (CATEGORY_EMOJIS[name]) {
    return (
      <span
        className="flex size-6 items-center justify-center text-lg"
        aria-hidden
      >
        {CATEGORY_EMOJIS[name]}
      </span>
    )
  }

  const localIcon = knownLocalIcon()
  if (localIcon) return localIcon

  // If image failed to load, show emoji or badge
  if (error) {
    if (localIcon) return localIcon
    const emoji = fallbackEmoji()
    if (emoji) {
      return (
        <span
          className="flex size-6 items-center justify-center text-lg"
          aria-hidden
        >
          {emoji}
        </span>
      )
    }
    return fallbackBadge(name)
  }

  const domain = getSourceFaviconDomain(name)
  if (!domain) {
    const emoji = fallbackEmoji()
    return emoji ? (
      <span
        className="flex size-6 items-center justify-center text-lg"
        aria-hidden
      >
        {emoji}
      </span>
    ) : (
      fallbackBadge(name)
    )
  }

  const faviconUrl = `/favicon/sources/${encodeURIComponent(name)}`

  return (
    <span className="flex size-6 items-center justify-center" aria-hidden>
      <img
        src={faviconUrl}
        alt=""
        className={[
          "size-5 shrink-0 object-contain",
          sourceNeedsLightBackground(domain)
            ? "rounded-full border border-white/90 bg-white p-0.5"
            : "",
        ]
          .filter(Boolean)
          .join(" ")}
        onError={() => setError(true)}
        referrerPolicy="no-referrer"
      />
    </span>
  )
}

function fallbackBadge(value: string) {
  const badge = value.slice(0, 1).toUpperCase() || "#"
  const palette = [
    "bg-primary/10 text-primary",
    "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400",
    "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400",
    "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
    "bg-rose-100 text-rose-700 dark:bg-rose-900/30 dark:text-rose-400",
  ]
  const hash = value
    .split("")
    .reduce((acc, char) => acc + char.charCodeAt(0), 0)
  const classes = palette[hash % palette.length]
  return (
    <span
      className={`flex size-6 items-center justify-center rounded-full text-[10px] font-semibold ${classes}`}
      aria-hidden
    >
      {badge}
    </span>
  )
}
