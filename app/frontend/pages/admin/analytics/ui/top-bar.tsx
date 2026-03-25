import { useEffect, useMemo, useRef, useState } from "react"
import { Calendar, Filter, Layers, Shuffle, X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import { useTopStatsContext } from "../top-stats-context"
import type { AnalyticsQuery } from "../types"
import DateRangePicker from "./date-range-dialog"
import FilterDialog from "./filter-dialog"

// No PERIOD_OPTIONS: menu rendered manually into Plausible-like groups

const FILTER_PICKER_COLUMNS = [
  {
    title: "URL",
    items: [{ label: "Page", key: "page", value: "/dashboard" }],
  },
  {
    title: "Acquisition",
    items: [
      { label: "Source", key: "source", value: "" },
      { label: "UTM tags", key: "utm", value: "" },
    ],
  },
  {
    title: "Device",
    items: [
      { label: "Location", key: "location", value: "" },
      { label: "Screen size", key: "size", value: "" },
      { label: "Browser", key: "browser", value: "" },
      { label: "Browser version", key: "browser_version", value: "" },
      { label: "Operating System", key: "os", value: "" },
      { label: "OS version", key: "os_version", value: "" },
    ],
  },
  {
    title: "Behavior",
    items: [
      { label: "Goal", key: "goal", value: "" },
      { label: "Property", key: "property", value: "" },
    ],
  },
]

type TopBarProps = {
  showCurrentVisitors: boolean
}

export default function TopBar({ showCurrentVisitors }: TopBarProps) {
  // Feature flag: hide Segments until we have real saved segments
  // We only show the Segments menu if there are more than the built-in "All visitors".
  const site = useSiteContext()
  const showSegments = Array.isArray(site.segments) && site.segments.length > 1
  const [pinned, setPinned] = useState(false)
  const sentinelRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    const sentinel = sentinelRef.current
    if (!sentinel) return

    const observer = new IntersectionObserver(
      ([entry]) => {
        setPinned(!entry.isIntersecting)
      },
      { rootMargin: "-80px 0px 0px 0px" }
    )
    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [])

  return (
    <div className="relative">
      <div
        ref={sentinelRef}
        aria-hidden="true"
        className="absolute -top-16 h-16 w-full"
      />
      <div
        className={[
          "relative z-10 flex flex-col gap-3 border-b border-transparent transition-colors",
          pinned
            ? "sticky top-0 border-border bg-background/95 backdrop-blur-xs"
            : "",
        ].join(" ")}
      >
        <div className="flex flex-col gap-2 px-2 pb-1 sm:px-0">
          <div className="flex items-center justify-between gap-2">
            {/* Live visitors + badges */}
            <div className="flex flex-wrap items-center gap-2.5">
              {showCurrentVisitors && <CurrentVisitors />}
              <div className="hidden sm:contents">
                <FiltersBar />
              </div>
            </div>

            {/* Action buttons — always right-aligned */}
            <div className="flex shrink-0 items-center gap-2">
              <FilterMenu />
              {showSegments ? <SegmentMenu /> : null}
              <QueryPeriodsPicker />
            </div>
          </div>

          {/* Filter badges row - only shown on mobile */}
          <div className="flex flex-wrap items-center gap-2.5 sm:hidden">
            <FiltersBar />
          </div>
        </div>
      </div>
    </div>
  )
}

function CurrentVisitors() {
  const { payload } = useTopStatsContext()
  const current = useMemo(() => {
    const live = payload.topStats.find(
      (stat) => stat.graphMetric === "currentVisitors"
    )
    if (live) return Math.round(live.value)
    const fallback = payload.topStats[0]
    return fallback ? Math.round(fallback.value) : 0
  }, [payload.topStats])

  return (
    <a
      href="/admin/analytics/live"
      className="flex items-center gap-2 rounded-full bg-muted px-3 py-1.5 text-sm font-semibold transition hover:bg-muted/80"
    >
      <span
        className={`inline-flex size-2 rounded-full ${current > 0 ? "animate-pulse bg-emerald-500" : "bg-muted-foreground/50"}`}
        aria-hidden="true"
      />
      <span>{current} live visitors</span>
    </a>
  )
}

