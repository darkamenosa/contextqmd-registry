import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type {
  AdminCrawlItem,
  AdminLibraryDetail,
  AdminLibraryVersion,
} from "@/types"
import {
  BookOpen,
  CheckCircle,
  ChevronLeft,
  Clock,
  ExternalLink,
  FileText,
  Layers,
  Loader2,
  Pencil,
  Trash2,
  XCircle,
} from "lucide-react"

import { formatDateShort } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import AdminLayout from "@/layouts/admin-layout"

interface Props {
  library: AdminLibraryDetail
  versions: AdminLibraryVersion[]
  crawlRequests: AdminCrawlItem[]
}

function StatusBadge({ status }: { status: string }) {
  switch (status) {
    case "pending":
      return (
        <Badge variant="outline" className="gap-1">
          <Clock className="size-3" />
          Pending
        </Badge>
      )
    case "processing":
      return (
        <Badge variant="default" className="gap-1">
          <Loader2 className="size-3 animate-spin" />
          Processing
        </Badge>
      )
    case "completed":
      return (
        <Badge variant="secondary" className="gap-1">
          <CheckCircle className="size-3" />
          Completed
        </Badge>
      )
    case "failed":
      return (
        <Badge variant="destructive" className="gap-1">
          <XCircle className="size-3" />
          Failed
        </Badge>
      )
    default:
      return <Badge variant="outline">{status}</Badge>
  }
}

function ChannelBadge({ channel }: { channel: string }) {
  const variant =
    channel === "stable"
      ? "secondary"
      : channel === "latest"
        ? "default"
        : "outline"
  return <Badge variant={variant}>{channel}</Badge>
}

