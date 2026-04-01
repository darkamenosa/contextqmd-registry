import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"

import { fetchBehaviors, fetchProfiles } from "../api"
import { buildBehaviorsRouteSearch } from "../lib/behaviors-route-search"
import {
  getBehaviorsFunnelFromSearch,
  getBehaviorsPropertyFromSearch,
  setBehaviorsPropertySearchParam,
} from "../lib/dashboard-url-state"
import {
  baseAnalyticsPath,
  buildDialogPath,
  parseDialogFromPath,
} from "../lib/dialog-path"
import { navigateAnalytics } from "../lib/location-store"
import {
  getBehaviorsModeFromSearch,
  setPanelModeSearchParam,
} from "../lib/panel-mode"
import {
  analyticsPreferenceKey,
  writeAnalyticsPreference,
} from "../lib/preferences"
import { mergeReportQueryParams } from "../lib/query-codec"
import { useScopedQuery } from "../lib/query-scope"
import { buildReportUrl } from "../lib/report-url"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type {
  BottomPanelPayload,
  ListItem,
  ListPayload,
  ProfileListItem,
  ProfilesPayload,
} from "../types"

const BEHAVIOR_TABS: Array<{ value: string; label: string }> = [
  { value: "visitors", label: "Visitors" },
  { value: "conversions", label: "Goals" },
  { value: "props", label: "Properties" },
  { value: "funnels", label: "Funnels" },
]

const STORAGE_PREFIX = "admin.analytics.behaviors"

const EMPTY_PROFILES_PAYLOAD: ProfilesPayload = {
  kind: "profiles",
  results: [],
  meta: { hasMore: false },
}

const EMPTY_LIST_PAYLOAD: ListPayload = {
  results: [],
  metrics: ["visitors"],
  meta: {
    hasMore: false,
    skipImportedReason: null,
  },
}

type UseBehaviorsPanelControllerOptions = {
  initialData: BottomPanelPayload
  initialMode?: string | null
  initialFunnel?: string | null
  initialProperty?: string | null
}

export type BehaviorsPanelController = ReturnType<
  typeof useBehaviorsPanelController
>

