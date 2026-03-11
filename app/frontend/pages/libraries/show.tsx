import { useState, type FormEvent } from "react"
import { Link, router } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import {
  ArrowLeft,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Copy,
  ExternalLink,
  FileText,
  Globe,
  Search,
  Terminal,
  X,
} from "lucide-react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"

import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import PublicLayout from "@/layouts/public-layout"

interface LibraryDetail {
  namespace: string
  name: string
  displayName: string
  aliases: string[]
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
  sourceType: string | null
  versionCount: number
}

interface VersionItem {
  version: string
  channel: string
  generatedAt: string | null
  pageCount: number
}

interface PageItem {
  pageUid: string
  path: string
  title: string
  url: string
  headings: string[]
  bytes: number
  content: string | null
}

interface Props {
  library: LibraryDetail
  versions: VersionItem[]
  pages: PageItem[]
  selectedVersion: string | null
  pagination: PaginationData
  search: string
}

/** Strip inline HTML tags (especially img) from markdown source before rendering */
function cleanMarkdown(md: string): string {
  return md
    .replace(/<img[^>]*>/gi, "") // remove img tags
    .replace(/<br\s*\/?>/gi, "\n") // convert br to newlines
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <Button
      variant="ghost"
      size="sm"
      className="absolute top-2 right-2 size-8 p-0"
      onClick={handleCopy}
    >
      {copied ? (
        <Check className="size-3.5 text-green-500" />
      ) : (
        <Copy className="size-3.5" />
      )}
    </Button>
  )
}