function FiltersBar() {
  const { query, updateQuery } = useQueryContext()
  const eqEntries = Object.entries(query.filters)
  const advEntries = Array.isArray(query.advancedFilters)
    ? query.advancedFilters
    : []

  const order = [
    "page",
    "entry_page",
    "exit_page",
    "source",
    "channel",
    "referrer",
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_content",
    "utm_term",
    "country",
    "region",
    "city",
    "browser",
    "browser_version",
    "os",
    "os_version",
    "goal",
    "prop",
    "segment",
  ]

  const sortedEq = eqEntries
    .slice()
    .sort(
      ([a], [b]) =>
        order.indexOf(filterOrderKey(a)) - order.indexOf(filterOrderKey(b))
    )
  const sortedAdv = advEntries
    .slice()
    .sort(
      (a, b) =>
        order.indexOf(filterOrderKey(a[1])) -
        order.indexOf(filterOrderKey(b[1]))
    )

  if (sortedEq.length === 0 && sortedAdv.length === 0) {
    return null
  }

  return (
    <>
      {sortedEq.map(([key, value]) => (
        <Badge
          key={`eq:${key}`}
          variant="secondary"
          className="flex items-center gap-1 bg-accent hover:bg-primary/10"
        >
          <span className="capitalize">{filterLabel(key)}:</span>
          <span>{(query.labels && query.labels[key]) || value}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-5 p-0"
            onClick={() => {
              updateQuery((current) => {
                const nextFilters: Record<string, string> = {
                  ...current.filters,
                }
                delete nextFilters[key]
                const nextLabels = { ...(current.labels || {}) } as Record<
                  string,
                  string
                >
                delete nextLabels[key]
                const cleaned =
                  Object.keys(nextFilters).length === 0 ? undefined : nextLabels
                return { ...current, filters: nextFilters, labels: cleaned }
              })
            }}
          >
            <X className="size-3" />
            <span className="sr-only">Remove filter {key}</span>
          </Button>
        </Badge>
      ))}
      {sortedAdv.map(([op, dim, clause], i) => (
        <Badge
          key={`adv:${i}:${op}:${dim}:${clause}`}
          variant="secondary"
          className="flex items-center gap-1 bg-accent hover:bg-primary/10"
        >
          <span className="capitalize">{filterLabel(dim)}:</span>
          <span className="lowercase">{String(op).replace("_", " ")}</span>
          <span className="font-medium">{clause}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-5 p-0"
            onClick={() => {
              updateQuery((current) => {
                const currentAdv = Array.isArray(current.advancedFilters)
                  ? current.advancedFilters
                  : []
                const nextAdv = currentAdv.filter(
                  (t) => !(t[0] === op && t[1] === dim && t[2] === clause)
                )
                return { ...current, advancedFilters: nextAdv }
              })
            }}
          >
            <X className="size-3" />
            <span className="sr-only">
              Remove filter {dim} {op} {clause}
            </span>
          </Button>
        </Badge>
      ))}
      {sortedEq.length + sortedAdv.length >= 2 ? (
        <Button
          variant="ghost"
          size="sm"
          className="h-6 px-2 text-xs"
          onClick={() =>
            updateQuery((current) => ({
              ...current,
              filters: {},
              labels: undefined,
              advancedFilters: [],
            }))
          }
        >
          Clear all
        </Button>
      ) : null}
    </>
  )
}

function filterLabel(key: string) {
  if (key.startsWith("prop:")) {
    return `Property ${key.slice("prop:".length)}`
  }

  switch (key) {
    case "hostname":
      return "Hostname"
    case "source":
      return "Source"
    case "channel":
      return "Channel"
    case "size":
      return "Screen Size"
    case "country":
      return "Country"
    case "region":
      return "Region"
    case "city":
      return "City"
    case "goal":
      return "Goal"
    case "segment":
      return "Segment"
    case "page":
      return "Page"
    case "browser":
      return "Browser"
    case "browser_version":
      return "Browser Version"
    case "os":
      return "Operating System"
    case "os_version":
      return "OS Version"
    case "utm_source":
      return "UTM Source"
    case "utm_medium":
      return "UTM Medium"
    case "utm_campaign":
      return "UTM Campaign"
    case "utm_content":
      return "UTM Content"
    case "utm_term":
      return "UTM Term"
    case "referrer":
      return "Referrer URL"
    case "entry_page":
      return "Entry Page"
    case "exit_page":
      return "Exit Page"
    case "prop":
      return "Property"
    default:
      return key
  }
}

function filterOrderKey(key: string) {
  return key.startsWith("prop:") ? "prop" : key
}

