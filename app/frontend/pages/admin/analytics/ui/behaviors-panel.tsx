import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import { ArrowDown, Check, ChevronDown } from "lucide-react"

import { Input } from "@/components/ui/input"

import { fetchBehaviors } from "../api"
import {
  getBehaviorsFunnelFromSearch,
  getBehaviorsPropertyFromSearch,
  setBehaviorsFunnelSearchParam,
  setBehaviorsPropertySearchParam,
} from "../lib/dashboard-url-state"
import {
  baseAnalyticsPath,
  buildDialogPath,
  parseDialogFromPath,
} from "../lib/dialog-path"
import { navigateAnalytics } from "../lib/location-store"
import { percentageFormatter } from "../lib/number-formatter"
import {
  getBehaviorsModeFromSearch,
  setPanelModeSearchParam,
} from "../lib/panel-mode"
import { useScopedQuery } from "../lib/query-scope"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type {
  BehaviorsPayload,
  ListItem,
  ListMetricKey,
  ListPayload,
} from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"

const BEHAVIOR_TABS: Array<{ value: string; label: string }> = [
  { value: "conversions", label: "Goals" },
  { value: "props", label: "Properties" },
  { value: "funnels", label: "Funnels" },
]

const STORAGE_PREFIX = "admin.analytics.behaviors"

type BehaviorsPanelProps = {
  initialData: BehaviorsPayload
  initialMode?: string | null
  initialFunnel?: string | null
  initialProperty?: string | null
}

