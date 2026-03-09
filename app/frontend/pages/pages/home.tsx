import { Link } from "@inertiajs/react"
import {
  ArrowRight,
  BookOpen,
  Download,
  Globe,
  Search,
  Server,
  Terminal,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import PublicLayout from "@/layouts/public-layout"

interface Props {
  libraryCount: number
  pageCount: number
  versionCount: number
}

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

const mcpConfig = `{
  "mcpServers": {
    "contextqmd": {
      "command": "npx",
      "args": ["-y", "contextqmd-mcp"]
    }
  }
}`

export default function Home({ libraryCount, pageCount, versionCount }: Props) {
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
        <div className="mx-auto max-w-7xl px-4 pt-20 pb-24 sm:px-6 sm:pt-28 sm:pb-32 lg:px-8">
          <div className="mx-auto max-w-3xl text-center">
            <Badge variant="outline" className="mb-4">
              Open Source Documentation Registry
            </Badge>
            <h1 className="text-5xl font-bold tracking-tight sm:text-7xl">
              Local-first docs{" "}
              <span className="text-muted-foreground">for AI</span>
            </h1>
            <p className="mx-auto mt-6 max-w-xl text-lg/relaxed text-muted-foreground">
              Install documentation packages locally. Search them with QMD.
              Version-aware, offline-capable, MCP-native.
            </p>
            <div className="mt-10 flex items-center justify-center gap-4">
              <Button
                size="lg"
                nativeButton={false}
                render={<Link href="/libraries" />}
              >
                Browse Libraries
                <ArrowRight className="size-4" />
              </Button>
              <Button
                variant="outline"
                size="lg"
                nativeButton={false}
                render={<Link href="/libraries/new" />}
              >
                Submit Library
              </Button>
            </div>
          </div>
        </div>
      </section>

      {/* Stats */}
      <section className="border-y bg-muted/30">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
          <div className="grid grid-cols-3 gap-8">
            <div className="text-center">
              <div className="text-3xl font-bold tracking-tight">
                {libraryCount}
              </div>
              <div className="mt-1 text-sm text-muted-foreground">
                Libraries
              </div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold tracking-tight">
                {versionCount}
              </div>
              <div className="mt-1 text-sm text-muted-foreground">
                Versions
              </div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold tracking-tight">
                {pageCount}
              </div>
              <div className="mt-1 text-sm text-muted-foreground">
                Doc Pages
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* MCP Quickstart */}
      <section className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
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
                <span>
                  Add the MCP server config to your editor settings
                </span>
              </div>
              <div className="flex items-start gap-3">
                <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                  2
                </div>
                <span>
                  Use <code className="rounded bg-muted px-1.5 py-0.5 text-xs">install_docs</code> to download a
                  library&apos;s documentation
                </span>
              </div>
              <div className="flex items-start gap-3">
                <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                  3
                </div>
                <span>
                  Use <code className="rounded bg-muted px-1.5 py-0.5 text-xs">search_docs</code> to find relevant
                  docs locally
                </span>
              </div>
            </div>
          </div>
          <div className="overflow-hidden rounded-xl border bg-zinc-950 text-zinc-100">
            <div className="flex items-center gap-2 border-b border-zinc-800 px-4 py-3">
              <div className="size-3 rounded-full bg-zinc-700" />
              <div className="size-3 rounded-full bg-zinc-700" />
              <div className="size-3 rounded-full bg-zinc-700" />
              <span className="ml-2 text-xs text-zinc-500">
                mcp.json
              </span>
            </div>
            <pre className="overflow-x-auto p-4 text-sm leading-relaxed">
              <code>{mcpConfig}</code>
            </pre>
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