function FilterMenu() {
  const { updateQuery } = useQueryContext()
  const [open, setOpen] = useState(false)
  const [dialogOpen, setDialogOpen] = useState(false)
  const openDialogFrameRef = useRef<number | null>(null)
  const [dialogType, setDialogType] = useState<
    | "page"
    | "location"
    | "source"
    | "utm"
    | "browser"
    | "browser_version"
    | "os"
    | "os_version"
    | "size"
    | "goal"
    | "property"
  >("page")

  useEffect(() => {
    return () => {
      if (openDialogFrameRef.current != null) {
        window.cancelAnimationFrame(openDialogFrameRef.current)
      }
    }
  }, [])

  const setFilter = (key: string, value: string) => {
    updateQuery((current) => ({
      ...current,
      filters: { ...current.filters, [key]: value },
    }))
  }

  const openFilterDialog = (
    nextType:
      | "page"
      | "location"
      | "source"
      | "utm"
      | "browser"
      | "browser_version"
      | "os"
      | "os_version"
      | "size"
      | "goal"
      | "property"
  ) => {
    setOpen(false)

    if (openDialogFrameRef.current != null) {
      window.cancelAnimationFrame(openDialogFrameRef.current)
    }

    openDialogFrameRef.current = window.requestAnimationFrame(() => {
      openDialogFrameRef.current = window.requestAnimationFrame(() => {
        setDialogType(nextType)
        setDialogOpen(true)
        openDialogFrameRef.current = null
      })
    })
  }

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
        <Filter className="size-4" />
        <span className="hidden sm:inline">Filters</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        sideOffset={8}
        alignOffset={-6}
        className="w-64 rounded-md border border-border bg-popover p-1 shadow-md"
      >
        {FILTER_PICKER_COLUMNS.map((column, idx) => (
          <div key={column.title} className="mb-1 last:mb-0">
            <DropdownMenuGroup>
              <DropdownMenuLabel className="text-[11px] font-extrabold tracking-wider text-primary uppercase">
                {column.title}
              </DropdownMenuLabel>
              {column.items.map((item) => (
                <DropdownMenuItem
                  key={item.label}
                  onClick={() => {
                    if (item.key === "page") {
                      openFilterDialog("page")
                    } else if (item.key === "location") {
                      openFilterDialog("location")
                    } else if (item.key === "source") {
                      openFilterDialog("source")
                    } else if (item.key === "utm") {
                      openFilterDialog("utm")
                    } else if (item.key === "browser") {
                      openFilterDialog("browser")
                    } else if (item.key === "browser_version") {
                      openFilterDialog("browser_version")
                    } else if (item.key === "os") {
                      openFilterDialog("os")
                    } else if (item.key === "os_version") {
                      openFilterDialog("os_version")
                    } else if (item.key === "size") {
                      openFilterDialog("size")
                    } else if (item.key === "goal") {
                      openFilterDialog("goal")
                    } else if (item.key === "property") {
                      openFilterDialog("property")
                    } else {
                      setFilter(item.key, item.value)
                      setOpen(false)
                    }
                  }}
                >
                  {item.label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
            {idx < FILTER_PICKER_COLUMNS.length - 1 ? (
              <DropdownMenuSeparator />
            ) : null}
          </div>
        ))}
      </DropdownMenuContent>
      <FilterDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        type={dialogType}
      />
    </DropdownMenu>
  )
}

function SegmentMenu() {
  const site = useSiteContext()
  const { query, updateQuery } = useQueryContext()
  const activeSegment = (query.filters as Record<string, string | undefined>)
    .segment

  const applySegment = (segmentId: string | null) => {
    updateQuery((current) => {
      const nextFilters = { ...current.filters }
      if (segmentId) {
        nextFilters.segment = segmentId
      } else {
        delete nextFilters.segment
      }
      return { ...current, filters: nextFilters }
    })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={
          "inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted"
        }
      >
        <Layers className="size-4" />
        <span className="hidden sm:inline">
          {activeSegment
            ? (site.segments.find((s) => s.id === activeSegment)?.name ??
              "Segment")
            : "Segments"}
        </span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Saved segments</DropdownMenuLabel>
          {site.segments.map((segment) => (
            <DropdownMenuItem
              key={segment.id}
              onClick={() => applySegment(segment.id)}
              className="hover:bg-accent data-[selected=true]:bg-primary/10"
            >
              {segment.name}
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onClick={() => applySegment(null)}
          className="hover:bg-accent"
        >
          All visitors
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function QueryPeriodsPicker() {
  const { query, updateQuery } = useQueryContext()
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const customCalendarButtonRef = useRef<HTMLButtonElement>(null)
  const compareCalendarButtonRef = useRef<HTMLButtonElement>(null)
  const [customOpen, setCustomOpen] = useState(false)
  const [compareOpen, setCompareOpen] = useState(false)

  useEffect(() => {
    function onKeydown(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null
      const tag = (target?.tagName || "").toLowerCase()
      const isTyping =
        tag === "input" ||
        tag === "textarea" ||
        (target?.isContentEditable ?? false)
      if (isTyping || e.metaKey || e.ctrlKey || e.altKey) return

      const k = (e.key || "").toUpperCase()
      const map: Record<
        string,
        | { value: AnalyticsQuery["period"]; setDate?: "current" | "last" }
        | "toggle-compare"
        | "custom"
      > = {
        D: { value: "day", setDate: "current" },
        E: { value: "day", setDate: "last" },
        R: { value: "realtime" },
        W: { value: "7d" },
        F: { value: "28d" },
        N: { value: "91d" },
        M: { value: "month", setDate: "current" },
        P: { value: "month", setDate: "last" },
        Y: { value: "year", setDate: "current" },
        L: { value: "12mo" },
        A: { value: "all" },
        C: "custom",
        X: "toggle-compare",
      }
      const action = map[k]
      if (!action) return
      e.preventDefault()
      if (action === "custom") {
        setCustomOpen(true)
        return
      }
      if (action === "toggle-compare") {
        updateQuery((current) => ({
          ...current,
          comparison:
            current.comparison === "previous_period" ? null : "previous_period",
        }))
        return
      }
      updateQuery((current) => applyPeriodSelection(current, action))
    }
    window.addEventListener("keydown", onKeydown)
    return () => window.removeEventListener("keydown", onKeydown)
  }, [updateQuery, customCalendarButtonRef])

  const compareEnabled = Boolean(query.comparison)
  const compareLabel = (() => {
    if (!query.comparison) return "Compare"
    if (query.comparison === "previous_period") return "Previous period"
    if (query.comparison === "year_over_year") return "Year over year"
    if (query.comparison === "custom" && query.compareFrom && query.compareTo) {
      const from = String(query.compareFrom).slice(0, 10)
      const to = String(query.compareTo).slice(0, 10)

      const fromDate = new Date(from)
      const toDate = new Date(to)

      const monthNames = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ]
      const fromMonth = monthNames[fromDate.getMonth()]
      const toMonth = monthNames[toDate.getMonth()]
      const fromDay = fromDate.getDate()
      const toDay = toDate.getDate()
      const fromYear = fromDate.getFullYear()
      const toYear = toDate.getFullYear()

      // Same year
      if (fromYear === toYear) {
        // Same month
        if (fromMonth === toMonth) {
          return `${fromMonth} ${fromDay}–${toDay}, ${fromYear}`
        }
        // Different months, same year
        return `${fromMonth} ${fromDay}–${toMonth} ${toDay}, ${fromYear}`
      }
      // Different years
      return `${fromMonth} ${fromDay}, ${fromYear}–${toMonth} ${toDay}, ${toYear}`
    }
    return "Compare"
  })()

  return (
    <div className="flex flex-wrap items-center gap-2">
      <DropdownMenu open={dropdownOpen} onOpenChange={setDropdownOpen}>
        <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
          <Calendar className="size-4 shrink-0" />
          <span className="truncate">{getPeriodDisplay(query)}</span>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuItem
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
            onClick={() =>
              updateQuery((c) =>
                applyPeriodSelection(c, { value: "day", setDate: "current" })
              )
            }
          >
            <MenuRow
              label="Today"
              hint="D"
              active={isActiveDay(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
            onClick={() =>
              updateQuery((c) =>
                applyPeriodSelection(c, { value: "day", setDate: "last" })
              )
            }
          >
            <MenuRow
              label="Yesterday"
              hint="E"
              active={isActiveDay(query, "last")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "realtime" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Realtime"
              hint="R"
              active={query.period === "realtime"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "7d" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 7 Days"
              hint="W"
              active={query.period === "7d"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "28d" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 28 Days"
              hint="F"
              active={query.period === "28d"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "91d" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 91 Days"
              hint="N"
              active={query.period === "91d"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) =>
                applyPeriodSelection(c, { value: "month", setDate: "current" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Month to Date"
              hint="M"
              active={isActiveMonth(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) =>
                applyPeriodSelection(c, { value: "month", setDate: "last" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last Month"
              hint="P"
              active={isActiveMonth(query, "last")}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) =>
                applyPeriodSelection(c, { value: "year", setDate: "current" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Year to Date"
              hint="Y"
              active={isActiveYear(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "12mo" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 12 Months"
              hint="L"
              active={query.period === "12mo"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((c) => applyPeriodSelection(c, { value: "all" }))
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="All time"
              hint="A"
              active={query.period === "all"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => {
              setDropdownOpen(false)
              setTimeout(() => setCustomOpen(true), 0)
            }}
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Custom Range"
              hint="C"
              active={query.period === "custom"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {query.comparison ? (
            <DropdownMenuItem
              onClick={() =>
                updateQuery((c) => ({
                  ...c,
                  comparison: null,
                  compareFrom: null,
                  compareTo: null,
                }))
              }
              className="hover:bg-accent"
            >
              <MenuRow label="Disable comparison" hint="X" />
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem
              onClick={() =>
                updateQuery((c) => ({ ...c, comparison: "previous_period" }))
              }
              className="hover:bg-accent"
            >
              <MenuRow
                label="Compare"
                hint="X"
                leftIcon={<Shuffle className="mr-2 size-4" />}
              />
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {compareEnabled && (
        <>
          <span className="shrink-0 text-sm text-muted-foreground">vs.</span>
          <DropdownMenu>
            <DropdownMenuTrigger
              className={
                "inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted"
              }
            >
              <span className="truncate">{compareLabel}</span>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((c) => ({
                    ...c,
                    comparison: null,
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent"
              >
                <MenuRow label="Disable comparison" />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((c) => ({
                    ...c,
                    comparison: "previous_period",
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Previous period"
                  active={query.comparison === "previous_period"}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((c) => ({
                    ...c,
                    comparison: "year_over_year",
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Year over year"
                  active={query.comparison === "year_over_year"}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() => {
                  setDropdownOpen(false)
                  setTimeout(() => setCompareOpen(true), 0)
                }}
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Custom period…"
                  active={query.comparison === "custom"}
                />
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((c) => ({ ...c, matchDayOfWeek: true }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Match day of week"
                  active={Boolean(query.matchDayOfWeek)}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((c) => ({ ...c, matchDayOfWeek: false }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Match exact date"
                  active={Boolean(query.matchDayOfWeek) === false}
                />
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </>
      )}

      {/* Custom Range Calendar Picker */}
      <DateRangePicker
        buttonRef={customCalendarButtonRef}
        open={customOpen}
        onOpenChange={setCustomOpen}
        initialFrom={query.period === "custom" ? query.from : undefined}
        initialTo={query.period === "custom" ? query.to : undefined}
        onApply={(fromISO, toISO) => {
          setCustomOpen(false)
          updateQuery((current) => ({
            ...current,
            period: "custom",
            from: fromISO,
            to: toISO,
          }))
        }}
      />

      {/* Comparison Custom Range Calendar Picker */}
      <DateRangePicker
        buttonRef={compareCalendarButtonRef}
        open={compareOpen}
        onOpenChange={setCompareOpen}
        initialFrom={
          query.comparison === "custom" ? query.compareFrom : undefined
        }
        initialTo={query.comparison === "custom" ? query.compareTo : undefined}
        onApply={(fromISO, toISO) => {
          setCompareOpen(false)
          updateQuery(
            (current) =>
              ({
                ...current,
                comparison: "custom",
                compareFrom: fromISO,
                compareTo: toISO,
              }) as AnalyticsQuery
          )
        }}
      />
    </div>
  )
}

function getPeriodDisplay(query: AnalyticsQuery) {
  const pad = (n: number) => String(n).padStart(2, "0")
  const ymd = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  const monthLabel = (dateStr?: string | null) => {
    if (!dateStr) return "Month to Date"
    const [y, m] = String(dateStr).split("-")
    const monthNames = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ]
    const now = new Date()
    if (Number(y) === now.getFullYear() && Number(m) === now.getMonth() + 1)
      return "Month to Date"
    return `${monthNames[Math.max(0, Math.min(11, Number(m) - 1))]} ${y}`
  }
  const yearLabel = (dateStr?: string | null) => {
    if (!dateStr) return "Year to Date"
    const y = String(dateStr).slice(0, 4)
    const now = new Date()
    if (Number(y) === now.getFullYear()) return "Year to Date"
    return y
  }

  switch (query.period) {
    case "realtime":
      return "Realtime (30m)"
    case "day": {
      const now = new Date()
      if (!query.date) return "Today"
      const yest = new Date(now)
      yest.setDate(now.getDate() - 1)
      if (query.date === ymd(now)) return "Today"
      if (query.date === ymd(yest)) return "Yesterday"
      return query.date
    }
    case "7d":
      return "Last 7 days"
    case "28d":
      return "Last 28 days"
    case "30d":
      return "Last 30 days"
    case "91d":
      return "Last 91 days"
    case "month":
      return monthLabel(query.date)
    case "year":
      return yearLabel(query.date)
    case "12mo":
      return "Last 12 Months"
    case "all":
      return "All time"
    case "custom": {
      const from = query.from as string | undefined
      const to = query.to as string | undefined
      if (!from || !to) return "Custom range"

      const fromDate = new Date(String(from).slice(0, 10))
      const toDate = new Date(String(to).slice(0, 10))

      const monthNames = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ]
      const fromMonth = monthNames[fromDate.getMonth()]
      const toMonth = monthNames[toDate.getMonth()]
      const fromDay = fromDate.getDate()
      const toDay = toDate.getDate()
      const fromYear = fromDate.getFullYear()
      const toYear = toDate.getFullYear()

      // Same year
      if (fromYear === toYear) {
        // Same month
        if (fromMonth === toMonth) {
          return `${fromMonth} ${fromDay}–${toDay}, ${fromYear}`
        }
        // Different months, same year
        return `${fromMonth} ${fromDay}–${toMonth} ${toDay}, ${fromYear}`
      }
      // Different years
      return `${fromMonth} ${fromDay}, ${fromYear}–${toMonth} ${toDay}, ${toYear}`
    }
    default:
      return "Period"
  }
}

function MenuRow({
  label,
  hint,
  active,
  leftIcon,
  rightIcon,
}: {
  label: string
  hint?: string
  active?: boolean
  leftIcon?: React.ReactNode
  rightIcon?: React.ReactNode
}) {
  return (
    <span className="flex w-full items-center justify-between">
      <span
        className={`flex items-center ${active ? "font-semibold text-primary" : ""}`}
      >
        {leftIcon}
        {label}
      </span>
      {rightIcon ? (
        rightIcon
      ) : hint ? (
        <span className="rounded-md border border-border px-1.5 py-0.5 text-[11px] text-muted-foreground">
          {hint}
        </span>
      ) : null}
    </span>
  )
}

function isActiveDay(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "day") return false
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, "0")
  const ymd = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  if (mode === "current") {
    return !query.date || query.date === ymd(now)
  }
  const y = new Date(now)
  y.setDate(now.getDate() - 1)
  return query.date === ymd(y)
}

function isActiveMonth(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "month") return false
  const now = new Date()
  const target = new Date(now)
  if (mode === "last") target.setMonth(target.getMonth() - 1)
  const y = target.getFullYear()
  const m = target.getMonth() + 1
  if (!query.date) {
    // No date means current MTD
    return mode === "current"
  }
  const [qy, qm] = String(query.date)
    .split("-")
    .map((s) => Number(s))
  return qy === y && qm === m
}

function isActiveYear(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "year") return false
  const now = new Date()
  const y = mode === "last" ? now.getFullYear() - 1 : now.getFullYear()
  if (!query.date) {
    return mode === "current"
  }
  const qy = Number(String(query.date).slice(0, 4))
  return qy === y
}

function applyPeriodSelection(
  current: AnalyticsQuery,
  option: { value: AnalyticsQuery["period"]; setDate?: "current" | "last" }
) {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, "0")
  const ymd = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  const setMonthDate = (mode: "current" | "last") => {
    const d = new Date(now)
    if (mode === "last") {
      d.setMonth(d.getMonth() - 1)
    }
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-01`
  }
  const setYearDate = (mode: "current" | "last") => {
    const y = mode === "last" ? now.getFullYear() - 1 : now.getFullYear()
    return `${y}-01-01`
  }
  const next: AnalyticsQuery = {
    ...current,
    period: option.value,
    from: null,
    to: null,
  }
  if (option.value === "day" && option.setDate === "last") {
    const y = new Date(now)
    y.setDate(now.getDate() - 1)
    next.date = ymd(y)
    return next
  }
  if (option.value === "month") {
    next.date = setMonthDate(option.setDate ?? "current")
    return next
  }
  if (option.value === "year") {
    next.date = setYearDate(option.setDate ?? "current")
    return next
  }
  next.date = null
  return next
}
