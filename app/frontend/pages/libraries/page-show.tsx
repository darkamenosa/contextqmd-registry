import { Link } from "@inertiajs/react"
import { ArrowLeft, BookOpen, ExternalLink, FileText, List } from "lucide-react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"

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

/** Strip inline HTML tags (especially img) from markdown source before rendering */
function cleanMarkdown(md: string): string {
  return md
    .replace(/<img[^>]*>/gi, "") // remove img tags
    .replace(/<br\s*\/?>/gi, "\n") // convert br to newlines
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
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
                        h1: ({ children, ...props }) => {
                          const text =
                            typeof children === "string" ? children : ""
                          const id = text.toLowerCase().replace(/[^\w]+/g, "-")
                          return (
                            <h1 id={id} {...props}>
                              {children}
                            </h1>
                          )
                        },
                        h2: ({ children, ...props }) => {
                          const text =
                            typeof children === "string" ? children : ""
                          const id = text.toLowerCase().replace(/[^\w]+/g, "-")
                          return (
                            <h2 id={id} {...props}>
                              {children}
                            </h2>
                          )
                        },
                        h3: ({ children, ...props }) => {
                          const text =
                            typeof children === "string" ? children : ""
                          const id = text.toLowerCase().replace(/[^\w]+/g, "-")
                          return (
                            <h3 id={id} {...props}>
                              {children}
                            </h3>
                          )
                        },
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
