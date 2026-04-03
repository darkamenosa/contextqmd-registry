import {
  ArrowRight,
  Cloud,
  Code,
  Database,
  Download,
  FileText,
  Search,
} from "lucide-react"

import PublicLayout from "@/layouts/public-layout"

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

/* Shared arrow for desktop flow diagrams */
function FlowArrow({
  label,
  muted = false,
}: {
  label: string
  muted?: boolean
}) {
  const color = muted ? "text-muted-foreground/30" : "text-foreground/30"
  const line = muted ? "bg-muted-foreground/30" : "bg-foreground/30"
  return (
    <div className="flex flex-1 flex-col items-center pt-6">
      <div className="flex w-full items-center">
        <div className={`h-px flex-1 ${line}`} />
        <svg
          className={`size-3 shrink-0 ${color}`}
          viewBox="0 0 12 12"
          fill="currentColor"
        >
          <path d="M0 0 L12 6 L0 12Z" />
        </svg>
      </div>
      <p className="mt-1.5 text-[10px] text-muted-foreground">{label}</p>
    </div>
  )
}

/* Shared node for desktop flow diagrams */
function FlowNode({
  icon: Icon,
  title,
  subtitle,
  accent = false,
  large = false,
  muted: _muted = false,
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  subtitle: string
  accent?: boolean
  large?: boolean
  muted?: boolean
}) {
  const boxSize = large ? "size-16" : "size-14"
  const iconSize = large ? "size-7" : "size-6"
  const border = accent ? "border-primary/30" : "border-muted-foreground/20"
  const bg = accent ? "bg-primary/5" : "bg-muted/50"
  const iconColor = accent ? "text-foreground" : "text-muted-foreground"

  return (
    <div className="flex w-1/3 flex-col items-center text-center">
      <div
        className={`flex ${boxSize} items-center justify-center rounded-xl border-2 ${border} ${bg} transition-transform hover:scale-105`}
      >
        <Icon className={`${iconSize} ${iconColor}`} />
      </div>
      <p className="mt-3 text-sm font-semibold">{title}</p>
      <p className="mt-1 text-xs text-muted-foreground">{subtitle}</p>
    </div>
  )
}

