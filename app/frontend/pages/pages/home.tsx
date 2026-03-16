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

import { formatCount, formatTimeAgo } from "@/lib/format-date"
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
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import PublicLayout from "@/layouts/public-layout"

interface LibraryItem {
  slug: string
  displayName: string
  sourceType: string | null
  homepageUrl: string | null
  pageCount: number
  updatedAt: string
}

interface Props {
  libraryCount: number
  libraries: LibraryItem[]
  activeTab: string
}

const mcpConfig = `{
  "mcpServers": {
    "contextqmd": {
      "command": "npx",
      "args": ["-y", "contextqmd-mcp"]
    }
  }
}`

const cliQuickstart = `npx -y contextqmd libraries search "kamal"
npx -y contextqmd libraries install kamal
npx -y contextqmd docs search "proxy" --library kamal`

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
    title: "CLI + MCP",
    description:
      "Use the standalone CLI in your terminal or add the MCP server to Claude, Cursor, Windsurf, and other MCP-compatible editors.",
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
      "Clean REST API for programmatic access. Resolve libraries, fetch manifests, and download compressed documentation bundles.",
  },
]

function LibraryTable({ libraries }: { libraries: LibraryItem[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead className="pl-4 text-xs font-medium tracking-wider text-muted-foreground/70">
            LIBRARY
          </TableHead>
          <TableHead className="text-xs font-medium tracking-wider text-muted-foreground/70">
            SLUG
          </TableHead>
          <TableHead className="pr-4 text-right text-xs font-medium tracking-wider text-muted-foreground/70 sm:pr-2">
            PAGES
          </TableHead>
          <TableHead className="hidden pr-4 text-right text-xs font-medium tracking-wider text-muted-foreground/70 sm:table-cell">
            UPDATE
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {libraries.map((lib) => (
          <TableRow key={lib.slug}>
            <TableCell className="py-2 pl-4">
              <Link
                href={`/libraries/${lib.slug}`}
                className="font-medium text-primary hover:underline"
              >
                {lib.displayName}
              </Link>
            </TableCell>
            <TableCell className="py-2">
              {lib.homepageUrl ? (
                <a
                  href={lib.homepageUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 hover:text-foreground"
                >
                  <SourceTypeIcon sourceType={lib.sourceType} size="size-4" />
                  <span className="text-sm text-muted-foreground">
                    {lib.slug}
                  </span>
                </a>
              ) : (
                <span className="inline-flex items-center gap-1.5">
                  <SourceTypeIcon sourceType={lib.sourceType} size="size-4" />
                  <span className="text-sm text-muted-foreground">
                    {lib.slug}
                  </span>
                </span>
              )}
            </TableCell>
            <TableCell className="py-2 pr-4 text-right text-sm sm:pr-2">
              {formatCount(lib.pageCount)}
            </TableCell>
            <TableCell className="hidden py-2 pr-4 text-right text-sm text-muted-foreground sm:table-cell">
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
    <div className="flex items-center justify-between border-t px-4 py-2.5 text-xs tracking-wide text-muted-foreground">
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

export default function Home({ libraryCount, libraries, activeTab }: Props) {
  const [search, setSearch] = useState("")

  function handleSearch(e: FormEvent) {
    e.preventDefault()
    if (search.trim()) {
      router.get("/libraries", { query: search.trim() })
    }
  }

  function handleTabChange(tab: string) {
    router.get("/", { tab }, { preserveState: true, preserveScroll: true })
  }

  return (
    <PublicLayout
      title="ContextQMD — Local-First Docs for AI"
      seo={{
        description:
          "Local-first documentation package system for CLI and MCP. Install, search, and retrieve version-aware docs for any library.",
      }}
    >
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_30%_20%,_var(--muted)_0%,_transparent_50%)]" />
        <div className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-20 sm:pb-12 lg:px-8">
          <div className="mx-auto max-w-3xl text-center">
            <h1 className="text-3xl font-bold tracking-tight sm:text-6xl">
              Local-first docs{" "}
              <span className="text-muted-foreground">for your AI editor</span>
            </h1>
            <p className="mx-auto mt-2 max-w-xl text-base/relaxed text-muted-foreground sm:mt-4 sm:text-lg/relaxed">
              Install documentation packages locally from the CLI or your MCP
              client. Search offline with hybrid retrieval, version-pinned and
              always available.
            </p>

            {/* Search bar */}
            <form
              onSubmit={handleSearch}
              className="mx-auto mt-5 flex max-w-lg gap-2 sm:mt-8"
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
        <Tabs value={activeTab} onValueChange={handleTabChange}>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
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

          <TabsContent value={activeTab} className="mt-4">
            <div className="overflow-x-auto rounded-xl border">
              {libraries.length === 0 ? (
                <div className="py-16 text-center">
                  <div className="mx-auto flex size-12 items-center justify-center rounded-xl bg-muted">
                    <BookOpen className="size-6 text-muted-foreground" />
                  </div>
                  <h2 className="mt-4 text-lg font-semibold">
                    No libraries yet
                  </h2>
                  <p className="mt-2 text-sm text-muted-foreground">
                    Be the first to submit documentation to the registry.
                  </p>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-6"
                    nativeButton={false}
                    render={<Link href="/crawl/new" />}
                  >
                    <Plus className="size-4" />
                    Submit Docs
                  </Button>
                </div>
              ) : (
                <LibraryTable libraries={libraries} />
              )}
              <TableFooter libraryCount={libraryCount} />
            </div>
          </TabsContent>
        </Tabs>
      </section>

      {/* CLI + MCP Quickstart */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
            <div>
              <Badge variant="secondary" className="mb-3">
                Quick Start
              </Badge>
              <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
                Start in your terminal or editor
              </h2>
              <p className="mt-4 text-muted-foreground">
                Use the CLI package `contextqmd` for terminal workflows, or add
                `contextqmd-mcp` to Claude Desktop, Cursor, Windsurf, and other
                MCP-compatible tools.
              </p>
              <div className="mt-6 space-y-3 text-sm">
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    1
                  </div>
                  <span>
                    Search the registry and install docs with `contextqmd`
                  </span>
                </div>
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    2
                  </div>
                  <span>
                    Search and read installed docs locally with{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      contextqmd docs search
                    </code>{" "}
                    and{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      contextqmd docs get
                    </code>
                  </span>
                </div>
                <div className="flex items-start gap-3">
                  <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    3
                  </div>
                  <span>
                    Add{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      contextqmd-mcp
                    </code>{" "}
                    to your editor if you want MCP tools like{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      install_docs
                    </code>{" "}
                    and{" "}
                    <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
                      search_docs
                    </code>
                  </span>
                </div>
              </div>
            </div>
            <div className="space-y-6">
              <div className="overflow-hidden rounded-xl border bg-zinc-950 text-zinc-100">
                <div className="flex items-center gap-2 border-b border-zinc-800 px-4 py-3">
                  <div className="size-3 rounded-full bg-red-500/70" />
                  <div className="size-3 rounded-full bg-yellow-500/70" />
                  <div className="size-3 rounded-full bg-green-500/70" />
                  <span className="ml-2 text-xs text-zinc-500">terminal</span>
                </div>
                <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                  <code>{cliQuickstart}</code>
                </pre>
              </div>
              <div className="overflow-hidden rounded-xl border bg-zinc-950 text-zinc-100">
                <div className="flex items-center gap-2 border-b border-zinc-800 px-4 py-3">
                  <div className="size-3 rounded-full bg-red-500/70" />
                  <div className="size-3 rounded-full bg-yellow-500/70" />
                  <div className="size-3 rounded-full bg-green-500/70" />
                  <span className="ml-2 text-xs text-zinc-500">mcp.json</span>
                </div>
                <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
                  <code>{mcpConfig}</code>
                </pre>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              What you get
            </h2>
            <p className="mt-4 text-muted-foreground">
              A documentation package manager with a standalone CLI and an MCP
              server, both backed by the same open registry.
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
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Try it now
            </h2>
            <p className="mt-4 text-lg text-muted-foreground">
              Install a library in one command. Give your AI coding tools the
              context they need.
            </p>
            <div className="mx-auto mt-6 max-w-md">
              <div className="overflow-hidden rounded-lg border bg-zinc-950 text-zinc-100">
                <pre className="px-4 py-3 text-sm">
                  <code>npx -y contextqmd libraries install react</code>
                </pre>
              </div>
            </div>
            <div className="mt-6 flex items-center justify-center gap-3">
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
