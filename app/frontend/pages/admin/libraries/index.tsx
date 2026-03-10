import { useCallback, useEffect, useRef, useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminLibrary, PaginationData } from "@/types"

import { formatDateShort } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import {
  IndexFilters,
  IndexTable,
  type IndexTableColumn,
  type IndexTablePagination,
  type IndexTableSort,
} from "@/components/admin/ui/index-table"
import { useSetIndexFiltersMode } from "@/components/admin/ui/use-index-filters-mode"
import AdminLayout from "@/layouts/admin-layout"

interface Filters {
  query: string
  sort: string
  direction: string
}

interface Props {
  libraries: AdminLibrary[]
  pagination: PaginationData
  totalCount: number
  filters: Filters
}

function buildParams(filters: Filters, page?: number) {
  const params: Record<string, string> = {}
  if (filters.query) params.query = filters.query
  if (filters.sort && filters.sort !== "updated_at") params.sort = filters.sort
  if (filters.direction && filters.direction !== "desc")
    params.direction = filters.direction
  if (page && page > 1) params.page = String(page)
  return params
}

export default function AdminLibrariesIndex({
  libraries,
  pagination,
  totalCount,
  filters,
}: Props) {
  const [query, setQuery] = useState(filters.query)
  const [bulkDialog, setBulkDialog] = useState<{
    ids: (string | number)[]
  } | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  )
  const { mode, setMode } = useSetIndexFiltersMode("default")

  const tabs = [{ id: "all", label: `All (${totalCount})` }]

  const navigate = useCallback(
    (overrides: Partial<Filters>, page?: number) => {
      const merged = { ...filters, ...overrides }
      router.get("/admin/libraries", buildParams(merged, page), {
        preserveState: true,
        preserveScroll: true,
      })
    },
    [filters],
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
    { id: "display_name", label: "Library", sortable: true },
    { id: "namespace", label: "Slug", sortable: true },
    { id: "account_name", label: "Account" },
    { id: "versions", label: "Versions", align: "end" },
    { id: "pages", label: "Pages", align: "end" },
    { id: "updated_at", label: "Updated", sortable: true, align: "end" },
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
    // Delete one by one (no bulk delete endpoint)
    for (const id of bulkDialog.ids) {
      router.delete(`/admin/libraries/${id}`, { preserveState: false })
    }
    setBulkDialog(null)
  }

  return (
    <AdminLayout>
      <Head title="Libraries" />
      <div className="flex flex-col gap-4">
        <div className="rounded-lg border border-border bg-card">
          <IndexFilters
            tabs={tabs}
            selected={0}
            onSelect={() => {}}
            queryValue={query}
            onQueryChange={setQuery}
            onQueryClear={() => {
              setQuery("")
              navigate({ query: "" })
            }}
            queryPlaceholder="Search libraries..."
            mode={mode}
            setMode={setMode}
          />
          <IndexTable
            items={libraries}
            columns={columns}
            itemId={(lib) => lib.id}
            renderRow={(lib) => [
              <Link
                key="name"
                href={`/admin/libraries/${lib.id}`}
                className="group block"
              >
                <span className="font-medium group-hover:underline">
                  {lib.displayName}
                </span>
                {lib.licenseStatus && (
                  <Badge variant="outline" className="ml-2 text-xs">
                    {lib.licenseStatus}
                  </Badge>
                )}
              </Link>,
              <span
                key="slug"
                className="font-mono text-xs text-muted-foreground"
              >
                {lib.namespace}/{lib.name}
              </span>,
              lib.accountName,
              lib.versionCount,
              lib.pageCount,
              formatDateShort(lib.updatedAt),
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
                <p className="text-muted-foreground">No libraries found</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {filters.query
                    ? "Try a different search term."
                    : "Libraries will appear here once docs are indexed."}
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
            <DialogTitle>Delete libraries?</DialogTitle>
            <DialogDescription>
              This will permanently delete {bulkDialog?.ids.length} library(ies)
              and all their versions, pages, and bundles. This cannot be undone.
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
