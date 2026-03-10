import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type {
  AdminCrawlItem,
  AdminLibraryDetail,
  AdminLibraryVersion,
  CrawlRules,
} from "@/types"
import {
  BookOpen,
  Check,
  CheckCircle,
  ChevronLeft,
  ChevronRight,
  Clock,
  ExternalLink,
  FileText,
  FolderGit2,
  Globe,
  Layers,
  Loader2,
  MoreHorizontal,
  Pencil,
  RefreshCw,
  Star,
  Trash2,
  XCircle,
} from "lucide-react"

import { formatDateTime } from "@/lib/format-date"
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
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
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

// --- Version row with actions ---

function VersionRow({
  v,
  libraryId,
  isDefault,
}: {
  v: AdminLibraryVersion
  libraryId: number
  isDefault: boolean
}) {
  const [renameOpen, setRenameOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [newName, setNewName] = useState(v.version)
  const [processing, setProcessing] = useState(false)

  function handleSetDefault() {
    router.patch(
      `/admin/libraries/${libraryId}/default_version`,
      { version: v.version },
      { preserveScroll: true }
    )
  }

  function handleRename() {
    if (!newName.trim() || newName === v.version) {
      setRenameOpen(false)
      return
    }
    setProcessing(true)
    router.patch(
      `/admin/versions/${v.id}`,
      { version: { version: newName.trim() } },
      {
        preserveScroll: true,
        onFinish: () => {
          setProcessing(false)
          setRenameOpen(false)
        },
      }
    )
  }

  function handleDelete() {
    setProcessing(true)
    router.delete(`/admin/versions/${v.id}`, {
      preserveScroll: true,
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <>
      <TableRow>
        <TableCell className="font-medium">
          <Link
            href={`/admin/versions/${v.id}/pages`}
            className="hover:underline"
          >
            {v.version}
          </Link>
          {isDefault && (
            <Badge variant="secondary" className="ml-2 text-xs">
              default
            </Badge>
          )}
        </TableCell>
        <TableCell>
          <ChannelBadge channel={v.channel} />
        </TableCell>
        <TableCell className="text-right">{v.pageCount}</TableCell>
        <TableCell className="text-right text-sm text-muted-foreground">
          {formatDateTime(v.createdAt)}
        </TableCell>
        <TableCell className="text-right">
          <div className="flex items-center justify-end gap-1">
            <Button
              variant="ghost"
              size="sm"
              className="h-7 gap-1 px-2 text-xs"
              nativeButton={false}
              render={<Link href={`/admin/versions/${v.id}/pages`} />}
            >
              Pages
              <ChevronRight className="size-3" />
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger className="inline-flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground">
                <MoreHorizontal className="size-4" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                {!isDefault && (
                  <DropdownMenuItem onClick={handleSetDefault}>
                    <Star className="mr-2 size-4" />
                    Set as default
                  </DropdownMenuItem>
                )}
                {isDefault && (
                  <DropdownMenuItem disabled>
                    <Check className="mr-2 size-4" />
                    Current default
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem onClick={() => setRenameOpen(true)}>
                  <Pencil className="mr-2 size-4" />
                  Rename
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  className="text-destructive focus:text-destructive"
                  onClick={() => setDeleteOpen(true)}
                >
                  <Trash2 className="mr-2 size-4" />
                  Delete version
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </TableCell>
      </TableRow>

      {/* Rename dialog */}
      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rename version</DialogTitle>
            <DialogDescription>
              Change the version identifier from &ldquo;{v.version}&rdquo;.
            </DialogDescription>
          </DialogHeader>
          <Input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="e.g. 11.x, latest, v2.0.0"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter") handleRename()
            }}
          />
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setRenameOpen(false)}
              disabled={processing}
            >
              Cancel
            </Button>
            <Button onClick={handleRename} disabled={processing}>
              {processing ? "Saving..." : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete dialog */}
      <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete version &ldquo;{v.version}&rdquo;?</DialogTitle>
            <DialogDescription>
              This will permanently delete this version and all {v.pageCount}{" "}
              pages within it. This cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeleteOpen(false)}
              disabled={processing}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDelete}
              disabled={processing}
            >
              {processing ? "Deleting..." : "Yes, delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

// --- Crawl rules card ---

function hasGitRules(rules: CrawlRules): boolean {
  return (
    (rules.git_include_prefixes?.length ?? 0) > 0 ||
    (rules.git_exclude_prefixes?.length ?? 0) > 0 ||
    (rules.git_exclude_basenames?.length ?? 0) > 0
  )
}

function hasWebsiteRules(rules: CrawlRules): boolean {
  return (rules.website_exclude_path_prefixes?.length ?? 0) > 0
}

function RulesList({
  label,
  items,
}: {
  label: string
  items: string[] | undefined
}) {
  if (!items || items.length === 0) return null
  return (
    <div className="space-y-1">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="flex flex-wrap gap-1">
        {items.map((item) => (
          <Badge
            key={item}
            variant="outline"
            className="font-mono text-[11px] font-normal"
          >
            {item}
          </Badge>
        ))}
      </dd>
    </div>
  )
}

function CrawlRulesCard({
  rules,
  libraryId,
  sourceType,
}: {
  rules: CrawlRules
  libraryId: number
  sourceType: string | null
}) {
  const isGit =
    !sourceType || ["git", "github", "gitlab", "bitbucket"].includes(sourceType)
  const isWebsite = !sourceType || sourceType === "website"
  const gitCustom = hasGitRules(rules)
  const websiteCustom = hasWebsiteRules(rules)
  const anyCustom = gitCustom || websiteCustom

  return (
    <Card>
      <CardHeader>
        <CardTitle>Crawl Rules</CardTitle>
        {!anyCustom && (
          <CardDescription>Using built-in defaults only.</CardDescription>
        )}
      </CardHeader>
      <CardContent className="space-y-4">
        {isGit && (
          <div className="space-y-2">
            <div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <FolderGit2 className="size-3.5" />
              Git source
            </div>
            {gitCustom ? (
              <dl className="space-y-2 pl-5">
                <RulesList
                  label="Include folders"
                  items={rules.git_include_prefixes}
                />
                <RulesList
                  label="Exclude folders"
                  items={rules.git_exclude_prefixes}
                />
                <RulesList
                  label="Exclude files"
                  items={rules.git_exclude_basenames}
                />
              </dl>
            ) : (
              <p className="pl-5 text-xs text-muted-foreground">
                Defaults only
              </p>
            )}
          </div>
        )}
        {isWebsite && (
          <div className="space-y-2">
            <div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <Globe className="size-3.5" />
              Website source
            </div>
            {websiteCustom ? (
              <dl className="pl-5">
                <RulesList
                  label="Exclude URLs"
                  items={rules.website_exclude_path_prefixes}
                />
              </dl>
            ) : (
              <p className="pl-5 text-xs text-muted-foreground">
                Defaults only
              </p>
            )}
          </div>
        )}
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start"
          nativeButton={false}
          render={<Link href={`/admin/libraries/${libraryId}/edit`} />}
        >
          <Pencil className="size-3.5" />
          {anyCustom ? "Edit rules" : "Add custom rules"}
        </Button>
      </CardContent>
    </Card>
  )
}

// --- Main page ---

export default function AdminLibraryShow({
  library,
  versions,
  crawlRequests,
}: Props) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [recrawling, setRecrawling] = useState(false)

  const slug = `${library.namespace}/${library.name}`

  function handleDelete() {
    setDeleting(true)
    router.delete(`/admin/libraries/${library.id}`, {
      onFinish: () => setDeleting(false),
    })
  }

  function handleRecrawl() {
    if (!library.lastCrawlUrl) return
    setRecrawling(true)
    router.post(
      `/admin/libraries/${library.id}/recrawl`,
      { url: library.lastCrawlUrl },
      { onFinish: () => setRecrawling(false) }
    )
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
            {library.lastCrawlUrl && (
              <Button
                variant="outline"
                size="sm"
                onClick={handleRecrawl}
                disabled={recrawling}
              >
                <RefreshCw
                  className={`size-4 ${recrawling ? "animate-spin" : ""}`}
                />
                {recrawling ? "Queuing..." : "Re-crawl"}
              </Button>
            )}
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
                      {formatDateTime(library.createdAt)}
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

            {/* Versions & Pages */}
            <Card>
              <CardHeader>
                <CardTitle>Versions &amp; Pages</CardTitle>
                <CardDescription>
                  {versions.length} version{versions.length !== 1 ? "s" : ""},{" "}
                  {versions.reduce((sum, v) => sum + v.pageCount, 0)} total
                  pages
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
                          <TableHead className="w-32" />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {versions.map((v) => (
                          <VersionRow
                            key={v.id}
                            v={v}
                            libraryId={library.id}
                            isDefault={v.version === library.defaultVersion}
                          />
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
                              {formatDateTime(cr.createdAt)}
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

            <CrawlRulesCard
              rules={library.crawlRules || {}}
              libraryId={library.id}
              sourceType={library.sourceType}
            />
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