export default function BehaviorsPanel({
  initialData,
  initialMode,
  initialFunnel,
  initialProperty,
}: BehaviorsPanelProps) {
  const { query, pathname, search, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const behaviourTabs = useMemo(
    () =>
      site.hasGoals
        ? BEHAVIOR_TABS
        : BEHAVIOR_TABS.filter((tab) => tab.value !== "conversions"),
    [site.hasGoals]
  )

  const defaultMode = behaviourTabs[0]?.value ?? "props"
  const queryMode = getBehaviorsModeFromSearch(
    search,
    query.mode,
    site.hasGoals
  )

  const [preferredMode, setPreferredMode] = useState<string | null>(null)
  const [modeState, setModeState] = useState(
    initialMode ?? queryMode ?? defaultMode
  )
  const [data, setData] = useState<BehaviorsPayload>(initialData)
  const [loading, setLoading] = useState(false)
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
    () => ("funnels" in data ? data.funnels : []),
    [data]
  )
  const routeSelectedFunnel = detailsOpen ? selectedFunnelFromSearch : null
  const routeSelectedProperty = detailsOpen ? selectedPropertyFromSearch : null
  const selectedFunnel =
    routeSelectedFunnel ??
    selectedFunnelState ??
    ("funnels" in data ? (data.active?.name ?? data.funnels[0]) : undefined)
  const requestedFunnel =
    routeSelectedFunnel ?? selectedFunnelState ?? undefined
  const listPayload: ListPayload | null = useMemo(() => {
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
    ("funnels" in initialData
      ? (initialData.active?.name ?? initialData.funnels[0])
      : undefined)
  const initialRequestProperty =
    initialProperty ??
    selectedPropertyState ??
    ("list" in initialData ? (initialData.activeProperty ?? null) : null)
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

  const setAndStoreMode = (value: string) => {
    setModeState(value)
    setPreferredMode(value)
    if (typeof window !== "undefined") {
      localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, value)
    }
  }

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
      if (typeof window !== "undefined") {
        localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, modeValue)
      }
    },
    [site.domain]
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
      } else {
        updateQuery((current) => ({
          ...current,
          filters: { ...current.filters, goal: String(item.name) },
        }))
      }
    },
    [activeProperty, mode, updateQuery]
  )

  useEffect(() => {
    if (requestKey === lastRequestKeyRef.current) return
    lastRequestKeyRef.current = requestKey

    const controller = new AbortController()
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
          if (requestedFunnel && value.funnels.includes(requestedFunnel)) {
            return
          }
          setSelectedFunnelState(resolvedFunnel ?? null)
        } else if (mode === "props" && "list" in value) {
          const resolvedProperty = value.activeProperty ?? null
          if (resolvedProperty) {
            lastRequestKeyRef.current = JSON.stringify([
              baseQuery,
              mode,
              resolvedProperty,
            ])
          }
          if (selectedPropertyState === resolvedProperty) return
          if (resolvedProperty || selectedPropertyState) {
            setSelectedPropertyState(resolvedProperty)
          }
        }
      })
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => setLoading(false))

    return () => controller.abort()
  }, [baseQuery, mode, requestKey, requestedFunnel, selectedPropertyState])

  const closeDetailsDialog = useCallback(() => {
    try {
      const sp = new URLSearchParams(window.location.search)
      sp.delete("dialog")
      setPanelModeSearchParam(sp, "behaviors", mode)
      if (selectedFunnel) {
        setBehaviorsFunnelSearchParam(sp, selectedFunnel)
      }
      if (activeProperty) {
        setBehaviorsPropertySearchParam(sp, activeProperty)
      }
      navigateAnalytics(baseAnalyticsPath(sp.toString()))
    } catch {
      // Ignore history errors; the modal can still close locally.
    }
  }, [activeProperty, mode, selectedFunnel])

  const tablePayload = listPayload

  // Limit card view to top 9 by first metric; Details uses full tablePayload
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
    const sliced = sorted.slice(0, 9)
    return {
      ...tablePayload,
      results: sliced,
      meta: { ...tablePayload.meta, hasMore: tablePayload.results.length > 9 },
    }
  }, [tablePayload, mode])

  const activeTitle = useMemo(() => {
    switch (mode) {
      case "props":
        return site.propsAvailable ? "Custom Properties" : "Properties"
      case "funnels":
        return "Funnels"
      case "conversions":
      default:
        return site.hasGoals ? "Goal Conversions" : "Behaviors"
    }
  }, [mode, site.hasGoals, site.propsAvailable])

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

  return (
    <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-medium">{activeTitle}</h2>
        <PanelTabs>
          {behaviourTabs
            .filter((tab) => tab.value !== "funnels" && tab.value !== "props")
            .map((tab) => (
              <PanelTab
                key={tab.value}
                active={mode === tab.value}
                onClick={() => setAndStoreMode(tab.value)}
              >
                {tab.label}
              </PanelTab>
            ))}
          {propertyOptions.length > 0 ? (
            <SelectionTabDropdown
              active={mode === "props"}
              label="Properties"
              options={propertyOptions}
              value={activeProperty ?? undefined}
              searchPlaceholder="Search properties"
              onSelect={(value) => {
                selectModeWithValue("props", value)
              }}
            />
          ) : (
            <PanelTab
              active={mode === "props"}
              onClick={() => setAndStoreMode("props")}
            >
              Properties
            </PanelTab>
          )}
          {availableFunnels.length > 0 ? (
            <SelectionTabDropdown
              active={mode === "funnels"}
              label="Funnels"
              options={availableFunnels}
              value={selectedFunnel}
              searchPlaceholder="Search funnels"
              onSelect={(value) => {
                selectModeWithValue("funnels", value)
              }}
            />
          ) : (
            <PanelTab
              active={mode === "funnels"}
              onClick={() => setAndStoreMode("funnels")}
            >
              Funnels
            </PanelTab>
          )}
        </PanelTabs>
      </header>
      {!site.hasGoals ? (
        <p className="text-sm text-muted-foreground">
          No goals configured yet. Explore properties or funnels in the
          meantime.
        </p>
      ) : null}

      {loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : hasRenderableFunnels ? (
        <FunnelSteps data={data} />
      ) : mode === "funnels" ? (
        <p className="text-sm text-muted-foreground">No funnels available</p>
      ) : tablePayload ? (
        <>
          {mode === "props" && activeProperty ? (
            <p className="text-sm text-muted-foreground">
              Showing values for{" "}
              <span className="font-medium text-foreground">
                {activeProperty}
              </span>
            </p>
          ) : null}
          <MetricTable
            data={limitedTablePayload ?? tablePayload}
            highlightedMetric={
              mode === "conversions"
                ? "uniques"
                : tablePayload.metrics.includes("conversionRate")
                  ? "conversionRate"
                  : tablePayload.metrics[0]
            }
            onRowClick={handleRowClick}
            displayBars={false}
            revealSecondaryMetricsOnHover={false}
            firstColumnLabel={firstColumnLabel}
            barColorTheme="cyan"
          />
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton
              onClick={() => {
                try {
                  const sp = new URLSearchParams(window.location.search)
                  sp.delete("dialog")
                  setPanelModeSearchParam(sp, "behaviors", mode)
                  if (selectedFunnel) {
                    setBehaviorsFunnelSearchParam(sp, selectedFunnel)
                  }
                  if (activeProperty) {
                    setBehaviorsPropertySearchParam(sp, activeProperty)
                  }
                  navigateAnalytics(buildDialogPath("behaviors", sp.toString()))
                } catch {
                  // Ignore history errors; the dialog can still open from local state.
                }
              }}
            >
              Details
            </DetailsButton>
          </div>
        </>
      ) : (
        <PanelEmptyState>No data available</PanelEmptyState>
      )}

      {tablePayload ? (
        <RemoteDetailsDialog
          open={detailsOpen}
          onOpenChange={(open) => {
            try {
              const sp = new URLSearchParams(window.location.search)
              sp.delete("dialog")
              setPanelModeSearchParam(sp, "behaviors", mode)
              if (selectedFunnel) {
                setBehaviorsFunnelSearchParam(sp, selectedFunnel)
              }
              if (activeProperty) {
                setBehaviorsPropertySearchParam(sp, activeProperty)
              }
              const qs = sp.toString()
              if (open) {
                navigateAnalytics(buildDialogPath("behaviors", qs))
              } else {
                navigateAnalytics(baseAnalyticsPath(qs))
              }
            } catch {
              // Ignore history errors; keep the current dialog state.
            }
          }}
          title={activeTitle}
          endpoint="/admin/analytics/behaviors"
          extras={{
            mode,
            funnel: selectedFunnel,
            property:
              mode === "props" ? (activeProperty ?? undefined) : undefined,
          }}
          firstColumnLabel={firstColumnLabel}
          initialSearch=""
          defaultSortKey={
            tablePayload.metrics.includes("conversionRate")
              ? ("conversionRate" as ListMetricKey)
              : (tablePayload.metrics[0] as ListMetricKey)
          }
          onRowClick={(item) => {
            handleRowClick(item)
            closeDetailsDialog()
          }}
        />
      ) : null}
    </section>
  )
}

