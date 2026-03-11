import { useCallback, useEffect, useRef, useState, type FormEvent } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminPage, PaginationData } from "@/types"
import { ChevronLeft, Eye, Pencil, Search, Trash2, X } from "lucide-react"

import { formatBytes } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import AdminLayout from "@/layouts/admin-layout"

interface LibrarySummary {
  id: number
  displayName: string
  namespace: string
  name: string
}

interface VersionSummary {
  id: number
  version: string
  channel: string
}

interface Props {
  library: LibrarySummary
  version: VersionSummary
  pages: AdminPage[]
  pagination: PaginationData
  query: string
}

function PageRow({ page }: { page: AdminPage }) {
  const [deleteConfirm, setDeleteConfirm] = useState(false)

  function handleDelete() {
    router.delete(`/admin/pages/${page.id}`, {
      preserveScroll: true,
    })
  }

  return (
    <TableRow>
      <TableCell>
        <Link
          href={`/admin/pages/${page.id}`}
          className="text-sm font-medium hover:underline"
        >
          {page.title}
        </Link>
      </TableCell>
      <TableCell className="font-mono text-xs text-muted-foreground">
        {page.path}
      </TableCell>
      <TableCell className="text-right text-sm text-muted-foreground">
        {formatBytes(page.bytes)}
      </TableCell>
      <TableCell className="text-right">
        <div className="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            nativeButton={false}
            render={<Link href={`/admin/pages/${page.id}`} />}
            title="View page"
          >
            <Eye className="size-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            nativeButton={false}
            render={<Link href={`/admin/pages/${page.id}/edit`} />}
            title="Edit page"
          >
            <Pencil className="size-3.5" />
          </Button>
          {deleteConfirm ? (
            <div className="flex items-center gap-1">
              <Button
                variant="destructive"
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={handleDelete}
              >
                Confirm
              </Button>
              <Button
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={() => setDeleteConfirm(false)}
              >
                No
              </Button>
            </div>
          ) : (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 w-7 p-0 text-muted-foreground hover:text-destructive"
              onClick={() => setDeleteConfirm(true)}
              title="Delete page"
            >
              <Trash2 className="size-3.5" />
            </Button>
          )}
        </div>
      </TableCell>
    </TableRow>
  )
}

export default function AdminVersionPagesIndex({
  library,
  version,
  pages,
  pagination,
  query: initialQuery,
}: Props) {
  const [query, setQuery] = useState(initialQuery)
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined)

  const navigate = useCallback(
    (params: Record<string, string | number>) => {
      router.get(
        `/admin/versions/${version.id}/pages`,
        { ...params },
        { preserveState: true, preserveScroll: true }
      )
    },
    [version.id]
  )

  // Debounced search
  useEffect(() => {
    if (query === initialQuery) return
    clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      navigate({ query, page: 1 })
    }, 300)
    return () => clearTimeout(debounceRef.current)
  }, [query, initialQuery, navigate])

  function handleSearch(e: FormEvent) {
    e.preventDefault()
    navigate({ query, page: 1 })
  }

  return (
    <AdminLayout>
      <Head title={`Pages — ${version.version} — ${library.displayName}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <Link
              href={`/admin/libraries/${library.id}`}
              aria-label="Back to library"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <h1 className="text-lg font-semibold">{library.displayName}</h1>
            <Badge variant="outline">{version.version}</Badge>
            <Badge variant="secondary">{version.channel}</Badge>
          </div>
          <span className="text-sm text-muted-foreground">
            {pagination.total} page{pagination.total !== 1 ? "s" : ""}
          </span>
        </div>

        {/* Search */}
        <form onSubmit={handleSearch} className="flex max-w-md gap-2">
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              type="text"
              placeholder="Search by title, content, or path..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="pl-9"
            />
          </div>
          {initialQuery && (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                setQuery("")
                navigate({ query: "", page: 1 })
              }}
            >
              <X className="size-4" />
              Clear
            </Button>
          )}
        </form>

        {/* Table */}
        {pages.length === 0 ? (
          <div className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">
            {initialQuery
              ? `No pages match "${initialQuery}".`
              : "No pages in this version."}
          </div>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Title</TableHead>
                  <TableHead>Path</TableHead>
                  <TableHead className="text-right">Size</TableHead>
                  <TableHead className="w-28 text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {pages.map((page) => (
                  <PageRow key={page.id} page={page} />
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {/* Pagination */}
        {pagination.pages > 1 && (
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">
              {pagination.from}–{pagination.to} of {pagination.total}
            </span>
            <div className="flex gap-1">
              <Button
                variant="outline"
                size="sm"
                disabled={!pagination.hasPrevious}
                onClick={() =>
                  navigate({ query: initialQuery, page: pagination.page - 1 })
                }
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={!pagination.hasNext}
                onClick={() =>
                  navigate({ query: initialQuery, page: pagination.page + 1 })
                }
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </div>
    </AdminLayout>
  )
}
