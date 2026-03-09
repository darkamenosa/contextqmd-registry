import { BookOpen, Code2, Globe, Search, Server, Zap } from "lucide-react"

import PublicLayout from "@/layouts/public-layout"

const principles = [
  {
    icon: Zap,
    title: "Local-First",
    description:
      "Documentation lives on your machine. Search stays fast and private — no API calls per query, no latency.",
  },
  {
    icon: Search,
    title: "Hybrid Search",
    description:
      "QMD combines BM25 full-text search with vector retrieval. Find the right docs instantly, even with vague queries.",
  },
  {
    icon: Globe,
    title: "Open Registry",
    description:
      "All documentation is freely accessible. No API keys for read operations. Anyone can submit and share libraries.",
  },
]

const techStack = [
  {
    icon: Server,
    title: "Registry",
    description: "Rails 8 + Inertia.js + React. REST API with cursor pagination. PostgreSQL with full-text search.",
  },
  {
    icon: Code2,
    title: "MCP Server",
    description: "TypeScript MCP server. Install via npx. Works with Claude, Cursor, Windsurf, and any MCP client.",
  },
  {
    icon: BookOpen,
    title: "QMD Engine",
    description: "Local hybrid search engine. BM25 + vector retrieval. SQLite-backed for zero-config setup.",
  },
]

export default function About() {
  return (
    <PublicLayout title="About">
      <section className="mx-auto max-w-7xl px-4 pt-20 pb-12 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-3xl">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            About
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">
            Documentation for the AI era
          </h1>
          <div className="mt-8 space-y-6 text-lg/relaxed text-muted-foreground">
            <p>
              ContextQMD is a documentation package system built for
              MCP-enabled AI coding tools. Instead of hitting APIs for every
              query, you install documentation packages locally and search them
              with QMD — a hybrid search engine that combines full-text and
              semantic retrieval.
            </p>
            <p>
              The registry is free and open. The MCP server runs locally.
              Your docs stay on your machine, version-pinned and
              always available — even offline.
            </p>
          </div>
        </div>
      </section>

      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Design principles
            </h2>
          </div>
          <div className="mt-16 grid gap-8 md:grid-cols-3">
            {principles.map((item) => (
              <div key={item.title} className="text-center">
                <div className="mx-auto flex size-11 items-center justify-center rounded-lg bg-muted">
                  <item.icon className="size-5 text-foreground" />
                </div>
                <h3 className="mt-5 text-lg font-semibold">{item.title}</h3>
                <p className="mt-2 text-sm/relaxed text-muted-foreground">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Tech stack
            </h2>
          </div>
          <div className="mt-16 grid gap-8 md:grid-cols-3">
            {techStack.map((item) => (
              <div key={item.title} className="text-center">
                <div className="mx-auto flex size-11 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                  <item.icon className="size-5" />
                </div>
                <h3 className="mt-5 text-lg font-semibold">{item.title}</h3>
                <p className="mt-2 text-sm/relaxed text-muted-foreground">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