export function useBehaviorsPanelController({
  initialData,
  initialMode,
  initialFunnel,
  initialProperty,
}: UseBehaviorsPanelControllerOptions) {
  const { query, pathname, search, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const behaviourTabs = useMemo(
    () =>
      BEHAVIOR_TABS.filter((tab) => {
        if (tab.value === "visitors" && !site.profilesAvailable) return false
        if (tab.value === "props" && !site.propsAvailable) return false
        if (tab.value === "funnels" && !site.funnelsAvailable) return false
        return true
      }),
    [site.funnelsAvailable, site.profilesAvailable, site.propsAvailable]
  )

  const defaultMode = behaviourTabs[0]?.value ?? "visitors"
  const queryMode = getBehaviorsModeFromSearch(
    search,
    query.mode,
    site.profilesAvailable,
    site.propsAvailable,
    site.funnelsAvailable
  )

  const [preferredMode, setPreferredMode] = useState<string | null>(null)
  const [modeState, setModeState] = useState(
    initialMode ?? queryMode ?? defaultMode
  )
  const [data, setData] = useState<BottomPanelPayload>(
    isProfilesPayload(initialData) ? EMPTY_LIST_PAYLOAD : initialData
  )
  const [profilesData, setProfilesData] = useState<ProfilesPayload>(
    isProfilesPayload(initialData) ? initialData : EMPTY_PROFILES_PAYLOAD
  )
  const [loading, setLoading] = useState(false)
  const [profilesSearch, setProfilesSearch] = useState("")
  const [profilesPage, setProfilesPage] = useState(1)
  const [profilesLoadingMore, setProfilesLoadingMore] = useState(false)
  const [selectedProfile, setSelectedProfile] =
    useState<ProfileListItem | null>(null)
  const [journeyOpen, setJourneyOpen] = useState(false)
  const dataRequestIdRef = useRef(0)
  const profilesRequestIdRef = useRef(0)

  const selectedFunnelFromSearch = getBehaviorsFunnelFromSearch(
    search,
    query.funnel
  )
  const selectedPropertyFromSearch = getBehaviorsPropertyFromSearch(search)

  const [selectedFunnelState, setSelectedFunnelState] = useState(
    initialFunnel ?? selectedFunnelFromSearch
  )
  const [selectedPropertyState, setSelectedPropertyState] = useState(
    initialProperty ?? selectedPropertyFromSearch
  )

  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const detailsOpen = useMemo(() => {
    const parsed = parseDialogFromPath(pathname)
    return parsed.type === "segment" && parsed.segment === "behaviors"
  }, [pathname])

  const localMode = behaviourTabs.some((tab) => tab.value === modeState)
    ? modeState
    : (preferredMode ?? defaultMode)
  const mode = detailsOpen && queryMode ? queryMode : localMode

  const availableFunnels = useMemo(
    () =>
      data && !isProfilesPayload(data) && "funnels" in data ? data.funnels : [],
    [data]
  )
  const routeSelectedFunnel = detailsOpen ? selectedFunnelFromSearch : null
  const routeSelectedProperty = detailsOpen ? selectedPropertyFromSearch : null
  const selectedFunnel =
    routeSelectedFunnel ??
    selectedFunnelState ??
    (data && !isProfilesPayload(data) && "funnels" in data
      ? (data.active?.name ?? data.funnels[0])
      : undefined)
  const requestedFunnel =
    routeSelectedFunnel ?? selectedFunnelState ?? undefined

  const listPayload: ListPayload | null = useMemo(() => {
    if (!data || isProfilesPayload(data)) {
      return null
    }
    if ("list" in data) {
      return data.list
    }
    if (!("funnels" in data) && "results" in data) {
      return data as ListPayload
    }
    return null
  }, [data])

  const propertyOptions = useMemo(() => {
    if (mode !== "props" || !("list" in data)) {
      return []
    }
    return Array.isArray(data.propertyKeys) ? data.propertyKeys : []
  }, [data, mode])

  const activeProperty = useMemo(() => {
    if (mode !== "props") return null
    if (propertyOptions.length === 0) return null
    return routeSelectedProperty &&
      propertyOptions.includes(routeSelectedProperty)
      ? routeSelectedProperty
      : selectedPropertyState && propertyOptions.includes(selectedPropertyState)
        ? selectedPropertyState
        : "list" in data &&
            data.activeProperty &&
            propertyOptions.includes(data.activeProperty)
          ? data.activeProperty
          : propertyOptions[0]
  }, [
    data,
    mode,
    propertyOptions,
    routeSelectedProperty,
    selectedPropertyState,
  ])

  const initialRequestMode = initialMode ?? queryMode ?? defaultMode
  const initialRequestFunnel =
    initialFunnel ??
    selectedFunnelFromSearch ??
    (!isProfilesPayload(initialData) && "funnels" in initialData
      ? (initialData.active?.name ?? initialData.funnels[0])
      : undefined)
  const initialRequestProperty =
    initialProperty ??
    selectedPropertyState ??
    (!isProfilesPayload(initialData) && "list" in initialData
      ? (initialData.activeProperty ?? null)
      : null)
  const initialRequestKey = useMemo(
    () =>
      JSON.stringify([
        baseQuery,
        initialRequestMode,
        initialRequestMode === "funnels"
          ? (initialRequestFunnel ?? null)
          : initialRequestMode === "props"
            ? (initialRequestProperty ?? null)
            : null,
      ]),
    [
      baseQuery,
      initialRequestFunnel,
      initialRequestMode,
      initialRequestProperty,
    ]
  )
  const requestKey = useMemo(
    () =>
      JSON.stringify([
        baseQuery,
        mode,
        mode === "funnels"
          ? (requestedFunnel ?? null)
          : mode === "props"
            ? (selectedPropertyState ?? null)
            : null,
      ]),
    [baseQuery, mode, requestedFunnel, selectedPropertyState]
  )
  const lastRequestKeyRef = useRef(initialRequestKey)

  const setAndStoreMode = useCallback(
    (value: string) => {
      setModeState(value)
      setPreferredMode(value)
      writeAnalyticsPreference(storageKey, value)
    },
    [storageKey]
  )

  const selectModeWithValue = useCallback(
    (modeValue: string, value: string) => {
      setModeState(modeValue)
      setPreferredMode(modeValue)
      if (modeValue === "funnels") {
        setSelectedFunnelState(value)
      }
      if (modeValue === "props") {
        setSelectedPropertyState(value)
      }
      writeAnalyticsPreference(storageKey, modeValue)
    },
    [storageKey]
  )

  const handleRowClick = useCallback(
    (item: ListItem) => {
      if (mode === "props") {
        const propertyKey = activeProperty
        if (!propertyKey) return
        updateQuery((current) => ({
          ...current,
          filters: {
            ...Object.fromEntries(
              Object.entries(current.filters).filter(
                ([key]) => !key.startsWith("prop:")
              )
            ),
            [`prop:${propertyKey}`]: String(item.name),
          },
        }))
        return
      }

      const nextQuery = {
        ...query,
        filters: {
          ...query.filters,
          goal: String(item.filterValue ?? item.name),
        },
      }

      const nextParams = mergeReportQueryParams(search, nextQuery)

      if (site.propsAvailable) {
        setPanelModeSearchParam(nextParams, "behaviors", "props")
        setBehaviorsPropertySearchParam(
          nextParams,
          activeProperty ?? selectedPropertyState ?? undefined
        )
        setModeState("props")
        setPreferredMode("props")
        writeAnalyticsPreference(storageKey, "props")
      }

      navigateAnalytics(buildReportUrl(pathname, nextParams))
    },
    [
      activeProperty,
      mode,
      pathname,
      query,
      search,
      selectedPropertyState,
      site.propsAvailable,
      storageKey,
      updateQuery,
    ]
  )

  useEffect(() => {
    if (mode === "visitors") return
    if (requestKey === lastRequestKeyRef.current) return
    lastRequestKeyRef.current = requestKey

    const controller = new AbortController()
    const requestId = dataRequestIdRef.current + 1
    dataRequestIdRef.current = requestId
    startTransition(() => setLoading(true))

    fetchBehaviors(
      baseQuery,
      {
        mode,
        funnel: requestedFunnel,
        property:
          mode === "props" ? (selectedPropertyState ?? undefined) : undefined,
      },
      controller.signal
    )
      .then((value) => {
        if (dataRequestIdRef.current !== requestId) return
        setData(value)
        if ("funnels" in value) {
          const resolvedFunnel = value.active?.name ?? value.funnels[0] ?? null
          if (mode === "funnels") {
            lastRequestKeyRef.current = JSON.stringify([
              baseQuery,
              mode,
              resolvedFunnel,
            ])
          }
          if (!requestedFunnel || !value.funnels.includes(requestedFunnel)) {
            setSelectedFunnelState(resolvedFunnel ?? null)
          }
          return
        }

        if (mode === "props" && "list" in value) {
          const resolvedProperty = value.activeProperty ?? null
          if (resolvedProperty) {
            lastRequestKeyRef.current = JSON.stringify([
              baseQuery,
              mode,
              resolvedProperty,
            ])
          }
          if (selectedPropertyState !== resolvedProperty) {
            if (resolvedProperty || selectedPropertyState) {
              setSelectedPropertyState(resolvedProperty)
            }
          }
        }
      })
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (dataRequestIdRef.current !== requestId) return
        setLoading(false)
      })

    return () => controller.abort()
  }, [baseQuery, mode, requestKey, requestedFunnel, selectedPropertyState])

  useEffect(() => {
    if (mode !== "visitors") return

    startTransition(() => {
      setLoading(true)
      setProfilesPage(1)
    })

    const controller = new AbortController()
    const requestId = profilesRequestIdRef.current + 1
    profilesRequestIdRef.current = requestId
    const id = window.setTimeout(() => {
      fetchProfiles(
        baseQuery,
        {
          limit: 9,
          page: 1,
          search: profilesSearch.trim() || undefined,
        },
        controller.signal
      )
        .then((value: ProfilesPayload) => {
          if (profilesRequestIdRef.current !== requestId) return
          setProfilesData(value)
        })
        .catch((error: Error) => {
          if (error.name !== "AbortError") console.error(error)
        })
        .finally(() => {
          if (profilesRequestIdRef.current !== requestId) return
          setLoading(false)
        })
    }, 200)

    return () => {
      window.clearTimeout(id)
      controller.abort()
    }
  }, [baseQuery, mode, profilesSearch])

  const loadMoreProfiles = useCallback(() => {
    const nextPage = profilesPage + 1
    setProfilesLoadingMore(true)
    fetchProfiles(baseQuery, {
      limit: 9,
      page: nextPage,
      search: profilesSearch.trim() || undefined,
    })
      .then((value: ProfilesPayload) => {
        setProfilesData((prev) => ({
          ...value,
          results: [...prev.results, ...value.results],
        }))
        setProfilesPage(nextPage)
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => setProfilesLoadingMore(false))
  }, [baseQuery, profilesPage, profilesSearch])

  const buildCurrentRouteSearch = useCallback(
    () =>
      buildBehaviorsRouteSearch(search, {
        mode,
        funnel: selectedFunnel,
        property: activeProperty,
      }),
    [activeProperty, mode, search, selectedFunnel]
  )

  const closeDetailsDialog = useCallback(() => {
    try {
      navigateAnalytics(baseAnalyticsPath(buildCurrentRouteSearch()))
    } catch {
      // Ignore history errors; the modal can still close locally.
    }
  }, [buildCurrentRouteSearch])

  const openDetailsDialog = useCallback(() => {
    try {
      navigateAnalytics(buildDialogPath("behaviors", buildCurrentRouteSearch()))
    } catch {
      // Ignore history errors; the dialog can still open from local state.
    }
  }, [buildCurrentRouteSearch])

  const setDetailsDialogOpen = useCallback(
    (open: boolean) => {
      try {
        const qs = buildCurrentRouteSearch()
        if (open) {
          navigateAnalytics(buildDialogPath("behaviors", qs))
        } else {
          navigateAnalytics(baseAnalyticsPath(qs))
        }
      } catch {
        // Ignore history errors; keep the current dialog state.
      }
    },
    [buildCurrentRouteSearch]
  )

  const tablePayload = listPayload
  const limitedTablePayload = useMemo((): ListPayload | null => {
    if (!tablePayload) return null
    const isConversions = mode === "conversions"
    const metricKey = isConversions
      ? "uniques"
      : (tablePayload.metrics[0] ?? "visitors")
    const sorted = [...tablePayload.results].sort((a, b) => {
      const av = Number((a as Record<string, unknown>)[metricKey] ?? 0)
      const bv = Number((b as Record<string, unknown>)[metricKey] ?? 0)
      if (av === bv) return String(a.name).localeCompare(String(b.name))
      return bv - av
    })
    return {
      ...tablePayload,
      results: sorted.slice(0, 9),
      meta: { ...tablePayload.meta, hasMore: tablePayload.results.length > 9 },
    }
  }, [tablePayload, mode])

  const activeTitle = useMemo(() => {
    switch (mode) {
      case "visitors":
        return "Visitors"
      case "props":
        return site.propsAvailable ? "Custom Properties" : "Properties"
      case "funnels":
        return "Funnels"
      case "conversions":
      default:
        return "Goals"
    }
  }, [mode, site.propsAvailable])

  const firstColumnLabel = useMemo(() => {
    switch (mode) {
      case "props":
        return "Property"
      case "funnels":
        return "Step"
      default:
        return "Goal"
    }
  }, [mode])

  const hasRenderableFunnels =
    mode === "funnels" &&
    "funnels" in data &&
    data.funnels.length > 0 &&
    data.active.steps.length > 0
  const funnelData =
    mode === "funnels" && "funnels" in data && data.funnels.length > 0
      ? data
      : null

  return {
    activeProperty,
    activeTitle,
    availableFunnels,
    behaviourTabs,
    closeDetailsDialog,
    detailsOpen,
    firstColumnLabel,
    funnelData,
    handleRowClick,
    hasRenderableFunnels,
    journeyOpen,
    limitedTablePayload,
    loadMoreProfiles,
    loading,
    mode,
    openDetailsDialog,
    profilesData,
    profilesLoadingMore,
    profilesSearch,
    propertyOptions,
    selectedFunnel,
    selectedProfile,
    setAndStoreMode,
    setDetailsDialogOpen,
    setJourneyOpen,
    setProfilesSearch,
    setSelectedProfile,
    selectModeWithValue,
    tablePayload,
  }
}

function isProfilesPayload(
  payload: BottomPanelPayload
): payload is ProfilesPayload {
  return "kind" in payload && payload.kind === "profiles"
}
