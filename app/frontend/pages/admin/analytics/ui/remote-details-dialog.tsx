import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react"
import { createPortal } from "react-dom"
import { ExternalLink, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

import { fetchListPage } from "../api"
import { useDebounce } from "../hooks/use-debounce"
import { lockBodyScroll } from "../lib/body-scroll-lock"
import { normalizeMetricKey } from "../lib/metric-key"
import { useQueryContext } from "../query-context"
import type {
  AnalyticsQuery,
  ListItem,
  ListMetricKey,
  ListPayload,
} from "../types"
import { FORMATTERS, isPathLike, METRIC_LABELS, renderFlag } from "./list-table"

type SortState = {
  key: "name" | ListMetricKey
  direction: "asc" | "desc"
}

type RemoteDetailsDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  endpoint: string
  extras?: Record<string, unknown>
  firstColumnLabel?: string
  onRowClick?: (item: ListItem) => void
  renderLeading?: (item: ListItem) => React.ReactNode
  initialLimit?: number
  getExternalLinkUrl?: (item: ListItem) => string | null
  sortable?: boolean
  defaultSortKey?: SortState["key"]
  initialSearch?: string
}

export default function RemoteDetailsDialog({
  open,
  onOpenChange,
  title,
  endpoint,
  extras = {},
  firstColumnLabel = "Item",
  onRowClick,
  renderLeading,
  initialLimit = 100,
  getExternalLinkUrl,
  sortable = true,
  defaultSortKey,
  initialSearch,
}: RemoteDetailsDialogProps) {
  const { query } = useQueryContext()
  const [mounted, setMounted] = useState(false)
  const [search, setSearch] = useState("")
  const [debouncedSearch, setDebouncedSearch] = useState("")
  const [sort, setSort] = useState<SortState>(() => {
    const key = defaultSortKey ?? "visitDuration"
    return { key, direction: key === "name" ? "asc" : "desc" }
  })
  const [metrics, setMetrics] = useState<ListMetricKey[]>(["visitors"])
  const [metricLabels, setMetricLabels] = useState<Record<string, string>>({})
  const [items, setItems] = useState<ListItem[]>([])
  const [page, setPage] = useState(1)
  const [hasMore, setHasMore] = useState(false)
  const [loading, setLoading] = useState(false)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const dialogRef = useRef<HTMLDivElement | null>(null)

  // Debounced search following Plausible's 300ms pattern
  const debouncedSetSearch = useDebounce<(value: string) => void>(
    (value: string) => {
      setDebouncedSearch(value)
      setPage(1) // Reset to first page on search
    },
    300
  )

  const handleSearchChange = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value
      setSearch(value)
      debouncedSetSearch(value)
    },
    [debouncedSetSearch]
  )

  // Mount tracking
  useEffect(() => setMounted(true), [])

  // Seed search on open (useful for props subset)
  useEffect(() => {
    if (open && initialSearch && !search) {
      setSearch(initialSearch)
      setDebouncedSearch(initialSearch)
      setPage(1)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initialSearch])

  // Body scroll lock
  useEffect(() => {
    if (!open) return
    return lockBodyScroll()
  }, [open])

  // Focus handling
  useEffect(() => {
    if (open) {
      setTimeout(() => dialogRef.current?.focus(), 0)
    }
  }, [open])

  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onOpenChange(false)
      }
      if (event.key === "/" && !(event.target instanceof HTMLInputElement)) {
        event.preventDefault()
        inputRef.current?.focus()
      }
    },
    [onOpenChange]
  )

  useEffect(() => {
    if (!open) return
    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [open, handleKeyDown])

  // Fetch first page when opened or when query/extras/debouncedSearch/sort change
  // Following Plausible's pattern: new search resets page to 1
  useEffect(() => {
    if (!open) return
    let aborted = false
    setLoading(true)
    setPage(1)

    // Build order_by following Plausible's format: [["metric", "direction"]]
    const orderBy = sortable ? [[sort.key, sort.direction]] : undefined

    fetchListPage(endpoint, query as AnalyticsQuery, extras, {
      limit: initialLimit,
      page: 1,
      search: debouncedSearch,
      orderBy,
    })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      .then((rawPayload: any) => {
        const payload: ListPayload =
          rawPayload && (rawPayload.results || rawPayload.metrics)
            ? rawPayload
            : rawPayload?.list || rawPayload
        if (aborted) return
        setItems(payload.results.map(normalizeItemKeys))
        const normalizedMetrics = payload.metrics.map(
          normalizeMetricKey
        ) as ListMetricKey[]
        setMetrics(normalizedMetrics)
        const metaObj = payload.meta as Record<string, unknown>
        const labels = metaObj.metricLabels || metaObj.metric_labels
        if (labels && typeof labels === "object") {
          // Normalize keys to camelCase to match ListMetricKey in UI
          const normalized: Record<string, string> = {}
          for (const [k, v] of Object.entries(
            labels as Record<string, string>
          )) {
            const ck = k.includes("_")
              ? k.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
              : k
            normalized[ck] = String(v)
          }
          setMetricLabels(normalized)
        } else {
          setMetricLabels({})
        }
        // If current sort key is not available, fall back to visitors (desc) or name (asc)
        if (
          !normalizedMetrics.includes(sort.key as ListMetricKey) &&
          sort.key !== "name"
        ) {
          setSort({
            key: normalizedMetrics.includes("visitors") ? "visitors" : "name",
            direction: normalizedMetrics.includes("visitors") ? "desc" : "asc",
          })
        }
        setHasMore(Boolean(payload.meta?.hasMore))
      })
      .catch((err) => {
        if (!aborted) console.error(err)
      })
      .finally(() => {
        if (!aborted) setLoading(false)
      })
    return () => {
      aborted = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    open,
    endpoint,
    // eslint-disable-next-line react-hooks/exhaustive-deps
    JSON.stringify(extras),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    JSON.stringify(query),
    debouncedSearch,
    sort.key,
    sort.direction,
    initialLimit,
  ])

  const loadMore = useCallback(() => {
    const next = page + 1
    setLoading(true)
    let aborted = false

    // Build order_by following Plausible's format: [["metric", "direction"]]
    const orderBy = [[sort.key, sort.direction]]

    fetchListPage(endpoint, query as AnalyticsQuery, extras, {
      limit: initialLimit,
      page: next,
      search: debouncedSearch,
      orderBy,
    })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      .then((rawPayload: any) => {
        const payload: ListPayload =
          rawPayload && (rawPayload.results || rawPayload.metrics)
            ? rawPayload
            : rawPayload?.list || rawPayload
        if (aborted) return
        setItems((prev) => prev.concat(payload.results.map(normalizeItemKeys)))
        setHasMore(Boolean(payload.meta?.hasMore))
        setPage(next)
      })
      .catch((err) => {
        if (!aborted) console.error(err)
      })
      .finally(() => {
        if (!aborted) setLoading(false)
      })
    return () => {
      aborted = true
    }
  }, [
    endpoint,
    query,
    extras,
    page,
    initialLimit,
    debouncedSearch,
    sort.key,
    sort.direction,
  ])

  const handleClose = useCallback(() => {
    onOpenChange(false)
    setSearch("")
    setDebouncedSearch("")
    setItems([])
    setPage(1)
    setHasMore(false)
  }, [onOpenChange])

  const onDialogKeyDown = useCallback(
    (event: ReactKeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onOpenChange(false)
      }
    },
    [onOpenChange]
  )

  // Backend sorting - toggle sort triggers a re-fetch via useEffect
  const toggleSort = useCallback((key: SortState["key"]) => {
    setSort((current) => {
      if (current.key === key) {
        return { key, direction: current.direction === "asc" ? "desc" : "asc" }
      }
      // Default to desc for metrics, asc for name
      return { key, direction: key === "name" ? "asc" : "desc" }
    })
  }, [])

  if (!mounted || !open) return null
  // Ensure result item keys follow our camelCase convention
  function normalizeItemKeys(item: ListItem): ListItem {
    const out: Record<string, ListItem[keyof ListItem]> = { ...item }
    for (const key of Object.keys(item)) {
      if (key.includes("_")) {
        const camel = key.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
        if (typeof out[camel] === "undefined") {
          out[camel] = item[key]
        }
      }
    }
    return out as ListItem
  }

  return createPortal(
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center bg-background/80 backdrop-blur-xs sm:items-start sm:p-4 sm:pt-10 md:pt-12 lg:pt-16"
      onClick={handleClose}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
        className="relative mx-auto flex h-full w-full flex-col bg-card shadow-xl outline-hidden sm:h-[84vh] sm:max-h-[84vh] sm:max-w-6xl sm:rounded-xl sm:border sm:border-border"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={onDialogKeyDown}
      >
        <header className="shrink-0 border-b border-border px-4 py-3 sm:px-6 sm:py-4 md:px-8 md:py-5">
          <div className="flex items-center justify-between gap-3">
            <h2 className="min-w-0 truncate text-lg font-semibold text-foreground sm:text-xl">
              {title}
            </h2>
            <div className="flex shrink-0 items-center gap-2">
              <Input
                ref={inputRef}
                placeholder="Search…"
                value={search}
                onChange={handleSearchChange}
                className="hidden h-9 w-56 sm:block"
              />
              <Button
                variant="ghost"
                size="icon"
                onClick={handleClose}
                aria-label="Close details dialog"
                className="size-8 sm:size-9"
              >
                <X className="size-4 sm:size-5" />
              </Button>
            </div>
          </div>
          <Input
            placeholder="Search…"
            value={search}
            onChange={handleSearchChange}
            className="mt-2 h-9 w-full sm:hidden"
          />
        </header>

        <div className="flex-1 overflow-y-auto">
          <div className="overflow-x-auto">
            <table
              className="w-full table-fixed"
              style={{ minWidth: metrics.length * 100 + 240 }}
            >
              <colgroup>
                <col className="w-[40%] sm:w-[45%]" />
                {metrics.map((metric) => (
                  <col key={metric} style={{ width: 100 }} />
                ))}
              </colgroup>
              <thead className="sticky top-0 z-10 bg-background/95 backdrop-blur-xs">
                <tr className="border-b border-border">
                  <th className="px-4 py-2.5 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase sm:px-6 sm:py-3">
                    {sortable ? (
                      <button
                        type="button"
                        className="inline-flex items-center gap-1 text-left"
                        onClick={() => toggleSort("name")}
                      >
                        {firstColumnLabel}
                        <SortArrow
                          active={sort.key === "name"}
                          direction={sort.direction}
                        />
                      </button>
                    ) : (
                      firstColumnLabel
                    )}
                  </th>
                  {metrics.map((metric) => (
                    <th
                      key={metric}
                      className="px-3 py-2.5 text-right text-xs font-semibold tracking-wide whitespace-nowrap text-muted-foreground uppercase sm:px-6 sm:py-3"
                    >
                      {sortable ? (
                        <button
                          type="button"
                          className="inline-flex w-full items-center justify-end gap-1"
                          onClick={() => toggleSort(metric as SortState["key"])}
                        >
                          {metricLabels[metric] ??
                            METRIC_LABELS[metric] ??
                            metric}
                          <SortArrow
                            active={sort.key === metric}
                            direction={sort.direction}
                          />
                        </button>
                      ) : (
                        <span>
                          {metricLabels[metric] ??
                            METRIC_LABELS[metric] ??
                            metric}
                        </span>
                      )}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-border bg-card text-sm">
                {items.map((item) => {
                  const isPath = isPathLike(item.name)
                  const externalHref = getExternalLinkUrl
                    ? getExternalLinkUrl(item)
                    : isPath
                      ? String(item.name)
                      : null

                  return (
                    <tr
                      key={item.name}
                      className={`group transition hover:bg-accent ${onRowClick ? "cursor-pointer" : ""}`}
                      onClick={() => onRowClick?.(item)}
                    >
                      <td className="overflow-hidden px-4 py-2.5 sm:px-6 sm:py-3">
                        <div className="flex items-center gap-2">
                          {renderLeading
                            ? renderLeading(item)
                            : renderFlag(item)}
                          <span
                            className="min-w-0 flex-1 truncate font-medium text-foreground"
                            title={String(item.name)}
                          >
                            {item.name}
                          </span>
                          {externalHref ? (
                            <a
                              href={externalHref}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="shrink-0 text-muted-foreground hover:text-foreground"
                              onClick={(e) => e.stopPropagation()}
                              title={String(item.name)}
                            >
                              <ExternalLink className="size-3.5" />
                            </a>
                          ) : null}
                        </div>
                      </td>
                      {metrics.map((metric) => (
                        <td
                          key={metric}
                          className="px-3 py-2.5 text-right whitespace-nowrap sm:px-6 sm:py-3"
                        >
                          <span className="text-foreground tabular-nums">
                            {formatCell(metric, item[metric])}
                          </span>
                        </td>
                      ))}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>

        <footer className="flex shrink-0 items-center justify-between border-t border-border px-4 py-2.5 text-sm sm:px-6 sm:py-3 md:px-8 md:py-4">
          <div className="text-muted-foreground">
            {loading
              ? "Loading…"
              : hasMore
                ? "Scroll for more or click Load More"
                : "End of results"}
          </div>
          {hasMore ? (
            <Button onClick={loadMore} disabled={loading} variant="secondary">
              Load More
            </Button>
          ) : null}
        </footer>
      </div>
    </div>,
    document.body
  )
}

function SortArrow({
  active,
  direction,
}: {
  active: boolean
  direction: "asc" | "desc"
}) {
  if (!active) return <span className="text-[11px]/3 text-transparent">▼</span>
  return (
    <span className="text-[11px]/3 text-muted-foreground">
      {direction === "asc" ? "▲" : "▼"}
    </span>
  )
}

function formatCell(metric: string, value: unknown) {
  const formatter = FORMATTERS[metric as ListMetricKey]
  return formatter
    ? formatter(value as number | null | undefined)
    : String(value ?? 0)
}
