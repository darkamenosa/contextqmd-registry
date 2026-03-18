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
    description:
      "Free, open API at contextqmd.com. Browse libraries, resolve versions, fetch manifests, and download compressed documentation bundles.",
  },
  {
    icon: Code2,
    title: "CLI + MCP Server",
    description:
      "Use the `contextqmd` CLI in your terminal for install and search workflows, or add `contextqmd-mcp` to Claude, Cursor, Windsurf, and other MCP-compatible editors.",
  },
  {
    icon: BookOpen,
    title: "QMD Engine",
    description:
      "Local hybrid search combining BM25 full-text and semantic vector retrieval. Zero-config, SQLite-backed, works fully offline.",
  },
]

interface SeoData {
  title?: string
  description?: string
  url?: string
  type?: "website" | "article" | "product"
  noindex?: boolean
  image?: string
}

interface Props {
  seo?: SeoData
}

export default function About({ seo }: Props) {
  return (
    <PublicLayout seo={seo}>
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-16 sm:pb-12 lg:px-8">
        <div className="mx-auto max-w-3xl">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            About
          </p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight sm:text-5xl">
            Documentation for the AI era
          </h1>
          <div className="mt-4 space-y-6 text-base/relaxed text-muted-foreground sm:mt-8 sm:text-lg/relaxed">
            <p>
              AI coding tools work best when they have accurate, up-to-date
              documentation. But most approaches either hit an API on every
              query or dump an entire docs site into context.
            </p>
            <p>
              ContextQMD takes a different approach: install documentation
              packages locally, search them with QMD — a hybrid engine combining
              BM25 full-text and semantic vector retrieval — and get
              version-pinned results without network calls.
            </p>
            <p>
              The registry is free and open. The CLI and MCP server both run on
              your machine. Your docs stay local, version-pinned, and available
              even offline.
            </p>
          </div>
        </div>
      </section>

      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
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
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              How it fits together
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
