import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react"
import { createPortal } from "react-dom"
import { X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

import { fetchListPage } from "../api"
import { useDebounce } from "../hooks/use-debounce"
import { lockBodyScroll } from "../lib/body-scroll-lock"
import { useQueryContext } from "../query-context"
import type {
  AnalyticsQuery,
  ListItem,
  ListMetricKey,
  ListPayload,
} from "../types"
import { FORMATTERS, METRIC_LABELS, renderFlag } from "./list-table"

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

  function normalizeMetricKey(k: string): string {
    if (k.includes("_")) {
      return k.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
    }
    return k
  }

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
      className="fixed inset-0 z-[60] flex items-start justify-center bg-background/80 p-4 pt-10 backdrop-blur-sm sm:pt-10 md:pt-12 lg:pt-16"
      onClick={handleClose}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
        className="relative mx-auto flex h-[84vh] max-h-[84vh] w-full max-w-6xl flex-col rounded-xl border border-border bg-card shadow-xl outline-none"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={onDialogKeyDown}
      >
        <header className="flex flex-col gap-2 border-b border-border px-6 py-4 sm:flex-row sm:items-center sm:justify-between md:px-8 md:py-5">
          <div>
            <h2 className="text-xl font-semibold text-foreground">{title}</h2>
          </div>
          <div className="flex w-full items-center gap-3 sm:w-auto">
            <Input
              ref={inputRef}
              placeholder="Press / to search"
              value={search}
              onChange={handleSearchChange}
              className="h-9 w-full sm:w-56"
            />
            <Button
              variant="ghost"
              size="icon"
              onClick={handleClose}
              aria-label="Close details dialog"
            >
              <X className="size-5" />
            </Button>
          </div>
        </header>

        <div className="flex-1 overflow-y-auto p-0 md:p-0">
          <table className="min-w-full table-fixed">
            <thead className="sticky top-0 z-10 bg-background/95">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                  {sortable ? (
                    <button
                      type="button"
                      className="flex items-center gap-1 text-left"
                      onClick={() => toggleSort("name")}
                    >
                      {firstColumnLabel}
                      <span className="text-[11px] leading-none text-muted-foreground">
                        {sort.key === "name"
                          ? sort.direction === "asc"
                            ? "▲"
                            : "▼"
                          : ""}
                      </span>
                    </button>
                  ) : (
                    <span className="flex items-center gap-1 text-left">
                      {firstColumnLabel}
                    </span>
                  )}
                </th>
                {metrics.map((metric) => (
                  <th
                    key={metric}
                    className="px-6 py-3 text-right text-xs font-semibold tracking-wide text-muted-foreground uppercase"
                  >
                    {sortable ? (
                      <button
                        type="button"
                        className="flex w-full items-center justify-end gap-1"
                        onClick={() => toggleSort(metric as SortState["key"])}
                      >
                        {metricLabels[metric] ??
                          METRIC_LABELS[metric] ??
                          metric}
                        <span className="text-[11px] leading-none text-muted-foreground">
                          {sort.key === metric
                            ? sort.direction === "asc"
                              ? "▲"
                              : "▼"
                            : ""}
                        </span>
                      </button>
                    ) : (
                      <span className="flex w-full items-center justify-end gap-1">
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
              {items.map((item) => (
                <tr
                  key={item.name}
                  className={`transition hover:bg-accent ${onRowClick ? "cursor-pointer" : ""}`}
                  onClick={() => onRowClick?.(item)}
                >
                  <td className="px-6 py-3">
                    <div className="flex items-center gap-2">
                      {renderLeading ? renderLeading(item) : renderFlag(item)}
                      {getExternalLinkUrl ? (
                        (() => {
                          const href = getExternalLinkUrl(item)
                          return href ? (
                            <a
                              href={href}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="font-medium break-all whitespace-normal text-foreground underline decoration-muted-foreground/30 hover:decoration-foreground/50"
                            >
                              {item.name}
                            </a>
                          ) : (
                            <span className="font-medium text-foreground">
                              {item.name}
                            </span>
                          )
                        })()
                      ) : (
                        <span className="font-medium text-foreground">
                          {item.name}
                        </span>
                      )}
                    </div>
                  </td>
                  {metrics.map((metric) => (
                    <td key={metric} className="px-6 py-3 text-right">
                      <span className="text-foreground tabular-nums">
                        {formatCell(metric, item[metric])}
                      </span>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <footer className="flex shrink-0 items-center justify-between border-t border-border px-6 py-3 text-sm md:px-8 md:py-4">
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

function formatCell(metric: string, value: unknown) {
  const formatter = FORMATTERS[metric as ListMetricKey]
  return formatter
    ? formatter(value as number | null | undefined)
    : String(value ?? 0)
}
