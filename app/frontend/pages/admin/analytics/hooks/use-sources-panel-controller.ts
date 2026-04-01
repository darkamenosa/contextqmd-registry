import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"

import { analyticsApiErrorCode, analyticsApiErrorMessage } from "../api"
import { useAnalyticsHost } from "../host-context"
import { limitListPayloadForCard, pickCardMetrics } from "../lib/card-metrics"
import {
  dialogSegmentForMode,
  parseDialogFromPath,
  type SourcesMode,
} from "../lib/dialog-path"
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
  getSourcesCampaignLabel,
  getSourcesCardTitle,
  getSourcesDialogTitle,
  getSourcesFilterKey,
  getSourcesFirstColumnLabel,
  hasUsableUtmData,
  isSourcesCampaignMode,
  normalizeSourcesMode,
  resolveSourcesViewState,
  shouldShowSourceIcon,
} from "../lib/sources-panel"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type { ListItem, ListPayload } from "../types"
import { useAnalyticsApi } from "./use-analytics-api"
import { usePanelData } from "./use-panel-data"

const STORAGE_PREFIX = "admin.analytics.sources"

type UseSourcesPanelControllerOptions = {
  initialData: ListPayload
  initialMode: string
}

export function useSourcesPanelController({
  initialData,
  initialMode,
}: UseSourcesPanelControllerOptions) {
  const { fetchReferrers, fetchSearchTerms, fetchSources } = useAnalyticsApi()
  const host = useAnalyticsHost()
  const { query, search, updateQuery } = useQueryContext()
  const site = useSiteContext()
  const explicitSearchMode = hasPanelModeSearchParam(search, "sources")
    ? getSourcesModeFromSearch(search, query)
    : null

  const [debugOpen, setDebugOpen] = useState(false)
  const [preferredMode, setPreferredMode] = useState<SourcesMode>(() =>
    normalizeSourcesMode(explicitSearchMode ?? initialMode)
  )
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const parsedDialog = parseDialogFromPath(host.pathname, host.reportsPath)
  const derivedModeFromFilters = inferSourcesModeFromFilters(query.filters)
  const {
    mode,
    activeSource,
    detailsOpen,
    isGoogleActive,
    refDetailsOpen,
    takeover,
  } = resolveSourcesViewState(
    parsedDialog,
    query.filters,
    preferredMode,
    derivedModeFromFilters
  )

  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const closeDialog = host.closeDialogRoute
  const initialRequestKey = JSON.stringify([
    baseQuery,
    normalizeSourcesMode(initialMode),
  ])
  const requestKey = JSON.stringify([baseQuery, mode])
  const panelState = usePanelData({
    initialData,
    initialRequestKey,
    requestKey,
    fetchData: (controller) =>
      fetchSources(baseQuery, { mode }, controller.signal),
  })
  const data = panelState.data
  const loading = panelState.loading

  const [refData, setRefData] = useState<ListPayload | null>(null)
  const [refLoading, setRefLoading] = useState(false)
  const refRequestIdRef = useRef(0)

  useEffect(() => {
    if (takeover !== "referrers" || !activeSource) {
      startTransition(() => {
        setRefData(null)
        setRefLoading(false)
      })
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
  }, [activeSource, baseQuery, takeover])

  const [termsData, setTermsData] = useState<ListPayload | null>(null)
  const [termsLoading, setTermsLoading] = useState(false)
  const [termsError, setTermsError] = useState<string | null>(null)
  const [termsErrorCode, setTermsErrorCode] = useState<string | null>(null)
  const termsRequestIdRef = useRef(0)

  useEffect(() => {
    if (takeover !== "search-terms") {
      startTransition(() => {
        setTermsData(null)
        setTermsError(null)
        setTermsErrorCode(null)
        setTermsLoading(false)
      })
      return
    }

    const controller = new AbortController()
    const requestId = termsRequestIdRef.current + 1
    termsRequestIdRef.current = requestId
    startTransition(() => {
      setTermsLoading(true)
      setTermsError(null)
      setTermsErrorCode(null)
    })

    fetchSearchTerms(baseQuery, {}, controller.signal)
      .then((payload) => {
        if (termsRequestIdRef.current !== requestId) return
        setTermsData(payload)
      })
      .catch((error) => {
        if (error.name === "AbortError") return
        if (termsRequestIdRef.current !== requestId) return
        setTermsData(null)
        setTermsErrorCode(analyticsApiErrorCode(error))
        setTermsError(searchTermsErrorMessage(error))
        console.error(error)
      })
      .finally(() => {
        if (termsRequestIdRef.current !== requestId) return
        setTermsLoading(false)
      })

    return () => controller.abort()
  }, [baseQuery, takeover])

  const highlightMetric = data.metrics.includes("visitors")
    ? "visitors"
    : data.metrics[0]
  const limitedData = useMemo(
    () =>
      limitListPayloadForCard(data, {
        metrics: pickCardMetrics(data.metrics),
      }),
    [data]
  )
  const limitedTermsData = useMemo(() => {
    if (!termsData) return null
    return limitListPayloadForCard(termsData)
  }, [termsData])
  const cardTitle = getSourcesCardTitle(mode, takeover)
  const dialogTitle = getSourcesDialogTitle(mode)
  const campaignActive = isSourcesCampaignMode(mode)
  const campaignLabel = getSourcesCampaignLabel(mode)
  const firstColumnLabel = getSourcesFirstColumnLabel(mode)
  const showSourceIcon = shouldShowSourceIcon(mode)
  const utmHasUsableData = hasUsableUtmData(mode, data)
  const searchTermsStatus = termsData?.meta.searchConsole
  const selectedSearchTermsPage = query.filters.page?.trim() || null
  const sourceDebugSource = mode === "all" ? activeSource || null : null
  const sourcesEndpoint = host.scopedPath("/sources")
  const searchTermsEndpoint = host.scopedPath("/search_terms")
  const referrersEndpoint = host.scopedPath("/referrers")

  const setAndStoreMode = useCallback(
    (value: SourcesMode) => {
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

  const handlePrimaryRowClick = useCallback(
    (item: ListItem) => {
      const name = String(item.name)
      if (mode === "channels") {
        setAndStoreMode("all")
        updateQuery((current) => ({
          ...current,
          filters: { ...current.filters, channel: name },
        }))
        return
      }

      applyFilter(getSourcesFilterKey(mode), name)
    },
    [applyFilter, mode, setAndStoreMode, updateQuery]
  )

  const handleReferrerRowClick = useCallback(
    (item: ListItem) => {
      if (String(item.name) === "Direct / None") return
      applyFilter("referrer", String(item.name))
    },
    [applyFilter]
  )

  const openDetailsDialog = useCallback(() => {
    try {
      if (takeover === "referrers" && activeSource) {
        host.openDialogRoute((routeSearch) =>
          host.buildReferrersPath(activeSource, routeSearch)
        )
        return
      }

      if (takeover === "search-terms") {
        host.openDialogRoute((routeSearch) =>
          host.buildReferrersPath("Google", routeSearch)
        )
        return
      }

      host.openDialogRoute((routeSearch) =>
        host.buildDialogPath(dialogSegmentForMode(mode), routeSearch)
      )
    } catch {
      // Ignore history errors when opening details routes.
    }
  }, [activeSource, host, mode, takeover])

  const syncPrimaryDialog = useCallback(
    (open: boolean) => {
      try {
        if (takeover === "search-terms") {
          host.syncDialogRoute(open, (routeSearch) =>
            host.buildReferrersPath("Google", routeSearch)
          )
          return
        }

        host.syncDialogRoute(open, (routeSearch) =>
          host.buildDialogPath(dialogSegmentForMode(mode), routeSearch)
        )
      } catch {
        // Ignore history errors when syncing the main details dialog.
      }
    },
    [host, mode, takeover]
  )

  const syncReferrerDialog = useCallback(
    (open: boolean) => {
      if (!activeSource) return

      try {
        if (open) {
          host.navigate(
            host.buildReferrersPath(
              String(activeSource),
              host.getDialogSearch()
            )
          )
          return
        }

        host.syncDialogRoute(false, (routeSearch) =>
          host.buildReferrersPath(String(activeSource), routeSearch)
        )
      } catch (error) {
        console.warn("Failed to sync referrer details route", error)
      }
    },
    [activeSource, host]
  )

  const setLast28Days = useCallback(() => {
    updateQuery((current) => ({
      ...current,
      period: "28d",
      comparison: null,
      date: null,
      from: null,
      to: null,
      compareFrom: null,
      compareTo: null,
      matchDayOfWeek: false,
    }))
  }, [updateQuery])

  return {
    activeSource,
    campaignActive,
    campaignLabel,
    cardTitle,
    closeDialog,
    data,
    debugOpen,
    detailsOpen,
    dialogTitle,
    firstColumnLabel,
    handlePrimaryRowClick,
    handleReferrerRowClick,
    highlightMetric,
    isGoogleActive,
    limitedData,
    limitedTermsData,
    loading,
    mode,
    openDetailsDialog,
    refData,
    refDetailsOpen,
    refLoading,
    searchTermsStatus,
    selectedSearchTermsPage,
    setAndStoreMode,
    setDebugOpen,
    setLast28Days,
    searchTermsEndpoint,
    showSourceIcon,
    sourcesEndpoint,
    sourceDebugSource,
    syncPrimaryDialog,
    syncReferrerDialog,
    takeover,
    termsData,
    termsError,
    termsErrorCode,
    termsLoading,
    utmHasUsableData,
    referrersEndpoint,
  }
}

function searchTermsErrorMessage(error: unknown) {
  switch (analyticsApiErrorCode(error)) {
    case "not_configured":
      return "Google Search Console is not configured yet. Enable it in analytics settings to load search terms."
    case "unsupported_filters":
      return "Google search terms support page, country, and device filters only. Remove entry page, exit page, referrer, UTM, browser, OS, custom property, or other non-Google dimensions and try again."
    case "period_too_recent":
      return "Google search terms are not available for very recent periods. Try a date range ending at least three days ago."
    default:
      return analyticsApiErrorMessage(error) ?? "Failed to load search terms."
  }
}
