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
import { StatusBadge } from "@/components/admin/ui/status-badge"
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import AdminLayout from "@/layouts/admin-layout"

interface Props {
  library: AdminLibraryDetail
  versions: AdminLibraryVersion[]
  crawlRequests: AdminCrawlItem[]
}

function CrawlStatusBadge({ status }: { status: string }) {
  switch (status) {
    case "pending":
      return (
        <StatusBadge status={status} showDot={false}>
          <Clock className="size-3" />
          Pending
        </StatusBadge>
      )
    case "processing":
      return (
        <StatusBadge status={status} showDot={false}>
          <Loader2 className="size-3 animate-spin" />
          Processing
        </StatusBadge>
      )
    case "completed":
      return (
        <StatusBadge status={status} showDot={false}>
          <CheckCircle className="size-3" />
          Completed
        </StatusBadge>
      )
    case "failed":
      return (
        <StatusBadge status={status} showDot={false}>
          <XCircle className="size-3" />
          Failed
        </StatusBadge>
      )
    default:
      return <StatusBadge status={status} showDot={false} />
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
        <TableCell className="pl-4 font-medium">
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
        <TableCell className="hidden text-right text-sm text-muted-foreground sm:table-cell">
          {formatDateTime(v.createdAt)}
        </TableCell>
        <TableCell className="pr-4 text-right">
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
    (rules.gitIncludePrefixes?.length ?? 0) > 0 ||
    (rules.gitExcludePrefixes?.length ?? 0) > 0 ||
    (rules.gitExcludeBasenames?.length ?? 0) > 0
  )
}

function hasWebsiteRules(rules: CrawlRules): boolean {
  return (rules.websiteExcludePathPrefixes?.length ?? 0) > 0
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
                  items={rules.gitIncludePrefixes}
                />
                <RulesList
                  label="Exclude folders"
                  items={rules.gitExcludePrefixes}
                />
                <RulesList
                  label="Exclude files"
                  items={rules.gitExcludeBasenames}
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
                  items={rules.websiteExcludePathPrefixes}
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

  const slug = library.slug

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

      <div className="flex min-w-0 flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-2.5">
            <Link
              href="/admin/libraries"
              aria-label="Back to libraries"
              className="shrink-0 rounded-sm p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <h1 className="min-w-0 truncate text-lg font-semibold">
              {library.displayName}
            </h1>
            <span className="hidden font-mono text-sm text-muted-foreground sm:inline">
              {slug}
            </span>
          </div>

          {/* Mobile: overflow menu */}
          <DropdownMenu>
            <DropdownMenuTrigger className="inline-flex size-8 shrink-0 items-center justify-center rounded-md border text-muted-foreground hover:bg-muted hover:text-foreground sm:hidden">
              <MoreHorizontal className="size-4" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem
                onClick={() => router.visit(`/libraries/${library.slug}`)}
              >
                <ExternalLink className="mr-2 size-4" />
                View public page
              </DropdownMenuItem>
              {library.homepageUrl && (
                <DropdownMenuItem
                  onClick={() => window.open(library.homepageUrl!, "_blank")}
                >
                  <Globe className="mr-2 size-4" />
                  Homepage
                </DropdownMenuItem>
              )}
              <DropdownMenuSeparator />
              {library.lastCrawlUrl && (
                <DropdownMenuItem onClick={handleRecrawl} disabled={recrawling}>
                  <RefreshCw className="mr-2 size-4" />
                  {recrawling ? "Queuing..." : "Re-crawl"}
                </DropdownMenuItem>
              )}
              <DropdownMenuItem
                onClick={() =>
                  router.visit(`/admin/libraries/${library.id}/edit`)
                }
              >
                <Pencil className="mr-2 size-4" />
                Edit
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                className="text-destructive focus:text-destructive"
                onClick={() => setDeleteOpen(true)}
              >
                <Trash2 className="mr-2 size-4" />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Desktop: inline buttons */}
          <div className="hidden shrink-0 items-center gap-2 sm:flex">
            <Button
              variant="ghost"
              size="sm"
              nativeButton={false}
              render={<Link href={`/libraries/${library.slug}`} />}
            >
              <ExternalLink className="size-3.5" />
              Public page
            </Button>
            {library.homepageUrl && (
              <Button
                variant="ghost"
                size="sm"
                nativeButton={false}
                render={
                  <a
                    href={library.homepageUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                  />
                }
              >
                <Globe className="size-3.5" />
                Homepage
              </Button>
            )}
            <div className="h-4 w-px bg-border" />
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

        {/* Stats — pills on mobile, card on sm+ */}
        <div className="flex flex-wrap gap-2 sm:hidden">
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Layers className="size-3" />
            {library.versionCount} versions
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <FileText className="size-3" />
            {library.pageCount} pages
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <BookOpen className="size-3" />
            {library.aliases.length} aliases
          </Badge>
        </div>
        <div className="hidden grid-cols-3 divide-x rounded-lg border bg-card text-card-foreground sm:grid">
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Layers className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-xl font-semibold">
                {library.versionCount}
              </div>
              <div className="text-xs text-muted-foreground">Versions</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <FileText className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-xl font-semibold">{library.pageCount}</div>
              <div className="text-xs text-muted-foreground">Pages</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <BookOpen className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-xl font-semibold">
                {library.aliases.length}
              </div>
              <div className="text-xs text-muted-foreground">Aliases</div>
            </div>
          </div>
        </div>

        {/* Main + sidebar grid */}
        <div className="grid min-w-0 items-start gap-4 lg:grid-cols-3">
          <div className="flex min-w-0 flex-col gap-4 lg:col-span-2">
            {/* Overview */}
            <Card>
              <CardHeader>
                <CardTitle>Library details</CardTitle>
              </CardHeader>
              <CardContent>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm sm:gap-x-6">
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
                  <div className="col-span-2">
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
                  {library.aliases.length > 0 && (
                    <div className="col-span-2">
                      <dt className="text-muted-foreground">Aliases</dt>
                      <dd className="mt-1 flex flex-wrap gap-1">
                        {library.aliases.map((alias) => (
                          <Badge
                            key={alias}
                            variant="outline"
                            className="text-xs"
                          >
                            {alias}
                          </Badge>
                        ))}
                      </dd>
                    </div>
                  )}
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
                          <TableHead className="pl-4">Version</TableHead>
                          <TableHead>Channel</TableHead>
                          <TableHead className="text-right">Pages</TableHead>
                          <TableHead className="hidden text-right sm:table-cell">
                            Created
                          </TableHead>
                          <TableHead className="w-24 pr-4 sm:w-32" />
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
                          <TableHead className="pl-4">URL</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="pr-4 sm:pr-2">Status</TableHead>
                          <TableHead className="hidden pr-4 text-right sm:table-cell">
                            Date
                          </TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {crawlRequests.map((cr) => (
                          <TableRow key={cr.id}>
                            <TableCell className="pl-4">
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
                              <SourceTypeIcon
                                sourceType={cr.sourceType}
                                size="size-3.5"
                                showLabel
                              />
                            </TableCell>
                            <TableCell className="pr-4 sm:pr-2">
                              <CrawlStatusBadge status={cr.status} />
                            </TableCell>
                            <TableCell className="hidden pr-4 text-right text-sm text-muted-foreground sm:table-cell">
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
          <div className="flex flex-col gap-4">
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
