import { useState, type FormEvent } from "react"
import { Link, router } from "@inertiajs/react"
import {
  ArrowRight,
  BookOpen,
  Clock,
  Download,
  Globe,
  Plus,
  Search,
  Server,
  Star,
  Terminal,
  TrendingUp,
} from "lucide-react"

import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
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

interface LibraryItem {
  namespace: string
  name: string
  displayName: string
  sourceType: string | null
  homepageUrl: string | null
  defaultVersion: string | null
  version: string | null
  versionCount: number
  pageCount: number
  licenseStatus: string | null
  updatedAt: string
}

interface Props {
  libraryCount: number
  pageCount: number
  versionCount: number
  libraries: LibraryItem[]
}

function formatTimeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const hours = Math.floor(diff / 3600000)
  if (hours < 1) return "just now"
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

function formatCount(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`
  return String(n)
}

const mcpConfig = `{
  "mcpServers": {
    "contextqmd": {
      "command": "npx",
      "args": ["-y", "contextqmd-mcp"]
    }
  }
}`

const features = [
  {
    icon: Download,
    title: "Install Once, Search Locally",
    description:
      "Download documentation packages to your machine. Search stays fast and offline — no API calls per query.",
  },
  {
    icon: Search,
    title: "Hybrid Search with QMD",
    description:
      "Full-text and semantic search powered by QMD. Find the right docs instantly with BM25 + vector retrieval.",
  },
  {
    icon: Server,
    title: "MCP Native",
    description:
      "Works with Claude, Cursor, Windsurf and any MCP-compatible editor. Just add the server to your config.",
  },
  {
    icon: Globe,
    title: "Free & Open Registry",
    description:
      "All documentation is freely accessible. No API keys needed for read operations. Submit your own libraries.",
  },
  {
    icon: BookOpen,
    title: "Version-Aware Docs",
    description:
      "Pin to a specific version or follow latest. Never get outdated docs mixed with your current stack.",
  },
  {
    icon: Terminal,
    title: "Developer-First API",
    description:
      "Clean REST API for programmatic access. Resolve libraries, fetch manifests, download page bundles.",
  },
]

function LibraryTable({ libraries }: { libraries: LibraryItem[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="text-xs font-medium tracking-wider text-muted-foreground/70">
            LIBRARY
          </TableHead>
          <TableHead className="text-xs font-medium tracking-wider text-muted-foreground/70">
            SOURCE
          </TableHead>
          <TableHead className="text-right text-xs font-medium tracking-wider text-muted-foreground/70">
            PAGES
          </TableHead>
          <TableHead className="text-right text-xs font-medium tracking-wider text-muted-foreground/70">
            UPDATE
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {libraries.map((lib) => (
          <TableRow key={`${lib.namespace}/${lib.name}`}>
            <TableCell className="py-3.5">
              <Link
                href={`/libraries/${lib.namespace}/${lib.name}`}
                className="font-medium text-primary hover:underline"
              >
                {lib.displayName}
              </Link>
            </TableCell>
            <TableCell className="py-3.5">
              {lib.homepageUrl ? (
                <a
                  href={lib.homepageUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 hover:text-foreground"
                >
                  <SourceTypeIcon sourceType={lib.sourceType} size="size-4" />
                  <span className="hidden text-sm text-muted-foreground sm:inline">
                    /{lib.namespace}/{lib.name}
                  </span>
                  <span className="text-sm text-muted-foreground sm:hidden">
                    /{lib.name}
                  </span>
                </a>
              ) : (
                <span className="inline-flex items-center gap-1.5">
                  <SourceTypeIcon sourceType={lib.sourceType} size="size-4" />
                  <span className="hidden text-sm text-muted-foreground sm:inline">
                    /{lib.namespace}/{lib.name}
                  </span>
                  <span className="text-sm text-muted-foreground sm:hidden">
                    /{lib.name}
                  </span>
                </span>
              )}
            </TableCell>
            <TableCell className="py-3.5 text-right text-sm">
              {formatCount(lib.pageCount)}
            </TableCell>
            <TableCell className="py-3.5 text-right text-sm text-muted-foreground">
              {formatTimeAgo(lib.updatedAt)}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

function TableFooter({ libraryCount }: { libraryCount: number }) {
  return (
    <div className="flex items-center justify-between border-t px-4 py-3 text-xs tracking-wide text-muted-foreground">
      <span>{libraryCount.toLocaleString()} LIBRARIES</span>
      <Link
        href="/crawl"
        className="flex items-center gap-1 uppercase hover:text-foreground"
      >
        See tasks in progress
        <ArrowRight className="size-3" />
      </Link>
    </div>
  )
}

export default function Home({ libraryCount, libraries }: Props) {
  const [search, setSearch] = useState("")

  const handleSearch = (e: FormEvent) => {
    e.preventDefault()
    if (search.trim()) {
      router.get("/libraries", { query: search.trim() })
    }
  }

  // Popular: sort by page count desc (libraries with content first)
  const sortedByPopular = [...libraries].sort(
    (a, b) => b.pageCount - a.pageCount || b.versionCount - a.versionCount
  )

  const sortedByRecent = [...libraries].sort(
    (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
  )

  // Trending: libraries with most recent activity AND content
  const sortedByTrending = [...libraries]
    .filter((lib) => lib.pageCount > 0)
    .sort(
      (a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime() ||
        b.pageCount - a.pageCount
    )

  return (
    <PublicLayout
      title="ContextQMD — Local-First Docs for AI"
      seo={{
        description:
          "Local-first documentation package system for MCP. Install, search, and retrieve version-aware docs for any library.",
      }}
    >
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_30%_20%,_var(--muted)_0%,_transparent_50%)]" />
        <div className="mx-auto max-w-7xl px-4 pt-16 pb-8 sm:px-6 sm:pt-20 sm:pb-12 lg:px-8">
          <div className="mx-auto max-w-3xl text-center">
            <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">
              Up-to-date docs{" "}
              <span className="text-muted-foreground">for AI</span>
            </h1>
            <p className="mx-auto mt-4 max-w-xl text-lg/relaxed text-muted-foreground">
              Get the latest documentation into Claude, Cursor, or any
              MCP-compatible editor. Local-first, version-aware.
            </p>

            {/* Search bar */}
            <form
              onSubmit={handleSearch}
              className="mx-auto mt-8 flex max-w-lg gap-2"
            >
              <div className="relative flex-1">
                <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  type="text"
                  placeholder="Search a library (e.g. Next, React)"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-9"
                />
              </div>
              <Button type="submit">Search</Button>
            </form>
          </div>
        </div>
      </section>

      {/* Library Table — context7 style */}
      <section className="mx-auto max-w-7xl px-4 pb-12 sm:px-6 lg:px-8">
        <Tabs defaultValue="popular">
          <div className="flex items-center justify-between">
            <TabsList>
              <TabsTrigger value="popular" className="gap-1.5">
                <Star className="size-3.5" />
                Popular
              </TabsTrigger>
              <TabsTrigger value="trending" className="gap-1.5">
                <TrendingUp className="size-3.5" />
                Trending
              </TabsTrigger>
              <TabsTrigger value="recent" className="gap-1.5">
                <Clock className="size-3.5" />
                Recent
              </TabsTrigger>
            </TabsList>
            <Button
              variant="outline"
              size="sm"
              nativeButton={false}
              render={<Link href="/crawl/new" />}
            >
              <Plus className="size-4" />
              Submit Docs
            </Button>
          </div>

          <TabsContent value="popular" className="mt-4">
            <div className="overflow-x-auto rounded-xl border">
              <LibraryTable libraries={sortedByPopular} />
              <TableFooter libraryCount={libraryCount} />
            </div>
          </TabsContent>

          <TabsContent value="trending" className="mt-4">
            <div className="overflow-x-auto rounded-xl border">
              <LibraryTable libraries={sortedByTrending} />
              <TableFooter libraryCount={libraryCount} />
            </div>
          </TabsContent>

          <TabsContent value="recent" className="mt-4">
            <div className="overflow-x-auto rounded-xl border">
              <LibraryTable libraries={sortedByRecent} />
              <TableFooter libraryCount={libraryCount} />
            </div>
          </TabsContent>
        </Tabs>
      </section>

      {/* MCP Quickstart */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
            <div>
              <Badge variant="secondary" className="mb-3">
                Quick Start
              </Badge>
              <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
                Add to your editor in seconds
              </h2>
              <p className="mt-4 text-muted-foreground">
                Add ContextQMD to your MCP config. Works with Claude Desktop,
                Cursor, Windsurf, and any MCP-compatible tool.
              </p>
              <div className="mt-6 space-y-3 text-sm">
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    1
                  </div>
                  <span>Add the MCP server config to your editor settings</span>
                </div>
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    2
                  </div>
                  <span>
                    Use{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      install_docs
                    </code>{" "}
                    to download a library&apos;s documentation
                  </span>
                </div>
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    3
                  </div>
                  <span>
                    Use{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      search_docs
                    </code>{" "}
                    to find relevant docs locally
                  </span>
                </div>
              </div>
            </div>
            <div className="overflow-hidden rounded-xl border bg-zinc-950 text-zinc-100">
              <div className="flex items-center gap-2 border-b border-zinc-800 px-4 py-3">
                <div className="size-3 rounded-full bg-zinc-700" />
                <div className="size-3 rounded-full bg-zinc-700" />
                <div className="size-3 rounded-full bg-zinc-700" />
                <span className="ml-2 text-xs text-zinc-500">mcp.json</span>
              </div>
              <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                <code>{mcpConfig}</code>
              </pre>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              How it works
            </h2>
            <p className="mt-4 text-muted-foreground">
              ContextQMD is a documentation package manager for AI coding tools.
            </p>
          </div>
          <div className="mt-16 grid gap-8 md:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <Card
                key={feature.title}
                className="border-transparent bg-transparent shadow-none"
              >
                <CardHeader>
                  <div className="flex size-11 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                    <feature.icon className="size-5" />
                  </div>
                  <CardTitle className="mt-3">{feature.title}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm/relaxed text-muted-foreground">
                    {feature.description}
                  </p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Start using ContextQMD
            </h2>
            <p className="mt-4 text-lg text-muted-foreground">
              Browse the registry, install docs, and give your AI coding tools
              the context they need.
            </p>
            <div className="mt-8 flex items-center justify-center gap-4">
              <Button
                size="lg"
                nativeButton={false}
                render={<Link href="/libraries" />}
              >
                Browse Libraries
                <ArrowRight className="size-4" />
              </Button>
            </div>
            <p className="mt-4 text-xs text-muted-foreground">
              Free and open. No API key required.
            </p>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
