import { useCallback, useEffect, useRef, useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminCrawlRequest, PaginationData } from "@/types"
import { Loader2 } from "lucide-react"

import { formatDateTime } from "@/lib/format-date"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  IndexFilters,
  IndexTable,
  type IndexTableColumn,
  type IndexTablePagination,
  type IndexTableSort,
} from "@/components/admin/ui/index-table"
import { StatusBadge } from "@/components/admin/ui/status-badge"
import { useSetIndexFiltersMode } from "@/components/admin/ui/use-index-filters-mode"
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import AdminLayout from "@/layouts/admin-layout"

interface Filters {
  query: string
  tab: string
  sort: string
  direction: string
}

interface Counts {
  all: number
  pending: number
  processing: number
  completed: number
  failed: number
  cancelled: number
}

interface Props {
  crawlRequests: AdminCrawlRequest[]
  pagination: PaginationData
  counts: Counts
  filters: Filters
}

function buildParams(filters: Filters, page?: number) {
  const params: Record<string, string> = {}
  if (filters.query) params.query = filters.query
  if (filters.tab && filters.tab !== "all") params.tab = filters.tab
  if (filters.sort && filters.sort !== "created_at") params.sort = filters.sort
  if (filters.direction && filters.direction !== "desc")
    params.direction = filters.direction
  if (page && page > 1) params.page = String(page)
  return params
}

function truncateUrl(url: string, max = 55): string {
  try {
    const u = new URL(url)
    const display = u.host + u.pathname
    return display.length > max ? display.slice(0, max) + "..." : display
  } catch {
    return url.length > max ? url.slice(0, max) + "..." : url
  }
}

function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return "—"
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  const secs = seconds % 60
  if (minutes < 60) return `${minutes}m ${secs}s`
  const hours = Math.floor(minutes / 60)
  const mins = minutes % 60
  return `${hours}h ${mins}m`
}

