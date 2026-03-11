import type { ReactNode } from "react"
import { Link } from "@inertiajs/react"
import { ArrowLeft, BookOpen, ExternalLink, FileText, List } from "lucide-react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"

import { cleanMarkdown, formatBytes } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import PublicLayout from "@/layouts/public-layout"

interface LibrarySummary {
  namespace: string
  name: string
  displayName: string
}

interface PageDetail {
  pageUid: string
  path: string
  title: string
  url: string
  headings: string[]
  bytes: number
  content: string | null
}

interface Props {
  library: LibrarySummary
  version: string
  page: PageDetail
}

/** Recursively extract text content from React children for heading IDs */
function extractText(node: ReactNode): string {
  if (typeof node === "string") return node
  if (typeof node === "number") return String(node)
  if (!node) return ""
  if (Array.isArray(node)) return node.map(extractText).join("")
  if (typeof node === "object" && "props" in node) {
    return extractText(
      (node as { props: { children?: ReactNode } }).props.children
    )
  }
  return ""
}

function extractTextId(children: ReactNode): string {
  return extractText(children)
    .toLowerCase()
    .replace(/[^\w]+/g, "-")
}

export default function LibraryPageShow({ library, version, page }: Props) {
  const slug = `${library.namespace}/${library.name}`

  return (
    <PublicLayout title={`${page.title} - ${library.displayName} — ContextQMD`}>
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        {/* Back link */}
        <Button
          variant="ghost"
          size="sm"
          nativeButton={false}
          render={<Link href={`/libraries/${slug}?version=${version}`} />}
          className="mb-6"
        >
          <ArrowLeft className="size-4" />
          Back to {library.displayName}
        </Button>

        {/* Page header */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
              {page.title}
            </h1>
            <p className="mt-1 font-mono text-sm text-muted-foreground">
              {page.path}
            </p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Badge variant="secondary">
                <BookOpen className="mr-1 size-3" />
                {version}
              </Badge>
              <Badge variant="outline">{formatBytes(page.bytes)}</Badge>
            </div>
          </div>
          <div className="flex gap-2">
            {page.url && (
              <Button
                variant="outline"
                size="sm"
                nativeButton={false}
                render={
                  <a
                    href={page.url}
                    target="_blank"
                    rel="noopener noreferrer"
                  />
                }
              >
                <ExternalLink className="size-4" />
                Original Source
              </Button>
            )}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-8 lg:flex-row">
          {/* Table of contents sidebar */}
          {page.headings.length > 1 && (
            <aside className="shrink-0 lg:w-64">
              <Card className="sticky top-20">
                <CardHeader className="pb-3">
                  <CardTitle className="flex items-center gap-2 text-sm">
                    <List className="size-4" />
                    Table of Contents
                  </CardTitle>
                </CardHeader>
                <CardContent className="pb-4">
                  <nav className="space-y-1">
                    {page.headings.map((heading, i) => (
                      <a
                        key={`${heading}-${i}`}
                        href={`#${heading.toLowerCase().replace(/[^\w]+/g, "-")}`}
                        className="block truncate text-sm text-muted-foreground transition-colors hover:text-foreground"
                        title={heading}
                      >
                        {heading}
                      </a>
                    ))}
                  </nav>
                </CardContent>
              </Card>
            </aside>
          )}

          {/* Main content */}
          <div className="min-w-0 flex-1">
            <Card>
              <CardContent className="pt-6">
                {page.content ? (
                  <div className="prose prose-sm max-w-none dark:prose-invert prose-headings:scroll-mt-20 prose-code:before:content-none prose-code:after:content-none prose-pre:bg-zinc-950 prose-pre:text-zinc-100">
                    <ReactMarkdown
                      remarkPlugins={[remarkGfm]}
                      components={{
                        img: () => null,
                        h1: ({ children, ...props }) => (
                          <h1 id={extractTextId(children)} {...props}>
                            {children}
                          </h1>
                        ),
                        h2: ({ children, ...props }) => (
                          <h2 id={extractTextId(children)} {...props}>
                            {children}
                          </h2>
                        ),
                        h3: ({ children, ...props }) => (
                          <h3 id={extractTextId(children)} {...props}>
                            {children}
                          </h3>
                        ),
                      }}
                    >
                      {cleanMarkdown(page.content)}
                    </ReactMarkdown>
                  </div>
                ) : (
                  <div className="rounded-xl border border-dashed p-8 text-center">
                    <FileText className="mx-auto size-8 text-muted-foreground/50" />
                    <p className="mt-3 text-sm text-muted-foreground">
                      No content available for this page.
                    </p>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
