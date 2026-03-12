import { Head, Link } from "@inertiajs/react"
import { ChevronLeft, ExternalLink, FileText, Hash, Pencil } from "lucide-react"

import { formatBytes, formatDateTime } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import AdminLayout from "@/layouts/admin-layout"

interface PageDetail {
  id: number
  pageUid: string
  path: string
  title: string
  url: string | null
  content: string
  bytes: number
  checksum: string | null
  sourceRef: string | null
  headings: string[]
  createdAt: string
  updatedAt: string
}

interface Props {
  page: PageDetail
  version: { id: number; version: string }
  library: {
    id: number
    displayName: string
    namespace: string
    name: string
  }
}

export default function AdminPageShow({ page, version, library }: Props) {
  return (
    <AdminLayout>
      <Head title={`${page.title} — ${library.displayName}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <Link
              href={`/admin/versions/${version.id}/pages`}
              aria-label="Back to pages"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <div className="min-w-0 flex-1">
              <h1 className="truncate text-lg font-semibold">{page.title}</h1>
              <p className="text-sm text-muted-foreground">
                {library.displayName} / {version.version} / {page.path}
              </p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            nativeButton={false}
            render={<Link href={`/admin/pages/${page.id}/edit`} />}
          >
            <Pencil className="size-4" />
            Edit
          </Button>
        </div>

        {/* Main + sidebar grid */}
        <div className="grid items-start gap-4 lg:grid-cols-5">
          {/* Content */}
          <div className="flex flex-col gap-4 lg:col-span-3">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <FileText className="size-4 text-muted-foreground" />
                  Content
                </CardTitle>
              </CardHeader>
              <CardContent>
                <pre className="max-h-[600px] overflow-auto rounded-md border bg-muted/30 p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap">
                  {page.content || (
                    <span className="text-muted-foreground">No content</span>
                  )}
                </pre>
              </CardContent>
            </Card>
          </div>

          {/* Sidebar */}
          <div className="flex flex-col gap-4 lg:col-span-2">
            {/* Metadata */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Details</CardTitle>
              </CardHeader>
              <CardContent>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                  <div className="col-span-2">
                    <dt className="text-muted-foreground">Page UID</dt>
                    <dd className="mt-0.5 font-mono text-xs">{page.pageUid}</dd>
                  </div>
                  <div className="col-span-2">
                    <dt className="text-muted-foreground">Path</dt>
                    <dd className="mt-0.5 font-mono text-xs">{page.path}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Size</dt>
                    <dd className="mt-0.5 font-medium">
                      {formatBytes(page.bytes)}
                    </dd>
                  </div>
                  {page.sourceRef && (
                    <div>
                      <dt className="text-muted-foreground">Source</dt>
                      <dd className="mt-0.5">
                        <Badge variant="outline" className="text-xs">
                          {page.sourceRef}
                        </Badge>
                      </dd>
                    </div>
                  )}
                  {page.url && (
                    <div className="col-span-2">
                      <dt className="text-muted-foreground">URL</dt>
                      <dd className="mt-0.5">
                        <a
                          href={page.url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-xs hover:underline"
                        >
                          <span className="max-w-[200px] truncate">
                            {page.url}
                          </span>
                          <ExternalLink className="size-3 shrink-0" />
                        </a>
                      </dd>
                    </div>
                  )}
                  {page.checksum && (
                    <div className="col-span-2">
                      <dt className="text-muted-foreground">Checksum</dt>
                      <dd className="mt-0.5 font-mono text-[11px] text-muted-foreground">
                        {page.checksum.slice(0, 12)}...
                      </dd>
                    </div>
                  )}
                  <div>
                    <dt className="text-muted-foreground">Created</dt>
                    <dd className="mt-0.5">{formatDateTime(page.createdAt)}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Updated</dt>
                    <dd className="mt-0.5">{formatDateTime(page.updatedAt)}</dd>
                  </div>
                </dl>
              </CardContent>
            </Card>

            {/* Headings */}
            {page.headings.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Hash className="size-4 text-muted-foreground" />
                    Headings
                    <Badge
                      variant="secondary"
                      className="ml-auto text-[10px] tabular-nums"
                    >
                      {page.headings.length}
                    </Badge>
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <ul className="space-y-1">
                    {page.headings.map((heading, i) => (
                      <li
                        key={i}
                        className="truncate text-xs text-muted-foreground"
                      >
                        {heading}
                      </li>
                    ))}
                  </ul>
                </CardContent>
              </Card>
            )}
          </div>
        </div>
      </div>
    </AdminLayout>
  )
}
