import { Fragment, useState } from "react"
import { Link } from "@inertiajs/react"
import {
  ArrowLeft,
  BookOpen,
  Check,
  ChevronDown,
  ChevronRight,
  Copy,
  ExternalLink,
  FileText,
  Globe,
  Terminal,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import PublicLayout from "@/layouts/public-layout"

interface LibraryDetail {
  namespace: string
  name: string
  displayName: string
  aliases: string[]
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
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
  defaultVersionLabel: string | null
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
  defaultVersionLabel,
}: Props) {
  const [expandedPage, setExpandedPage] = useState<string | null>(null)
  const slug = `${library.namespace}/${library.name}`

  const mcpInstall = `// In your MCP-enabled editor, use the install_docs tool:
resolve_docs_library({ name: "${library.aliases[0] || library.name}" })
install_docs({ library: "${slug}" })`

  const apiResolve = `curl https://contextqmd.com/api/v1/resolve \\
  -X POST -H "Content-Type: application/json" \\
  -d '{"query": "${library.aliases[0] || library.name}"}'`

  const apiPages = `curl https://contextqmd.com/api/v1/libraries/${slug}/versions/${defaultVersionLabel || "latest"}/page-index`

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
              <LicenseBadge status={library.licenseStatus} />
              {library.defaultVersion && (
                <Badge variant="outline">v{library.defaultVersion}</Badge>
              )}
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
              <div className="text-2xl font-bold">{pages.length}</div>
              <div className="text-sm text-muted-foreground">
                Pages{defaultVersionLabel ? ` (v${defaultVersionLabel})` : ""}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">
                {library.aliases.length}
              </div>
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
            {pages.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No pages available for this version.
              </p>
            ) : (
              <div className="rounded-xl border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-8" />
                      <TableHead>Title</TableHead>
                      <TableHead>Path</TableHead>
                      <TableHead className="text-right">Size</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pages.map((page) => {
                      const isExpanded = expandedPage === page.pageUid
                      return (
                        <Fragment key={page.pageUid}>
                          <TableRow
                            className="cursor-pointer"
                            onClick={() =>
                              setExpandedPage(
                                isExpanded ? null : page.pageUid,
                              )
                            }
                          >
                            <TableCell className="w-8 pr-0">
                              {isExpanded ? (
                                <ChevronDown className="size-4 text-muted-foreground" />
                              ) : (
                                <ChevronRight className="size-4 text-muted-foreground" />
                              )}
                            </TableCell>
                            <TableCell>
                              <div className="font-medium">{page.title}</div>
                              {page.headings.length > 1 && (
                                <div className="mt-1 flex flex-wrap gap-1">
                                  {page.headings.slice(1, 4).map((h) => (
                                    <span
                                      key={h}
                                      className="text-xs text-muted-foreground"
                                    >
                                      {h}
                                      {page.headings.indexOf(h) <
                                      Math.min(page.headings.length - 1, 3)
                                        ? " · "
                                        : ""}
                                    </span>
                                  ))}
                                  {page.headings.length > 4 && (
                                    <span className="text-xs text-muted-foreground">
                                      +{page.headings.length - 4} more
                                    </span>
                                  )}
                                </div>
                              )}
                            </TableCell>
                            <TableCell className="font-mono text-xs text-muted-foreground">
                              {page.path}
                            </TableCell>
                            <TableCell className="text-right text-sm text-muted-foreground">
                              {formatBytes(page.bytes)}
                            </TableCell>
                          </TableRow>
                          {isExpanded && page.content && (
                            <TableRow>
                              <TableCell colSpan={4} className="bg-muted/30 p-0">
                                <div className="relative">
                                  <CopyButton text={page.content} />
                                  <pre className="max-h-96 overflow-auto whitespace-pre-wrap p-4 text-sm leading-relaxed">
                                    {page.content}
                                  </pre>
                                </div>
                              </TableCell>
                            </TableRow>
                          )}
                        </Fragment>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
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
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {versions.map((v) => (
                      <TableRow key={v.version}>
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
                        <TableCell>{formatDate(v.generatedAt)}</TableCell>
                        <TableCell className="text-right">
                          {v.pageCount}
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
                  {defaultVersionLabel
                    ? `v${defaultVersionLabel}`
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