function LicenseBadge({ status }: { status: string | null }) {
  if (!status) return null
  const variant =
    status === "verified"
      ? "secondary"
      : status === "unclear"
        ? "outline"
        : "destructive"
  return <Badge variant={variant}>{status}</Badge>
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

function formatDate(iso: string | null): string {
  if (!iso) return "-"
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export default function LibraryShow({
  library,
  versions,
  pages,
  selectedVersion,
  pagination,
  search: initialSearch,
}: Props) {
  const [expandedPage, setExpandedPage] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState(initialSearch)
  const slug = `${library.namespace}/${library.name}`

  const selectedVersionData = versions.find(
    (v) => v.version === selectedVersion
  )

  function switchVersion(version: string) {
    router.get(
      `/libraries/${slug}`,
      { version },
      { preserveState: true, preserveScroll: true }
    )
  }

  function goToPage(page: number) {
    const params: Record<string, string | number | null> = {
      version: selectedVersion,
      page,
    }
    if (initialSearch) params.search = initialSearch
    router.get(`/libraries/${slug}`, params, {
      preserveState: true,
      preserveScroll: true,
    })
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault()
    router.get(
      `/libraries/${slug}`,
      searchQuery
        ? { version: selectedVersion, search: searchQuery }
        : { version: selectedVersion },
      { preserveState: true, preserveScroll: true }
    )
  }

  function clearSearch() {
    setSearchQuery("")
    router.get(
      `/libraries/${slug}`,
      { version: selectedVersion },
      { preserveState: true, preserveScroll: true }
    )
  }

  const mcpInstall = `// In your MCP-enabled editor, use the install_docs tool:
resolve_docs_library({ name: "${library.aliases[0] || library.name}" })
install_docs({ library: "${slug}" })`

  const apiResolve = `curl https://contextqmd.com/api/v1/resolve \\
  -X POST -H "Content-Type: application/json" \\
  -d '{"query": "${library.aliases[0] || library.name}"}'`

  const apiPages = `curl https://contextqmd.com/api/v1/libraries/${slug}/versions/${selectedVersion || "latest"}/page-index`

  return (
    <PublicLayout title={`${library.displayName} — ContextQMD`}>
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        {/* Back link */}
        <Button
          variant="ghost"
          size="sm"
          nativeButton={false}
          render={<Link href="/libraries" />}
          className="mb-6"
        >
          <ArrowLeft className="size-4" />
          Back to Libraries
        </Button>

        {/* Header */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
              {library.displayName}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">{slug}</p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {library.sourceType && (
                <Badge variant="outline" className="gap-1 text-xs">
                  <SourceTypeIcon
                    sourceType={library.sourceType}
                    size="size-3"
                    showLabel
                  />
                </Badge>
              )}
              <LicenseBadge status={library.licenseStatus} />
              {library.aliases.map((alias) => (
                <Badge key={alias} variant="outline" className="text-xs">
                  {alias}
                </Badge>
              ))}
            </div>
          </div>
          <div className="flex gap-2">
            {library.homepageUrl && (
              <Button
                variant="outline"
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
                <ExternalLink className="size-4" />
                Homepage
              </Button>
            )}
          </div>
        </div>

        {/* Quick stats */}
        <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{versions.length}</div>
              <div className="text-sm text-muted-foreground">Versions</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">
                {selectedVersionData?.pageCount ?? pagination.total}
              </div>
              <div className="text-sm text-muted-foreground">
                Pages
                {selectedVersion ? ` (${selectedVersion})` : ""}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{library.aliases.length}</div>
              <div className="text-sm text-muted-foreground">Aliases</div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Tabs */}
      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        <Tabs defaultValue="pages">
          <TabsList>
            <TabsTrigger value="pages">
              <FileText className="mr-1.5 size-4" />
              Pages
            </TabsTrigger>
            <TabsTrigger value="versions">
              <BookOpen className="mr-1.5 size-4" />
              Versions
            </TabsTrigger>
            <TabsTrigger value="usage">
              <Terminal className="mr-1.5 size-4" />
              Usage
            </TabsTrigger>
          </TabsList>

          {/* Pages tab */}
          <TabsContent value="pages" className="mt-6">
            {/* Toolbar: unified filter bar */}
            <div className="mb-5 flex flex-col gap-2 rounded-lg border bg-muted/20 p-2 sm:flex-row sm:items-center sm:gap-3">
              {versions.length > 1 && (
                <div className="flex shrink-0 items-center gap-2">
                  <Select
                    value={selectedVersion || versions[0]?.version}
                    onValueChange={(val) => val && switchVersion(val as string)}
                  >
                    <SelectTrigger size="sm" className="bg-background">
                      <SelectValue placeholder="Version" />
                    </SelectTrigger>
                    <SelectContent align="start" alignItemWithTrigger={false}>
                      {versions.map((v) => (
                        <SelectItem key={v.version} value={v.version}>
                          <span>{v.version}</span>
                          <span className="text-xs text-muted-foreground">
                            {v.pageCount} pages
                          </span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {selectedVersionData && (
                    <ChannelBadge channel={selectedVersionData.channel} />
                  )}
                </div>
              )}

              <form onSubmit={handleSearch} className="flex min-w-0 flex-1">
                <div className="relative min-w-0 flex-1">
                  <Search className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    type="text"
                    placeholder="Search pages..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="h-7 bg-background pr-8 pl-8 text-sm"
                  />
                  {(searchQuery || initialSearch) && (
                    <button
                      type="button"
                      onClick={clearSearch}
                      className="absolute top-1/2 right-2.5 -translate-y-1/2 text-muted-foreground transition-colors hover:text-foreground"
                    >
                      <X className="size-3.5" />
                    </button>
                  )}
                </div>
              </form>
            </div>

            {/* Search results pill */}
            {initialSearch && (
              <div className="mb-4">
                <span className="inline-flex items-center gap-1.5 rounded-md bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {pagination.total} result
                  {pagination.total !== 1 ? "s" : ""} for
                  <span className="font-semibold text-foreground">
                    &ldquo;{initialSearch}&rdquo;
                  </span>
                  <button
                    type="button"
                    onClick={clearSearch}
                    className="ml-0.5 rounded-xs p-0.5 hover:bg-foreground/10"
                  >
                    <X className="size-3" />
                  </button>
                </span>
              </div>
            )}

            {pages.length === 0 ? (
              <div className="rounded-xl border border-dashed p-12 text-center">
                <div className="mx-auto flex size-12 items-center justify-center rounded-full bg-muted">
                  <FileText className="size-5 text-muted-foreground" />
                </div>
                <p className="mt-4 text-sm font-medium">
                  {initialSearch
                    ? "No pages match your search"
                    : "No documentation indexed yet"}
                </p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {initialSearch
                    ? "Try a different search term."
                    : "Check back soon or submit a crawl request."}
                </p>
                {!initialSearch && (
                  <Button
                    variant="outline"
                    size="sm"
                    nativeButton={false}
                    render={<Link href="/crawl/new" />}
                    className="mt-4"
                  >
                    Submit Crawl Request
                  </Button>
                )}
              </div>
            ) : (
              <>
                <div className="overflow-hidden rounded-xl border">
                  {pages.map((page, idx) => {
                    const isExpanded = expandedPage === page.pageUid
                    return (
                      <div
                        key={page.pageUid}
                        className={idx > 0 ? "border-t" : ""}
                      >
                        <button
                          type="button"
                          className="group flex w-full items-start gap-3 px-4 py-3.5 text-left transition-colors hover:bg-muted/40"
                          onClick={() =>
                            setExpandedPage(isExpanded ? null : page.pageUid)
                          }
                        >
                          <div className="mt-0.5 shrink-0">
                            <ChevronRight
                              className={`size-4 text-muted-foreground transition-transform duration-150 ${isExpanded ? "rotate-90" : ""}`}
                            />
                          </div>
                          <div className="min-w-0 flex-1">
                            <div className="text-sm/5 font-semibold group-hover:text-primary">
                              {page.title}
                            </div>
                            {page.headings.length > 1 && (
                              <div className="mt-1.5 flex flex-wrap gap-1">
                                {page.headings.slice(1, 5).map((h) => (
                                  <span
                                    key={h}
                                    className="inline-block rounded-xs bg-muted px-1.5 py-0.5 text-[11px]/3 text-muted-foreground"
                                  >
                                    {h}
                                  </span>
                                ))}
                                {page.headings.length > 5 && (
                                  <span className="inline-block px-1.5 py-0.5 text-[11px]/3 text-muted-foreground">
                                    +{page.headings.length - 5} more
                                  </span>
                                )}
                              </div>
                            )}
                          </div>
                          <div className="hidden shrink-0 items-center gap-2 sm:flex">
                            <code className="rounded-xs bg-muted px-1.5 py-0.5 text-[11px]/3 font-medium text-muted-foreground">
                              {page.path}
                            </code>
                            <span className="min-w-12 text-right text-[11px] text-muted-foreground/70 tabular-nums">
                              {formatBytes(page.bytes)}
                            </span>
                          </div>
                        </button>
                        {isExpanded && page.content && (
                          <div className="relative border-t border-border/60 bg-muted/20">
                            <CopyButton text={page.content} />
                            <div className="max-h-[500px] overflow-y-auto p-4 pr-12">
                              <div className="prose prose-sm max-w-none dark:prose-invert prose-headings:scroll-mt-4 prose-code:before:content-none prose-code:after:content-none prose-pre:overflow-x-auto prose-pre:bg-zinc-950 prose-pre:text-zinc-100">
                                <ReactMarkdown
                                  remarkPlugins={[remarkGfm]}
                                  components={{
                                    img: () => null,
                                  }}
                                >
                                  {cleanMarkdown(page.content)}
                                </ReactMarkdown>
                              </div>
                              {selectedVersion && (
                                <div className="mt-4 border-t border-border/40 pt-3">
                                  <Button
                                    variant="outline"
                                    size="sm"
                                    nativeButton={false}
                                    render={
                                      <Link
                                        href={`/libraries/${slug}/versions/${selectedVersion}/pages/${page.pageUid}`}
                                      />
                                    }
                                  >
                                    <FileText className="size-3.5" />
                                    View full page
                                  </Button>
                                </div>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>

                {/* Pagination */}
                {pagination.pages > 1 && (
                  <div className="mt-5 flex items-center justify-between">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => goToPage(pagination.page - 1)}
                      disabled={!pagination.hasPrevious}
                    >
                      <ChevronLeft className="size-4" />
                      <span className="hidden sm:inline">Previous</span>
                    </Button>
                    <span className="rounded-md bg-muted px-3 py-1 text-xs font-medium text-muted-foreground tabular-nums">
                      {pagination.page} / {pagination.pages}
                    </span>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => goToPage(pagination.page + 1)}
                      disabled={!pagination.hasNext}
                    >
                      <span className="hidden sm:inline">Next</span>
                      <ChevronRight className="size-4" />
                    </Button>
                  </div>
                )}
              </>
            )}
          </TabsContent>

          {/* Versions tab */}
          <TabsContent value="versions" className="mt-6">
            {versions.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No versions published yet.
              </p>
            ) : (
              <div className="rounded-xl border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Version</TableHead>
                      <TableHead>Channel</TableHead>
                      <TableHead>Generated</TableHead>
                      <TableHead className="text-right">Pages</TableHead>
                      <TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {versions.map((v) => (
                      <TableRow key={v.version}>
                        <TableCell className="font-medium">
                          {v.version}
                          {v.version === selectedVersion && (
                            <Badge variant="secondary" className="ml-2 text-xs">
                              viewing
                            </Badge>
                          )}
                          {v.version === library.defaultVersion && (
                            <Badge variant="outline" className="ml-2 text-xs">
                              default
                            </Badge>
                          )}
                        </TableCell>
                        <TableCell>
                          <ChannelBadge channel={v.channel} />
                        </TableCell>
                        <TableCell>{formatDate(v.generatedAt)}</TableCell>
                        <TableCell className="text-right">
                          {v.pageCount}
                        </TableCell>
                        <TableCell className="text-right">
                          {v.version !== selectedVersion && (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => switchVersion(v.version)}
                            >
                              View pages
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </TabsContent>

          {/* Usage tab */}
          <TabsContent value="usage" className="mt-6 space-y-6">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <Terminal className="size-4" />
                  MCP Tool Usage
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="mb-3 text-sm text-muted-foreground">
                  Use these MCP tools in your editor to install and search{" "}
                  {library.displayName} docs:
                </p>
                <div className="relative overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                  <CopyButton text={mcpInstall} />
                  <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                    <code>{mcpInstall}</code>
                  </pre>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <Globe className="size-4" />
                  API: Resolve Library
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="mb-3 text-sm text-muted-foreground">
                  Resolve this library via the REST API:
                </p>
                <div className="relative overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                  <CopyButton text={apiResolve} />
                  <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                    <code>{apiResolve}</code>
                  </pre>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <FileText className="size-4" />
                  API: Page Index
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="mb-3 text-sm text-muted-foreground">
                  Fetch the page index for{" "}
                  {selectedVersion
                    ? selectedVersion === "latest"
                      ? "latest"
                      : `v${selectedVersion}`
                    : "the default version"}
                  :
                </p>
                <div className="relative overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                  <CopyButton text={apiPages} />
                  <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                    <code>{apiPages}</code>
                  </pre>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </section>
    </PublicLayout>
  )
}
