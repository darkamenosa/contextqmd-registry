import { useCallback, useEffect, useRef, useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminProxyConfig, PaginationData } from "@/types"
import { Plus } from "lucide-react"

import { formatTimeAgo } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
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
import AdminLayout from "@/layouts/admin-layout"

interface Filters {
  query: string
  tab: string
  sort: string
  direction: string
}

interface Props {
  proxyConfigs: AdminProxyConfig[]
  pagination: PaginationData
  totalCount: number
  activeCount: number
  filters: Filters
}

function buildParams(filters: Filters, page?: number) {
  const params: Record<string, string> = {}
  if (filters.query) params.query = filters.query
  if (filters.tab && filters.tab !== "all") params.tab = filters.tab
  if (filters.sort && filters.sort !== "priority") params.sort = filters.sort
  if (filters.direction && filters.direction !== "desc")
    params.direction = filters.direction
  if (page && page > 1) params.page = String(page)
  return params
}

function ProxyHealthIndicator({ config }: { config: AdminProxyConfig }) {
  if (!config.active) {
    return <StatusBadge status="inactive" />
  }
  if (config.cooldownUntil && new Date(config.cooldownUntil) > new Date()) {
    return <StatusBadge status="suspended">Cooldown</StatusBadge>
  }
  if (config.consecutiveFailures > 0) {
    return (
      <StatusBadge status="pending">
        {config.consecutiveFailures} fail
        {config.consecutiveFailures !== 1 && "s"}
      </StatusBadge>
    )
  }
  return <StatusBadge status="active" />
}

function CapacityBar({ active, max }: { active: number; max: number }) {
  const pct = max > 0 ? Math.min((active / max) * 100, 100) : 0
  const color =
    pct >= 90 ? "bg-red-500" : pct >= 60 ? "bg-amber-500" : "bg-emerald-500"

  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 w-16 overflow-hidden rounded-full bg-muted">
        <div
          className={`h-full rounded-full transition-all ${color}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="font-mono text-xs text-muted-foreground">
        {active}/{max}
      </span>
    </div>
  )
}

export default function AdminProxyConfigsIndex({
  proxyConfigs,
  pagination,
  totalCount,
  activeCount,
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
    { id: "all", label: `All (${totalCount})` },
    { id: "active", label: `Active (${activeCount})` },
    { id: "inactive", label: `Inactive (${totalCount - activeCount})` },
  ]

  const selectedTab = tabs.findIndex((t) => t.id === filters.tab)

  const navigate = useCallback(
    (overrides: Partial<Filters>, page?: number) => {
      const merged = { ...filters, ...overrides }
      router.get("/admin/proxy_configs", buildParams(merged, page), {
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
    { id: "name", label: "Proxy", sortable: true },
    { id: "host", label: "Endpoint", sortable: true },
    { id: "kind", label: "Type" },
    { id: "usage_scope", label: "Scope" },
    { id: "priority", label: "Priority", sortable: true, align: "end" },
    { id: "health", label: "Health" },
    { id: "capacity", label: "Capacity", align: "end" },
    { id: "last_activity", label: "Last Activity", align: "end" },
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
      router.delete(`/admin/proxy_configs/${id}`, { preserveState: false })
    }
    setBulkDialog(null)
  }

  return (
    <AdminLayout>
      <Head title="Proxy Pool" />
      <div className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-semibold">Proxy Pool</h1>
          <Button
            size="sm"
            nativeButton={false}
            render={<Link href="/admin/proxy_configs/new" />}
          >
            <Plus className="size-4" />
            Add Proxy
          </Button>
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
            queryPlaceholder="Search proxies..."
            mode={mode}
            setMode={setMode}
          />
          <IndexTable
            items={proxyConfigs}
            columns={columns}
            itemId={(c) => c.id}
            renderRow={(c) => [
              <Link
                key="name"
                href={`/admin/proxy_configs/${c.id}`}
                className="group block"
              >
                <span className="font-medium group-hover:underline">
                  {c.name}
                </span>
                {c.provider && (
                  <span className="ml-2 text-xs text-muted-foreground">
                    {c.provider}
                  </span>
                )}
              </Link>,
              <span
                key="endpoint"
                className="font-mono text-xs text-muted-foreground"
              >
                {c.scheme}://{c.host}:{c.port}
              </span>,
              c.kind ? (
                <Badge
                  key="kind"
                  variant="outline"
                  className="text-xs capitalize"
                >
                  {c.kind}
                </Badge>
              ) : (
                <span key="kind" className="text-xs text-muted-foreground">
                  —
                </span>
              ),
              <Badge key="scope" variant="secondary" className="text-xs">
                {c.usageScope}
              </Badge>,
              <span key="priority" className="font-mono text-xs">
                {c.priority}
              </span>,
              <ProxyHealthIndicator key="health" config={c} />,
              <CapacityBar
                key="capacity"
                active={c.activeLeaseCount}
                max={c.maxConcurrency}
              />,
              <span
                key="last_activity"
                className="text-xs text-muted-foreground"
              >
                {c.lastSuccessAt
                  ? formatTimeAgo(c.lastSuccessAt, true)
                  : "Never"}
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
                <p className="text-muted-foreground">No proxies configured</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {filters.query
                    ? "Try a different search term."
                    : "Add a proxy to start routing crawl requests."}
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
            <DialogTitle>Delete proxies?</DialogTitle>
            <DialogDescription>
              This will permanently delete {bulkDialog?.ids.length} proxy
              config(s) and all their lease history. This cannot be undone.
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
