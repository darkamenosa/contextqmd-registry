import { useCallback, useEffect, useRef, useState } from "react"
import type React from "react"
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

function PageRow({
  page,
  libraryId,
  versionId,
}: {
  page: AdminPage
  libraryId: number
  versionId: number
}) {
  const [deleteConfirm, setDeleteConfirm] = useState(false)

  function handleDelete() {
    router.delete(
      `/admin/libraries/${libraryId}/versions/${versionId}/pages/${page.id}`,
      {
        preserveScroll: true,
      }
    )
  }

  return (
    <TableRow>
      <TableCell className="pl-4">
        <Link
          href={`/admin/libraries/${libraryId}/versions/${versionId}/pages/${page.id}`}
          className="text-sm font-medium hover:underline"
        >
          {page.title}
        </Link>
      </TableCell>
      <TableCell className="hidden font-mono text-xs text-muted-foreground sm:table-cell">
        {page.path}
      </TableCell>
      <TableCell className="hidden text-right text-sm text-muted-foreground sm:table-cell">
        {formatBytes(page.bytes)}
      </TableCell>
      <TableCell className="pr-4 text-right">
        <div className="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            nativeButton={false}
            render={
              <Link
                href={`/admin/libraries/${libraryId}/versions/${versionId}/pages/${page.id}`}
              />
            }
            title="View page"
          >
            <Eye className="size-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            nativeButton={false}
            render={
              <Link
                href={`/admin/libraries/${libraryId}/versions/${versionId}/pages/${page.id}/edit`}
              />
            }
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
        `/admin/libraries/${library.id}/versions/${version.id}/pages`,
        { ...params },
        { preserveState: true, preserveScroll: true }
      )
    },
    [library.id, version.id]
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

  function handleSearch(e: React.FormEvent) {
    e.preventDefault()
    navigate({ query, page: 1 })
  }

  return (
    <AdminLayout>
      <Head title={`Pages — ${version.version} — ${library.displayName}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex min-w-0 items-center gap-2.5">
            <Link
              href={`/admin/libraries/${library.id}`}
              aria-label="Back to library"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <div className="min-w-0">
              <h1 className="truncate text-lg font-semibold">
                {library.displayName}
              </h1>
              <div className="mt-1 flex flex-wrap gap-2">
                <Badge variant="outline">{version.version}</Badge>
                <Badge variant="secondary">{version.channel}</Badge>
              </div>
            </div>
          </div>
          <span className="text-sm text-muted-foreground">
            {pagination.total} page{pagination.total !== 1 ? "s" : ""}
          </span>
        </div>

        {/* Search */}
        <form
          onSubmit={handleSearch}
          className="flex w-full max-w-md flex-col gap-2 sm:flex-row"
        >
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
              className="w-full sm:w-auto"
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
          <div className="rounded-lg border">
            <div className="divide-y sm:hidden">
              {pages.map((page) => (
                <article key={page.id} className="space-y-3 px-4 py-4">
                  <div>
                    <Link
                      href={`/admin/libraries/${library.id}/versions/${version.id}/pages/${page.id}`}
                      className="font-medium hover:underline"
                    >
                      {page.title}
                    </Link>
                    <p className="mt-1 font-mono text-xs text-muted-foreground">
                      {page.path}
                    </p>
                  </div>
                  <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
                    <span>{formatBytes(page.bytes)}</span>
                    <div className="flex gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        nativeButton={false}
                        render={
                          <Link
                            href={`/admin/libraries/${library.id}/versions/${version.id}/pages/${page.id}`}
                          />
                        }
                      >
                        <Eye className="size-3.5" />
                        View
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        nativeButton={false}
                        render={
                          <Link
                            href={`/admin/libraries/${library.id}/versions/${version.id}/pages/${page.id}/edit`}
                          />
                        }
                      >
                        <Pencil className="size-3.5" />
                        Edit
                      </Button>
                    </div>
                  </div>
                </article>
              ))}
            </div>

            <div className="hidden overflow-x-auto sm:block">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="pl-4">Title</TableHead>
                    <TableHead className="hidden sm:table-cell">Path</TableHead>
                    <TableHead className="hidden text-right sm:table-cell">
                      Size
                    </TableHead>
                    <TableHead className="w-28 pr-4 text-right">
                      Actions
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {pages.map((page) => (
                    <PageRow
                      key={page.id}
                      page={page}
                      libraryId={library.id}
                      versionId={version.id}
                    />
                  ))}
                </TableBody>
              </Table>
            </div>
          </div>
        )}

        {/* Pagination */}
        {pagination.pages > 1 && (
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <span className="text-sm text-muted-foreground">
              {pagination.from}–{pagination.to} of {pagination.total}
            </span>
            <div className="flex w-full gap-2 sm:w-auto sm:gap-1">
              <Button
                variant="outline"
                size="sm"
                className="flex-1 sm:flex-none"
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
                className="flex-1 sm:flex-none"
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