export default function AdminCrawlRequestsIndex({
  crawlRequests,
  pagination,
  counts,
  filters,
}: Props) {
  const [query, setQuery] = useState(filters.query)
  const [bulkDialog, setBulkDialog] = useState<{
    ids: (string | number)[]
  } | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined
  )
  const { mode, setMode } = useSetIndexFiltersMode("default")

  const tabs = [
    { id: "all", label: `All (${counts.all})` },
    { id: "pending", label: `Pending (${counts.pending})` },
    { id: "processing", label: `Processing (${counts.processing})` },
    { id: "completed", label: `Completed (${counts.completed})` },
    { id: "failed", label: `Failed (${counts.failed})` },
    { id: "cancelled", label: `Cancelled (${counts.cancelled})` },
  ]

  const selectedTab = tabs.findIndex((t) => t.id === filters.tab)

  const navigate = useCallback(
    (overrides: Partial<Filters>, page?: number) => {
      const merged = { ...filters, ...overrides }
      router.get("/admin/crawl_requests", buildParams(merged, page), {
        preserveState: true,
        preserveScroll: true,
      })
    },
    [filters]
  )

  useEffect(() => {
    if (query === filters.query) return
    clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      navigate({ query })
    }, 300)
    return () => clearTimeout(debounceRef.current)
  }, [query, filters.query, navigate])

  const columns: IndexTableColumn[] = [
    {
      id: "url",
      label: "Request",
      sortable: true,
      headerClassName: "pl-4",
      cellClassName: "pl-4",
    },
    { id: "status", label: "Status" },
    {
      id: "library",
      label: "Library",
      headerClassName: "hidden sm:table-cell",
      cellClassName: "hidden sm:table-cell",
    },
    {
      id: "identity",
      label: "Submitter",
      headerClassName: "hidden md:table-cell",
      cellClassName: "hidden md:table-cell",
    },
    {
      id: "duration",
      label: "Duration",
      align: "end",
      headerClassName: "hidden sm:table-cell",
      cellClassName: "hidden sm:table-cell",
    },
    {
      id: "created_at",
      label: "Created",
      sortable: true,
      align: "end",
      headerClassName: "pr-4",
      cellClassName: "pr-4",
    },
  ]

  const sort: IndexTableSort = {
    columnId: filters.sort,
    direction: filters.direction as "asc" | "desc",
    onChange: (columnId, direction) => {
      navigate({ sort: columnId, direction })
    },
  }

  const paginationProps: IndexTablePagination = {
    label: `${pagination.from}–${pagination.to} of ${pagination.total}`,
    hasPrevious: pagination.hasPrevious,
    hasNext: pagination.hasNext,
    onPrevious: () => navigate({}, pagination.page - 1),
    onNext: () => navigate({}, pagination.page + 1),
  }

  const handleBulkDelete = (ids: (string | number)[]) => {
    setBulkDialog({ ids })
  }

  const executeBulkDelete = () => {
    if (!bulkDialog) return
    for (const id of bulkDialog.ids) {
      router.delete(`/admin/crawl_requests/${id}`, { preserveState: false })
    }
    setBulkDialog(null)
  }

  return (
    <AdminLayout>
      <Head title="Crawl Requests" />
      <div className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-semibold">Crawl Requests</h1>
        </div>
        <div className="rounded-lg border border-border bg-card">
          <IndexFilters
            tabs={tabs}
            selected={selectedTab >= 0 ? selectedTab : 0}
            onSelect={(idx) => {
              navigate({ tab: tabs[idx]?.id ?? "all" })
            }}
            queryValue={query}
            onQueryChange={setQuery}
            onQueryClear={() => {
              setQuery("")
              navigate({ query: "" })
            }}
            queryPlaceholder="Search by URL or error message..."
            mode={mode}
            setMode={setMode}
          />
          <IndexTable
            items={crawlRequests}
            columns={columns}
            itemId={(cr) => cr.id}
            renderRow={(cr) => [
              <Link
                key="url"
                href={`/admin/crawl_requests/${cr.id}`}
                className="group block"
              >
                <span className="inline-flex items-center gap-2">
                  <SourceTypeIcon sourceType={cr.sourceType} size="size-3.5" />
                  <span className="max-w-[320px] truncate font-medium group-hover:underline">
                    {truncateUrl(cr.url)}
                  </span>
                </span>
                {cr.status === "failed" && cr.errorMessage && (
                  <span className="mt-0.5 block max-w-[320px] truncate text-xs text-red-600 dark:text-red-400">
                    {cr.errorMessage}
                  </span>
                )}
              </Link>,
              <span key="status" className="inline-flex items-center gap-1.5">
                {cr.status === "processing" && (
                  <Loader2 className="size-3 animate-spin text-amber-500" />
                )}
                <StatusBadge status={cr.status} />
              </span>,
              cr.librarySlug ? (
                <Link
                  key="library"
                  href={`/admin/libraries/${cr.libraryId}`}
                  className="text-sm hover:underline"
                >
                  {cr.libraryDisplayName || cr.librarySlug}
                </Link>
              ) : (
                <span key="library" className="text-sm text-muted-foreground">
                  —
                </span>
              ),
              <span
                key="identity"
                className="max-w-[160px] truncate text-xs text-muted-foreground"
                title={cr.identityEmail}
              >
                {cr.identityEmail}
              </span>,
              <span
                key="duration"
                className="font-mono text-xs text-muted-foreground"
              >
                {formatDuration(cr.durationSeconds)}
              </span>,
              <span key="created_at" className="text-xs text-muted-foreground">
                {formatDateTime(cr.createdAt)}
              </span>,
            ]}
            sort={sort}
            pagination={paginationProps}
            bulkActions={[
              {
                key: "delete",
                label: "Delete",
                destructive: true,
                onAction: (ids) => handleBulkDelete(ids),
              },
            ]}
            emptyState={
              <div>
                <p className="text-muted-foreground">No crawl requests found</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {filters.query
                    ? "Try a different search term."
                    : filters.tab !== "all"
                      ? "No requests match this filter."
                      : "Crawl requests will appear here when docs are submitted."}
                </p>
              </div>
            }
          />
        </div>
      </div>

      <Dialog
        open={bulkDialog !== null}
        onOpenChange={(open) => !open && setBulkDialog(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete crawl requests?</DialogTitle>
            <DialogDescription>
              This will permanently delete {bulkDialog?.ids.length} crawl
              request(s). This cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBulkDialog(null)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={executeBulkDelete}>
              Yes, delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  )
}