type FunnelStepsProps = {
  data: Extract<
    BehaviorsPayload,
    { funnels: string[]; active: { steps: unknown[] } }
  >
}

function FunnelSteps({ data }: FunnelStepsProps) {
  const funnel = data.active
  if (!funnel) return null

  const steps = funnel.steps
  const enteringVisitors = funnel.enteringVisitors ?? steps[0]?.visitors ?? 0
  const neverEnteringVisitors = funnel.neverEnteringVisitors ?? 0
  const maxVisitors = Math.max(...steps.map((step) => step.visitors), 1)
  const overallRate =
    funnel.conversionRate ?? steps[steps.length - 1]?.conversionRate ?? 0

  const enrichedSteps = steps.map((step) => {
    const barPercent = maxVisitors > 0 ? (step.visitors / maxVisitors) * 100 : 0
    return { ...step, barPercent }
  })

  return (
    <div className="space-y-8">
      <div className="space-y-1">
        <p className="text-lg font-semibold text-foreground">{funnel.name}</p>
        <p className="text-sm text-muted-foreground">
          {steps.length}-step funnel • {percentageFormatter(overallRate)}{" "}
          conversion rate
        </p>
      </div>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1.6fr)_minmax(20rem,1fr)]">
        <div className="rounded-md border border-border/70 bg-muted/10 p-4 sm:p-6">
          <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
            {enrichedSteps.map((step, index) => (
              <article
                key={step.name}
                className="flex min-h-72 flex-col rounded-md border border-border/70 bg-card p-4 shadow-xs"
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-xs font-semibold tracking-[0.18em] text-muted-foreground uppercase">
                      Step {index + 1}
                    </p>
                    <h3 className="mt-2 text-base/5 font-semibold text-foreground">
                      {step.name}
                    </h3>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-semibold text-foreground">
                      {compactNumberFormatter.format(step.visitors)}
                    </p>
                    <p className="text-xs text-muted-foreground">visitors</p>
                  </div>
                </div>

                <div className="mt-6 flex flex-1 items-end justify-center">
                  <div className="flex h-52 w-full max-w-28 items-end">
                    <div
                      className="relative w-full overflow-hidden rounded-t-xl rounded-b-md bg-primary/10"
                      style={{
                        height:
                          step.visitors > 0
                            ? `${Math.max(step.barPercent, 18)}%`
                            : "0%",
                      }}
                    >
                      <div
                        className="absolute inset-x-0 bottom-0 bg-primary"
                        style={{ height: `${step.conversionRateStep}%` }}
                      />
                      {step.dropoff > 0 ? (
                        <div
                          className="absolute inset-x-0 top-0 border-b border-primary/20 bg-[repeating-linear-gradient(-45deg,rgba(15,23,42,0.06),rgba(15,23,42,0.06)_6px,transparent_6px,transparent_12px)]"
                          style={{
                            height: `${100 - step.conversionRateStep}%`,
                          }}
                        />
                      ) : null}
                    </div>
                  </div>
                </div>

                <div className="mt-5 space-y-2 border-t border-border/70 pt-4 text-sm">
                  <div className="flex items-center justify-between gap-4">
                    <span className="text-muted-foreground">
                      {index === 0 ? "Entered funnel" : "Reached step"}
                    </span>
                    <span className="font-medium text-foreground">
                      {percentageFormatter(
                        index === 0
                          ? funnel.enteringVisitorsPercentage
                          : step.conversionRate
                      )}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-4">
                    <span className="text-muted-foreground">
                      {index === 0 ? "Never entered" : "Dropped off"}
                    </span>
                    <span className="font-medium text-foreground">
                      {compactNumberFormatter.format(step.dropoff)}
                    </span>
                  </div>
                </div>
              </article>
            ))}
          </div>
        </div>

        <aside className="rounded-md border border-border/70 bg-card p-5 shadow-xs">
          <p className="text-xs font-semibold tracking-[0.18em] text-muted-foreground uppercase">
            Summary
          </p>

          <div className="mt-4 text-center">
            <p className="text-4xl font-bold text-foreground tabular-nums">
              {percentageFormatter(overallRate)}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              overall conversion
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {compactNumberFormatter.format(enteringVisitors)} entered
              {" \u00B7 "}
              {compactNumberFormatter.format(
                steps[steps.length - 1]?.visitors ?? 0
              )}{" "}
              completed
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {compactNumberFormatter.format(neverEnteringVisitors)} never
              entered
            </p>
          </div>

          <div className="mt-6 border-t border-border/70 pt-4">
            {enrichedSteps.map((step, index) => (
              <div key={`${step.name}-summary`}>
                {index > 0 ? (
                  <div className="flex items-center gap-2 py-1.5 pl-1">
                    <ArrowDown className="size-3 shrink-0 text-muted-foreground/50" />
                    <span className="text-xs text-muted-foreground">
                      {step.dropoff > 0
                        ? `${compactNumberFormatter.format(step.dropoff)} dropped \u00B7 ${percentageFormatter(step.conversionRateStep)} converted`
                        : "no drop-off"}
                    </span>
                  </div>
                ) : null}
                <div className="space-y-1.5">
                  <div className="flex items-center justify-between gap-3 text-sm">
                    <span className="truncate font-medium text-foreground">
                      {step.name}
                    </span>
                    <span className="shrink-0 text-muted-foreground tabular-nums">
                      {compactNumberFormatter.format(step.visitors)}
                    </span>
                  </div>
                  <div className="h-2.5 overflow-hidden rounded-sm bg-muted">
                    <div
                      className="h-full rounded-sm bg-primary"
                      style={{
                        width:
                          step.visitors > 0
                            ? `${Math.max(4, step.barPercent)}%`
                            : "0%",
                      }}
                    />
                  </div>
                </div>
              </div>
            ))}
          </div>
        </aside>
      </div>
    </div>
  )
}