export default function AdminLibraryShow({
  library,
  versions,
  crawlRequests,
}: Props) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const slug = `${library.namespace}/${library.name}`

  function handleDelete() {
    setDeleting(true)
    router.delete(`/admin/libraries/${library.id}`, {
      onFinish: () => setDeleting(false),
    })
  }

  return (
    <AdminLayout>
      <Head title={library.displayName} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <Link
              href="/admin/libraries"
              aria-label="Back to libraries"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <h1 className="min-w-0 truncate text-lg font-semibold">
              {library.displayName}
            </h1>
            <span className="font-mono text-sm text-muted-foreground">
              {slug}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              nativeButton={false}
              render={<Link href={`/admin/libraries/${library.id}/edit`} />}
            >
              <Pencil className="size-4" />
              Edit
            </Button>
            <Button
              variant="destructive"
              size="sm"
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 className="size-4" />
              Delete
            </Button>
          </div>
        </div>

        {/* Main + sidebar grid */}
        <div className="grid items-start gap-4 lg:grid-cols-5">
          <div className="flex flex-col gap-4 lg:col-span-3">
            {/* Overview */}
            <Card>
              <CardHeader>
                <CardTitle>Library details</CardTitle>
              </CardHeader>
              <CardContent>
                <dl className="grid grid-cols-2 gap-x-6 gap-y-4 text-sm">
                  <div>
                    <dt className="text-muted-foreground">Display name</dt>
                    <dd className="mt-0.5 font-medium">
                      {library.displayName}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Account</dt>
                    <dd className="mt-0.5 font-medium">
                      {library.accountName}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Homepage</dt>
                    <dd className="mt-0.5 font-medium">
                      {library.homepageUrl ? (
                        <a
                          href={library.homepageUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="flex items-center gap-1 hover:underline"
                        >
                          <span className="truncate">
                            {library.homepageUrl}
                          </span>
                          <ExternalLink className="size-3 shrink-0" />
                        </a>
                      ) : (
                        <span className="text-muted-foreground">None</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Default version</dt>
                    <dd className="mt-0.5 font-medium">
                      {library.defaultVersion || (
                        <span className="text-muted-foreground">None</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">License</dt>
                    <dd className="mt-0.5 font-medium">
                      {library.licenseStatus || (
                        <span className="text-muted-foreground">Unknown</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Created</dt>
                    <dd className="mt-0.5 font-medium">
                      {formatDateShort(library.createdAt)}
                    </dd>
                  </div>
                  <div className="col-span-2">
                    <dt className="text-muted-foreground">Aliases</dt>
                    <dd className="mt-1 flex flex-wrap gap-1">
                      {library.aliases.length > 0 ? (
                        library.aliases.map((alias) => (
                          <Badge
                            key={alias}
                            variant="outline"
                            className="text-xs"
                          >
                            {alias}
                          </Badge>
                        ))
                      ) : (
                        <span className="text-sm text-muted-foreground">
                          None
                        </span>
                      )}
                    </dd>
                  </div>
                </dl>
              </CardContent>
            </Card>

            {/* Versions */}
            <Card>
              <CardHeader>
                <CardTitle>Versions</CardTitle>
                <CardDescription>
                  {versions.length} version
                  {versions.length !== 1 ? "s" : ""}
                </CardDescription>
              </CardHeader>
              <CardContent className="p-0">
                {versions.length === 0 ? (
                  <p className="px-6 pb-6 text-sm text-muted-foreground">
                    No versions published yet.
                  </p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Version</TableHead>
                          <TableHead>Channel</TableHead>
                          <TableHead className="text-right">Pages</TableHead>
                          <TableHead className="text-right">Created</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {versions.map((v) => (
                          <TableRow key={v.id}>
                            <TableCell className="font-medium">
                              {v.version}
                              {v.version === library.defaultVersion && (
                                <Badge
                                  variant="secondary"
                                  className="ml-2 text-xs"
                                >
                                  default
                                </Badge>
                              )}
                            </TableCell>
                            <TableCell>
                              <ChannelBadge channel={v.channel} />
                            </TableCell>
                            <TableCell className="text-right">
                              {v.pageCount}
                            </TableCell>
                            <TableCell className="text-right text-sm text-muted-foreground">
                              {formatDateShort(v.createdAt)}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Crawl History */}
            {crawlRequests.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle>Crawl History</CardTitle>
                </CardHeader>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>URL</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Date</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {crawlRequests.map((cr) => (
                          <TableRow key={cr.id}>
                            <TableCell>
                              <a
                                href={cr.url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="flex items-center gap-1 text-sm hover:underline"
                              >
                                <span className="max-w-xs truncate">
                                  {cr.url}
                                </span>
                                <ExternalLink className="size-3 shrink-0" />
                              </a>
                              {cr.errorMessage && (
                                <p className="mt-1 text-xs text-destructive">
                                  {cr.errorMessage}
                                </p>
                              )}
                            </TableCell>
                            <TableCell className="text-sm">
                              {cr.sourceType}
                            </TableCell>
                            <TableCell>
                              <StatusBadge status={cr.status} />
                            </TableCell>
                            <TableCell className="text-right text-sm text-muted-foreground">
                              {formatDateShort(cr.createdAt)}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>

          {/* Sidebar */}
          <div className="flex flex-col gap-4 lg:col-span-2">
            <Card>
              <CardHeader>
                <CardTitle>Stats</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center gap-3">
                  <Layers className="size-5 text-muted-foreground" />
                  <div>
                    <div className="text-2xl font-bold">
                      {library.versionCount}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      Versions
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <FileText className="size-5 text-muted-foreground" />
                  <div>
                    <div className="text-2xl font-bold">
                      {library.pageCount}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      Total Pages
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <BookOpen className="size-5 text-muted-foreground" />
                  <div>
                    <div className="text-2xl font-bold">
                      {library.aliases.length}
                    </div>
                    <div className="text-xs text-muted-foreground">Aliases</div>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Quick links</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  className="justify-start"
                  nativeButton={false}
                  render={
                    <Link
                      href={`/libraries/${library.namespace}/${library.name}`}
                    />
                  }
                >
                  <ExternalLink className="size-4" />
                  View public page
                </Button>
                {library.homepageUrl && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="justify-start"
                    nativeButton={false}
                    render={
                      <a
                        href={library.homepageUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                      />
                    }
                  >
                    <ExternalLink className="size-4" />
                    Homepage
                  </Button>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {/* Delete confirmation */}
      <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Delete &ldquo;{library.displayName}&rdquo;?
            </DialogTitle>
            <DialogDescription>
              This will permanently delete this library and all its versions,
              pages, and bundles. Any crawl requests referencing this library
              will be unlinked. This cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeleteOpen(false)}
              disabled={deleting}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDelete}
              disabled={deleting}
            >
              {deleting ? "Deleting..." : "Yes, delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  )
}
