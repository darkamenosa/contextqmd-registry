import { useState, type FormEvent } from "react"
import { Link, router } from "@inertiajs/react"
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
  Layers,
  Search,
  Terminal,
  X,
} from "lucide-react"

import { formatBytes } from "@/lib/format-date"
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
import { LicenseBadge } from "@/components/shared/license-badge"
import { MarkdownContent } from "@/components/shared/markdown-content"
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import PublicLayout from "@/layouts/public-layout"

interface LibraryDetail {
  slug: string
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
  pagination: {
    page: number
    perPage: number
    total: number | null
    pages: number | null
    from: number
    to: number
    hasPrevious: boolean
    hasNext: boolean
    countKnown: boolean
  }
  search: string
  searchActive: boolean
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

function ChannelBadge({ channel }: { channel: string }) {
  const variant =
    channel === "stable"
      ? "secondary"
      : channel === "latest"
        ? "default"
        : "outline"
  return <Badge variant={variant}>{channel}</Badge>
}

function getPageRange(current: number, total: number): (number | "...")[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)
  const pages: (number | "...")[] = []
  if (current <= 4) {
    for (let i = 1; i <= 5; i++) pages.push(i)
    pages.push("...", total)
  } else if (current >= total - 3) {
    pages.push(1, "...")
    for (let i = total - 4; i <= total; i++) pages.push(i)
  } else {
    pages.push(1, "...", current - 1, current, current + 1, "...", total)
  }
  return pages
}

function PageNumbers({
  current,
  total,
  onPage,
}: {
  current: number
  total: number
  onPage: (p: number) => void
}) {
  const range = getPageRange(current, total)
  return (
    <>
      {range.map((item, i) =>
        item === "..." ? (
          <span
            key={`ellipsis-${i}`}
            className="inline-flex size-8 items-center justify-center text-xs text-muted-foreground/50"
          >
            &hellip;
          </span>
        ) : (
          <button
            key={item}
            type="button"
            onClick={() => onPage(item)}
            className={`inline-flex size-8 items-center justify-center rounded-sm text-xs font-medium tabular-nums transition-colors ${
              item === current
                ? "bg-foreground text-background"
                : "text-muted-foreground hover:bg-background hover:text-foreground"
            }`}
          >
            {item}
          </button>
        )
      )}
    </>
  )
}