function SelectionTabDropdown({
  active,
  label,
  options,
  value,
  searchPlaceholder,
  onSelect,
}: {
  active: boolean
  label: string
  options: string[]
  value?: string
  searchPlaceholder: string
  onSelect: (next: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState("")
  const inputRef = useRef<HTMLInputElement | null>(null)
  const rootRef = useRef<HTMLDivElement | null>(null)

  const filtered = useMemo(() => {
    if (!search) return options
    return options.filter((option) =>
      option.toLowerCase().includes(search.toLowerCase())
    )
  }, [options, search])

  useEffect(() => {
    if (!open) return
    const id = window.requestAnimationFrame(() => {
      inputRef.current?.focus({ preventScroll: true })
    })
    return () => window.cancelAnimationFrame(id)
  }, [open])

  useEffect(() => {
    if (!open) return
    const handlePointerDown = (event: MouseEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) {
        setOpen(false)
        setSearch("")
      }
    }
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false)
        setSearch("")
      }
    }
    window.addEventListener("mousedown", handlePointerDown)
    window.addEventListener("keydown", handleEscape)
    return () => {
      window.removeEventListener("mousedown", handlePointerDown)
      window.removeEventListener("keydown", handleEscape)
    }
  }, [open])

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => {
          setOpen((current) => {
            const next = !current
            if (!next) setSearch("")
            return next
          })
        }}
        className={[
          "inline-flex items-center gap-1 border-b-2 pb-1 transition-colors",
          active
            ? "border-primary text-primary"
            : "border-transparent text-muted-foreground hover:text-primary",
        ].join(" ")}
      >
        {label}
        <ChevronDown className="size-3.5" aria-hidden="true" />
      </button>
      {open ? (
        <div className="absolute top-full right-0 z-30 mt-2 w-72 overflow-hidden rounded-2xl border border-border bg-popover text-popover-foreground shadow-xl ring-1 ring-foreground/10">
          <div className="border-b p-2">
            <Input
              ref={inputRef}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={searchPlaceholder}
            />
          </div>
          <div className="max-h-72 overflow-y-auto py-1 text-sm">
            {filtered.map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => {
                  onSelect(option)
                  setOpen(false)
                  setSearch("")
                }}
                className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left hover:bg-accent hover:text-accent-foreground"
              >
                <span className="truncate">{option}</span>
                {option === value ? (
                  <Check className="size-4 text-primary" aria-hidden="true" />
                ) : null}
              </button>
            ))}
            {filtered.length === 0 ? (
              <div className="px-3 py-2 text-sm text-muted-foreground">
                No matches
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  )
}

const compactNumberFormatter = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
})