export default function About({ seo }: Props) {
  return (
    <PublicLayout seo={seo}>
      {/* Intro */}
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-16 sm:pb-12 lg:px-8">
        <div className="mx-auto max-w-3xl">
          <h1 className="text-3xl font-bold tracking-tight sm:text-5xl">
            About ContextQMD
          </h1>
          <div className="mt-6 space-y-6 text-base/relaxed text-muted-foreground sm:mt-8 sm:text-lg/relaxed">
            <p className="text-lg font-medium text-foreground sm:text-xl">
              Hey, I&apos;m Tom.
            </p>
            <p>
              I run{" "}
              <a
                href="https://turnedninja.com"
                target="_blank"
                rel="noopener noreferrer"
                className="font-medium text-foreground underline decoration-muted-foreground/40 underline-offset-4 transition-colors hover:decoration-foreground"
              >
                Turned Ninja
              </a>
              , a fanart and custom portrait studio with 30+ artists around the
              world. On the side, I build developer tools. I spend a lot of time
              inside AI coding tools like Claude Code, Codex, OpenCode and Pi,
              and I kept running into the same wall: my AI assistant would
              confidently write code using an API that was renamed two versions
              ago.
            </p>
            <p>
              Context7 MCP was one of the first tools to tackle this problem,
              and honestly, I loved the idea. But then they started requiring an
              API key just to query docs. I get it, they need to cover server
              costs and keep things sustainable. But it felt wrong to need
              credentials for something as basic as looking up how a function
              works. Every single query had to hit their servers, even when I
              was searching the same React docs for the twentieth time that day.
            </p>
            <p>
              So I built ContextQMD. Not as a replacement for Context7, but as
              something you can reach for when their credits run out, or when
              you just want your docs to live on your machine and work offline.
            </p>
          </div>
        </div>
      </section>

      {/* How Context7 MCP works */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              How Context7 MCP works
            </h2>
            <div className="mt-6 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                Context7 is a cloud-first documentation service. Every time your
                AI assistant needs docs, here&apos;s what happens:
              </p>
            </div>

            {/* Context7 flow diagram */}
            <div className="mt-10">
              {/* Desktop */}
              <div className="hidden sm:block">
                <div className="flex items-start gap-0">
                  <FlowNode
                    icon={Code}
                    title="Your AI editor"
                    subtitle="Asks a question"
                    muted
                  />
                  <FlowArrow label="every query" muted />
                  <FlowNode
                    icon={Cloud}
                    title="Context7 Cloud API"
                    subtitle="Searches on their server"
                    large
                    muted
                  />
                  <FlowArrow label="responds" muted />
                  <FlowNode
                    icon={FileText}
                    title="Snippets back"
                    subtitle="Doc results returned"
                    muted
                  />
                </div>
              </div>

              {/* Mobile */}
              <div className="flex flex-col items-center gap-0 sm:hidden">
                {[
                  {
                    icon: Code,
                    label: "Your AI editor",
                    sub: "Asks a question",
                    arrow: "every query",
                  },
                  {
                    icon: Cloud,
                    label: "Context7 Cloud API",
                    sub: "Searches on their server",
                    arrow: "responds",
                  },
                  {
                    icon: FileText,
                    label: "Snippets back",
                    sub: "Doc results returned",
                    arrow: null,
                  },
                ].map((node, i) => (
                  <div key={i} className="flex flex-col items-center">
                    <div className="flex items-center gap-3 rounded-lg border bg-muted/30 px-4 py-3">
                      <node.icon className="size-5 shrink-0 text-muted-foreground" />
                      <div>
                        <p className="text-sm font-semibold">{node.label}</p>
                        <p className="text-xs text-muted-foreground">
                          {node.sub}
                        </p>
                      </div>
                    </div>
                    {node.arrow ? (
                      <div className="flex flex-col items-center py-1">
                        <div className="h-4 w-px bg-muted-foreground/30" />
                        <ArrowRight className="size-2.5 rotate-90 text-muted-foreground/30" />
                        <span className="mt-0.5 text-[10px] text-muted-foreground">
                          {node.arrow}
                        </span>
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
            </div>

            <div className="mt-8 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                It works well until it doesn&apos;t. You burn through free
                credits during a focused coding session. The API goes down and
                your assistant falls back to stale training data. There&apos;s
                no local cache, no offline mode, no way to control what version
                of the docs you&apos;re searching.
              </p>
              <p>
                And the search itself? It happens on their servers. You
                don&apos;t know what algorithm they use, how they rank results,
                or why a query returns what it does. It&apos;s a black box.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How ContextQMD works */}
      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              How ContextQMD works
            </h2>
            <div className="mt-6 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                ContextQMD flips the model. Instead of querying a remote API
                every time, you install documentation packages to your machine,
                like npm for docs. After that, everything happens locally.
              </p>
            </div>

            {/* ContextQMD flow diagram */}
            <div className="mt-10">
              {/* Desktop */}
              <div className="hidden sm:block">
                <div className="flex items-start gap-0">
                  <FlowNode
                    icon={Download}
                    title="Install from registry"
                    subtitle="One-time download"
                    accent
                  />
                  <FlowArrow label="stored locally" />
                  <FlowNode
                    icon={Search}
                    title="QMD searches locally"
                    subtitle="BM25 + vector hybrid"
                    accent
                    large
                  />
                  <FlowArrow label="instant" />
                  <FlowNode
                    icon={Database}
                    title="Version-pinned results"
                    subtitle="Token-budgeted"
                    accent
                  />
                </div>

                {/* Annotations */}
                <div className="mt-6 flex justify-center gap-4 text-xs text-muted-foreground">
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    Works offline
                  </span>
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    No rate limits
                  </span>
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    You own the docs
                  </span>
                </div>
              </div>

              {/* Mobile */}
              <div className="flex flex-col items-center gap-0 sm:hidden">
                {[
                  {
                    icon: Download,
                    label: "Install from registry",
                    sub: "One-time download",
                    arrow: "stored locally",
                  },
                  {
                    icon: Search,
                    label: "QMD searches locally",
                    sub: "BM25 + vector hybrid",
                    arrow: "instant",
                  },
                  {
                    icon: Database,
                    label: "Version-pinned results",
                    sub: "Token-budgeted",
                    arrow: null,
                  },
                ].map((node, i) => (
                  <div key={i} className="flex flex-col items-center">
                    <div className="flex items-center gap-3 rounded-lg border border-primary/30 bg-primary/5 px-4 py-3">
                      <node.icon className="size-5 shrink-0 text-foreground" />
                      <div>
                        <p className="text-sm font-semibold">{node.label}</p>
                        <p className="text-xs text-muted-foreground">
                          {node.sub}
                        </p>
                      </div>
                    </div>
                    {node.arrow ? (
                      <div className="flex flex-col items-center py-1">
                        <div className="h-4 w-px bg-foreground/30" />
                        <ArrowRight className="size-2.5 rotate-90 text-foreground/30" />
                        <span className="mt-0.5 text-[10px] text-muted-foreground">
                          {node.arrow}
                        </span>
                      </div>
                    ) : null}
                  </div>
                ))}

                <div className="mt-4 flex flex-wrap justify-center gap-2 text-xs text-muted-foreground">
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    Works offline
                  </span>
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    No rate limits
                  </span>
                  <span className="rounded-full border border-primary/30 bg-primary/5 px-3 py-1">
                    You own the docs
                  </span>
                </div>
              </div>
            </div>

            <div className="mt-8 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                The registry at contextqmd.com is free and open. No API keys
                needed to read. The CLI and MCP server both run on your machine.
                Once docs are installed, you can search them on an airplane,
                behind a firewall, or during a Context7 outage.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Side-by-side comparison */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              The difference at a glance
            </h2>

            <div className="mt-8 overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pr-4 pb-3 font-semibold" />
                    <th className="pr-4 pb-3 font-semibold text-muted-foreground">
                      Context7
                    </th>
                    <th className="pb-3 font-semibold">ContextQMD</th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    {
                      label: "Where search runs",
                      c7: "Their cloud servers",
                      qmd: "Your machine",
                    },
                    {
                      label: "Network needed",
                      c7: "Every query",
                      qmd: "Only on install",
                    },
                    {
                      label: "Rate limits",
                      c7: "Free tier capped",
                      qmd: "None",
                    },
                    {
                      label: "Offline mode",
                      c7: "No",
                      qmd: "Full offline search",
                    },
                    {
                      label: "Version control",
                      c7: "Server picks version",
                      qmd: "You pin the version",
                    },
                    {
                      label: "Search engine",
                      c7: "Closed source",
                      qmd: "Open (BM25 + vector)",
                    },
                    {
                      label: "Registry",
                      c7: "Single provider",
                      qmd: "Open, self-hostable",
                    },
                  ].map((row, i) => (
                    <tr key={i} className="border-b last:border-b-0">
                      <td className="py-3 pr-4 font-medium">{row.label}</td>
                      <td className="py-3 pr-4 text-muted-foreground">
                        {row.c7}
                      </td>
                      <td className="py-3 text-muted-foreground">{row.qmd}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </section>

      {/* Why I built it */}
      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              Why I built it
            </h2>
            <div className="mt-6 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                I&apos;m not against cloud tools. Context7 was a genuinely
                clever idea, the first to realize that AI assistants need
                up-to-date docs, not just stale training data. I appreciate what
                they started.
              </p>
              <p>
                Around the same time, I discovered{" "}
                <a
                  href="https://github.com/tobi/qmd"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-foreground underline decoration-muted-foreground/40 underline-offset-4 transition-colors hover:decoration-foreground"
                >
                  QMD by Tobi
                </a>
                , a local hybrid search engine that combines BM25 and vector
                retrieval in a single SQLite database. I loved the idea
                instantly. It felt like the perfect match: what if docs worked
                like packages? You install them, they sit on your disk, and QMD
                searches them locally. The registry just hosts manifests and
                bundles. It doesn&apos;t need to be in the loop for every query.
              </p>
              <p>
                ContextQMD is the tool I wanted to exist. If Context7 works
                great for you, keep using it. But when you need something you
                own and control, this is here.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* What's next */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              What&apos;s next
            </h2>
            <div className="mt-6 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                Right now the biggest priority is enriching the library
                registry. The more libraries available, the more useful
                ContextQMD becomes for everyone.
              </p>
              <p>
                This is where the community comes in. If a library you use
                isn&apos;t in the registry yet, you can help by creating an
                account and submitting it. Every contribution makes the whole
                ecosystem better.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Who am I */}
      <section className="border-t bg-muted/10">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-24 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              Who&apos;s behind this?
            </h2>
            <div className="mt-6 space-y-4 text-base/relaxed text-muted-foreground sm:text-lg/relaxed">
              <p>
                It&apos;s me (Tom), founder of{" "}
                <a
                  href="https://turnedninja.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-foreground underline decoration-muted-foreground/40 underline-offset-4 transition-colors hover:decoration-foreground"
                >
                  Turned Ninja
                </a>
                . By day I run an art studio, by night I build developer tools.
                I prototype fast, ship small improvements often, and care too
                much about developer experience to let things stay broken.
              </p>
              <p>
                Got ideas, feedback, or just want to say hi? Find me on{" "}
                <a
                  href="https://x.com/hxtxmu"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-foreground underline decoration-muted-foreground/40 underline-offset-4 transition-colors hover:decoration-foreground"
                >
                  X&nbsp;(@hxtxmu)
                </a>
                .
              </p>
              <p>
                Thanks for checking this out. Let&apos;s make AI coding tools
                actually know what they&apos;re talking about.
              </p>
              <p className="font-medium text-foreground">
                Tom and the Turned Ninja crew
              </p>
            </div>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