function formatDate(iso: string | null): string {
  if (!iso) return "-"
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

export default function LibraryShow({
  library,
  versions,
  pages,
  selectedVersion,
  pagination,
  search: initialSearch,
  searchActive,
}: Props) {
  const [expandedPage, setExpandedPage] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState(initialSearch)
  const slug = library.slug

  const selectedVersionData = versions.find(
    (v) => v.version === selectedVersion
  )
  const showNumberedPagination = Boolean(
    pagination.countKnown && pagination.pages && pagination.pages > 1
  )
  const showPaginationFooter =
    showNumberedPagination || pagination.hasPrevious || pagination.hasNext

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

  const installQuery = library.slug
  const sampleVersion = selectedVersion || library.defaultVersion || "latest"
  const samplePagePath = pages[0]?.path || "docs/getting-started.md"
  const sampleSearchQuery =
    library.displayName === "Kamal" ? "proxy" : library.displayName

  const cliUsage = `npx -y contextqmd libraries search "${installQuery}"
npx -y contextqmd libraries install ${installQuery}
npx -y contextqmd docs search "${sampleSearchQuery}" --library ${slug}
npx -y contextqmd docs get --library ${slug} --version ${sampleVersion} --doc-path ${samplePagePath} --from-line 1 --max-lines 80`

  const mcpUsage = `// Add "contextqmd-mcp" to your MCP config, then use:
install_docs({ library: "${installQuery}" })
search_docs({ query: "${sampleSearchQuery}", library: "${slug}" })
get_doc({ library: "${slug}", version: "${sampleVersion}", doc_path: "${samplePagePath}" })`

  const apiResolve = `curl /api/v1/resolve \\
  -X POST -H "Content-Type: application/json" \\
  -d '{"query": "${installQuery}"}'`

  const apiPages = `curl /api/v1/libraries/${slug}/versions/${selectedVersion || "latest"}/page-index`

  return (
    <PublicLayout title={`${library.displayName} — ContextQMD`}>
      <section className="mx-auto max-w-7xl px-4 pt-6 pb-4 sm:px-6 sm:pt-8 sm:pb-6 lg:px-8">
        {/* Back link */}
        <Button
          variant="ghost"
          size="sm"
          nativeButton={false}
          render={<Link href="/libraries" />}
          className="mb-4 -ml-3 sm:mb-6"
        >
          <ArrowLeft className="size-4" />
          Back to Libraries
        </Button>

        {/* Header */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
              {library.displayName}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">{library.slug}</p>
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

        {/* Quick stats — pills on mobile, card strip on desktop */}
        <div className="mt-4 flex flex-wrap gap-2 sm:hidden">
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Layers className="size-3" />
            {versions.length} versions
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <FileText className="size-3" />
            {selectedVersionData?.pageCount ?? pagination.total} pages
            {selectedVersion ? ` (${selectedVersion})` : ""}
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Globe className="size-3" />
            {library.aliases.length} aliases
          </Badge>
        </div>
        <div className="mt-6 hidden grid-cols-3 divide-x rounded-lg border bg-card text-card-foreground sm:grid">
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Layers className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{versions.length}</div>
              <div className="text-xs text-muted-foreground">Versions</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <FileText className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">
                {selectedVersionData?.pageCount ?? pagination.total}
              </div>
              <div className="text-xs text-muted-foreground">
                Pages{selectedVersion ? ` (${selectedVersion})` : ""}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Globe className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{library.aliases.length}</div>
              <div className="text-xs text-muted-foreground">Aliases</div>
            </div>
          </div>
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
          <TabsContent value="pages" className="mt-4 sm:mt-6">
            {/* Toolbar: unified filter bar */}
            <div className="mb-3 flex flex-col gap-2 rounded-lg border bg-muted/20 p-2 sm:mb-5 sm:flex-row sm:items-center sm:gap-3">
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
                  {pagination.countKnown && pagination.total !== null ? (
                    <>
                      {pagination.total} result
                      {pagination.total !== 1 ? "s" : ""} for
                      <span className="font-semibold text-foreground">
                        &ldquo;{initialSearch}&rdquo;
                      </span>
                    </>
                  ) : (
                    <>
                      Showing {pagination.from}&ndash;{pagination.to} for
                      <span className="font-semibold text-foreground">
                        &ldquo;{initialSearch}&rdquo;
                      </span>
                      {pagination.hasNext ? " with more matches available" : ""}
                    </>
                  )}
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
                  {searchActive
                    ? "No pages match your search"
                    : "No documentation indexed yet"}
                </p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {searchActive
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
                                {page.headings.slice(1, 5).map((h, i) => (
                                  <span
                                    key={`${h}-${i}`}
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
                          <div className="flex shrink-0 items-center gap-2">
                            {page.url ? (
                              <a
                                href={page.url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="hidden items-center gap-1 rounded-xs bg-muted px-1.5 py-0.5 text-[11px]/3 font-medium text-muted-foreground transition-colors hover:text-foreground sm:inline-flex"
                                onClick={(e) => e.stopPropagation()}
                                title={page.url}
                              >
                                {(() => {
                                  try {
                                    const u = new URL(page.url)
                                    const path =
                                      u.pathname === "/" ? "" : u.pathname
                                    const display = `${u.hostname}${path}${u.hash}`
                                    return display.length > 50
                                      ? display.slice(0, 47) + "..."
                                      : display
                                  } catch {
                                    return page.url
                                  }
                                })()}
                                <ExternalLink className="size-2.5 shrink-0 opacity-50" />
                              </a>
                            ) : (
                              <code className="hidden rounded-xs bg-muted px-1.5 py-0.5 text-[11px]/3 font-medium text-muted-foreground sm:inline">
                                {page.path}
                              </code>
                            )}
                            <span className="hidden min-w-12 text-right text-[11px] text-muted-foreground/70 tabular-nums sm:inline">
                              {formatBytes(page.bytes)}
                            </span>
                            {selectedVersion && (
                              <Link
                                href={`/libraries/${slug}/versions/${selectedVersion}/pages/${page.pageUid}`}
                                className="inline-flex h-7 items-center gap-1 rounded-md border bg-background px-2.5 text-xs font-medium text-foreground/80 transition-colors hover:bg-muted hover:text-foreground"
                                onClick={(e) => e.stopPropagation()}
                              >
                                <ExternalLink className="size-3" />
                                <span className="hidden sm:inline">
                                  Full page
                                </span>
                              </Link>
                            )}
                          </div>
                        </button>
                        {isExpanded && page.content && (
                          <div className="relative border-t border-border/60 bg-muted/20">
                            <CopyButton text={page.content} />
                            <div className="p-4 pr-12">
                              <div className="prose prose-sm max-w-none dark:prose-invert prose-headings:scroll-mt-4 prose-code:before:content-none prose-code:after:content-none prose-pre:overflow-x-auto prose-pre:bg-zinc-950 prose-pre:text-zinc-100">
                                <MarkdownContent content={page.content} />
                              </div>
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })}

                  {/* Pagination footer */}
                  {showPaginationFooter && (
                    <div className="flex items-center justify-between bg-muted/30 px-4 py-3">
                      <span className="hidden text-xs text-muted-foreground tabular-nums sm:block">
                        {pagination.from}&ndash;{pagination.to}
                        {pagination.countKnown && pagination.total !== null
                          ? ` of ${pagination.total}`
                          : ""}
                      </span>

                      <div className="flex flex-1 items-center justify-center gap-1 sm:flex-initial">
                        <button
                          type="button"
                          onClick={() => goToPage(pagination.page - 1)}
                          disabled={!pagination.hasPrevious}
                          className="inline-flex size-8 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-background hover:text-foreground disabled:pointer-events-none disabled:opacity-30"
                        >
                          <ChevronLeft className="size-4" />
                        </button>

                        {showNumberedPagination && pagination.pages && (
                          <PageNumbers
                            current={pagination.page}
                            total={pagination.pages}
                            onPage={goToPage}
                          />
                        )}

                        <button
                          type="button"
                          onClick={() => goToPage(pagination.page + 1)}
                          disabled={!pagination.hasNext}
                          className="inline-flex size-8 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-background hover:text-foreground disabled:pointer-events-none disabled:opacity-30"
                        >
                          <ChevronRight className="size-4" />
                        </button>
                      </div>

                      <span className="hidden min-w-16 text-right text-xs text-muted-foreground sm:block">
                        Page {pagination.page}
                      </span>
                    </div>
                  )}
                </div>
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
              <div className="overflow-x-auto rounded-xl border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="pl-4">Version</TableHead>
                      <TableHead>Channel</TableHead>
                      <TableHead className="hidden sm:table-cell">
                        Generated
                      </TableHead>
                      <TableHead className="text-right">Pages</TableHead>
                      <TableHead className="pr-4" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {versions.map((v) => (
                      <TableRow key={v.version}>
                        <TableCell className="pl-4 font-medium">
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
                        <TableCell className="hidden sm:table-cell">
                          {formatDate(v.generatedAt)}
                        </TableCell>
                        <TableCell className="text-right">
                          {v.pageCount}
                        </TableCell>
                        <TableCell className="pr-4 text-right">
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
                  CLI Usage
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="mb-3 text-sm text-muted-foreground">
                  Use the standalone CLI package{" "}
                  <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                    contextqmd
                  </code>{" "}
                  to search, install, and read {library.displayName} docs:
                </p>
                <div className="relative overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                  <CopyButton text={cliUsage} />
                  <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                    <code>{cliUsage}</code>
                  </pre>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <Terminal className="size-4" />
                  MCP Tool Usage
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="mb-3 text-sm text-muted-foreground">
                  Use the MCP package{" "}
                  <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                    contextqmd-mcp
                  </code>{" "}
                  in your editor to install and search {library.displayName}{" "}
                  docs:
                </p>
                <div className="relative overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                  <CopyButton text={mcpUsage} />
                  <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                    <code>{mcpUsage}</code>
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
