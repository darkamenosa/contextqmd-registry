import { useCallback, useEffect, useRef, useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminCustomer, PaginationData } from "@/types"

import { formatDateShort } from "@/lib/format-date"
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

interface Counts {
  all: number
  active: number
  cancelled: number
  suspended: number
}

interface Filters {
  status: string
  query: string
  sort: string
  direction: string
}

interface Props {
  customers: AdminCustomer[]
  pagination: PaginationData
  counts: Counts
  filters: Filters
}

function buildParams(filters: Filters, page?: number) {
  const params: Record<string, string> = {}
  if (filters.status && filters.status !== "all") params.status = filters.status
  if (filters.query) params.query = filters.query
  if (filters.sort && filters.sort !== "created_at") params.sort = filters.sort
  if (filters.direction && filters.direction !== "desc")
    params.direction = filters.direction
  if (page && page > 1) params.page = String(page)
  return params
}

const STATUS_TABS = ["all", "active", "cancelled", "suspended"]

export default function AdminCustomersIndex({
  customers,
  pagination,
  counts,
  filters,
}: Props) {
  const [query, setQuery] = useState(filters.query)
  const [bulkDialog, setBulkDialog] = useState<{
    action: string
    ids: (string | number)[]
  } | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined
  )
  const { mode, setMode } = useSetIndexFiltersMode("default")

  const tabs = [
    { id: "all", label: `All (${counts.all})` },
    { id: "active", label: `Active (${counts.active})` },
    { id: "cancelled", label: `Cancelled (${counts.cancelled})` },
    { id: "suspended", label: `Suspended (${counts.suspended})` },
  ]

  const selectedTabIndex = Math.max(STATUS_TABS.indexOf(filters.status), 0)

  const navigate = useCallback(
    (overrides: Partial<Filters>, page?: number) => {
      const merged = { ...filters, ...overrides }
      router.get("/admin/customers", buildParams(merged, page), {
        preserveState: true,
        preserveScroll: true,
      })
    },
    [filters]
  )

  // Debounced search
  useEffect(() => {
    if (query === filters.query) return
    clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      navigate({ query, status: filters.status })
    }, 300)
    return () => clearTimeout(debounceRef.current)
  }, [query, filters.query, filters.status, navigate])

  const handleTabChange = (index: number) => {
    const tabId = STATUS_TABS[index] ?? "all"
    navigate({ status: tabId, query: "" })
    setQuery("")
  }

  const handleBulkAction = (action: string, ids: (string | number)[]) => {
    setBulkDialog({ action, ids })
  }

  const executeBulkAction = () => {
    if (!bulkDialog) return
    const { action, ids } = bulkDialog

    if (action === "suspend") {
      router.post(
        "/admin/customers/bulk_suspension",
        { ids },
        { preserveState: false }
      )
    } else if (action === "reactivate") {
      router.delete("/admin/customers/bulk_suspension", {
        data: { ids },
        preserveState: false,
      })
    }

    setBulkDialog(null)
  }

  const columns: IndexTableColumn[] = [
    { id: "email", label: "Customer", sortable: true },
    { id: "auth_method", label: "Auth" },
    { id: "staff", label: "Staff" },
    { id: "status", label: "Login" },
    { id: "accounts_count", label: "Accounts" },
    { id: "created_at", label: "Joined", sortable: true },
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

  return (
    <AdminLayout>
      <Head title="Customers" />
      <div className="flex flex-col gap-4">
        <div className="rounded-lg border border-border bg-card">
          <IndexFilters
            tabs={tabs}
            selected={selectedTabIndex}
            onSelect={handleTabChange}
            queryValue={query}
            onQueryChange={setQuery}
            onQueryClear={() => {
              setQuery("")
              navigate({ query: "" })
            }}
            queryPlaceholder="Search customers..."
            mode={mode}
            setMode={setMode}
          />
          <IndexTable
            items={customers}
            columns={columns}
            itemId={(customer) => customer.id}
            renderRow={(customer) => [
              <Link
                key="customer"
                href={`/admin/customers/${customer.id}`}
                className="group block"
              >
                <span className="font-medium group-hover:underline">
                  {customer.name || "\u2014"}
                </span>
                <span className="block text-xs text-muted-foreground">
                  {customer.email}
                </span>
              </Link>,
              customer.authMethod,
              customer.staff ? (
                <Badge key="staff" variant="secondary">
                  Staff
                </Badge>
              ) : null,
              <StatusBadge key="status" status={customer.status} />,
              customer.accountsCount,
              formatDateShort(customer.createdAt),
            ]}
            sort={sort}
            pagination={paginationProps}
            bulkActions={[
              {
                key: "suspend",
                label: "Suspend",
                onAction: (ids) => handleBulkAction("suspend", ids),
              },
              {
                key: "reactivate",
                label: "Unsuspend",
                onAction: (ids) => handleBulkAction("reactivate", ids),
              },
            ]}
            emptyState={
              <div>
                <p className="text-muted-foreground">No customers found</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {filters.query
                    ? "Try a different search term."
                    : filters.status !== "all"
                      ? "No customers match this filter."
                      : "Customers will appear here once they sign up."}
                </p>
              </div>
            }
          />
        </div>
      </div>

      {/* Bulk action confirmation dialog */}
      <Dialog
        open={bulkDialog !== null}
        onOpenChange={(open) => !open && setBulkDialog(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {bulkDialog?.action === "suspend"
                ? "Suspend customers?"
                : "Unsuspend customers?"}
            </DialogTitle>
            <DialogDescription>
              {bulkDialog?.action === "suspend"
                ? `This will suspend ${bulkDialog?.ids.length} customer(s). They will not be able to sign in.`
                : `This will restore sign-in access for ${bulkDialog?.ids.length} suspended customer(s).`}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBulkDialog(null)}>
              Cancel
            </Button>
            <Button onClick={executeBulkAction}>
              {bulkDialog?.action === "suspend"
                ? "Yes, suspend"
                : "Yes, unsuspend"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  )
}
