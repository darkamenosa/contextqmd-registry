import type { ComponentProps, ReactNode } from "react"
import { Link, router } from "@inertiajs/react"
import {
  CheckCircle,
  Clock,
  Code2,
  ExternalLink,
  FileText,
  GitBranch,
  Globe,
  Loader2,
  Plus,
  RefreshCw,
  XCircle,
} from "lucide-react"

import { Button } from "@/components/ui/button"
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

interface CrawlRequestItem {
  id: number
  url: string
  sourceType: string
  status: string
  errorMessage: string | null
  libraryName: string | null
  librarySlug: string | null
  createdAt: string
  updatedAt: string
}

interface Counts {
  pending: number
  processing: number
  completed: number
  failed: number
}

interface Props {
  crawlRequests: CrawlRequestItem[]
  counts: Counts
}

// --- Source type config ---

function GitHubIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  )
}

function GitLabIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 14.5L10.9 5.27H5.1L8 14.5z" />
      <path d="M8 14.5L5.1 5.27H1.22L8 14.5z" opacity={0.7} />
      <path
        d="M1.22 5.27L.34 7.98c-.08.24.01.5.22.64L8 14.5 1.22 5.27z"
        opacity={0.5}
      />
      <path d="M1.22 5.27h3.88L3.56.44c-.09-.28-.49-.28-.58 0L1.22 5.27z" />
      <path d="M8 14.5l2.9-9.23h3.88L8 14.5z" opacity={0.7} />
      <path
        d="M14.78 5.27l.88 2.71c.08.24-.01.5-.22.64L8 14.5l6.78-9.23z"
        opacity={0.5}
      />
      <path d="M14.78 5.27H10.9l1.56-4.83c.09-.28.49-.28.58 0l1.74 4.83z" />
    </svg>
  )
}

function BitbucketIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M.778 1.212a.768.768 0 00-.768.892l2.17 13.203a1.043 1.043 0 001.032.893h9.863a.768.768 0 00.768-.645l2.17-13.451a.768.768 0 00-.768-.892H.778zm9.14 9.59H6.166L5.347 5.54h5.39l-.82 5.263z" />
    </svg>
  )
}

interface SourceTypeConfig {
  label: string
  icon: ReactNode
}

function getSourceTypeConfig(sourceType: string): SourceTypeConfig {
  switch (sourceType) {
    case "github":
      return { label: "GitHub", icon: <GitHubIcon className="size-3.5" /> }
    case "gitlab":
      return { label: "GitLab", icon: <GitLabIcon className="size-3.5" /> }
    case "bitbucket":
      return {
        label: "Bitbucket",
        icon: <BitbucketIcon className="size-3.5" />,
      }
    case "git":
      return { label: "Git", icon: <GitBranch className="size-3.5" /> }
    case "website":
      return { label: "Website", icon: <Globe className="size-3.5" /> }
    case "llms_txt":
      return { label: "llms.txt", icon: <FileText className="size-3.5" /> }
    case "openapi":
      return { label: "OpenAPI", icon: <Code2 className="size-3.5" /> }
    default:
      return { label: sourceType, icon: <Globe className="size-3.5" /> }
  }
}

// --- Helpers ---

function stateDisplay(cr: CrawlRequestItem) {
  switch (cr.status) {
    case "pending":
      return (
        <span className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Clock className="size-3.5" />
          Waiting
        </span>
      )
    case "processing":
      return (
        <span className="flex items-center gap-1.5 text-sm text-primary">
          <Loader2 className="size-3.5 animate-spin" />
          Crawling...
        </span>
      )
    case "completed":
      return (
        <span className="flex items-center gap-1.5 text-sm text-green-600 dark:text-green-400">
          <CheckCircle className="size-3.5" />
          Completed
        </span>
      )
    case "failed":
      return (
        <span className="flex items-center gap-1.5 text-sm text-destructive">
          <XCircle className="size-3.5" />
          Failed
        </span>
      )
    default:
      return <span className="text-sm text-muted-foreground">{cr.status}</span>
  }
}

function formatElapsed(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return "< 1 min ago"
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

function shortenUrl(url: string): string {
  try {
    const u = new URL(url)
    return u.pathname.length > 1 ? `${u.hostname}${u.pathname}` : u.hostname
  } catch {
    return url
  }
}

// --- Task Table ---

function TaskTable({ tasks }: { tasks: CrawlRequestItem[] }) {
  if (tasks.length === 0) {
    return (
      <div className="py-12 text-center text-sm text-muted-foreground">
        No tasks in this category.
      </div>
    )
  }

  return (
    <div className="overflow-x-auto rounded-xl border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Library</TableHead>
            <TableHead>Source</TableHead>
            <TableHead>State</TableHead>
            <TableHead className="text-right">Time</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {tasks.map((cr) => {
            const source = getSourceTypeConfig(cr.sourceType)
            return (
              <TableRow key={cr.id}>
                <TableCell>
                  {cr.librarySlug ? (
                    <Link
                      href={`/libraries/${cr.librarySlug}`}
                      className="font-medium text-foreground hover:underline"
                    >
                      {cr.libraryName}
                    </Link>
                  ) : (
                    <span className="text-sm text-muted-foreground">—</span>
                  )}
                </TableCell>
                <TableCell>
                  <a
                    href={cr.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group inline-flex items-center gap-1.5"
                  >
                    <span className="text-muted-foreground">{source.icon}</span>
                    <span className="text-sm text-muted-foreground group-hover:text-foreground">
                      {shortenUrl(cr.url)}
                    </span>
                    <ExternalLink className="size-3 text-muted-foreground/50 group-hover:text-foreground" />
                  </a>
                </TableCell>
                <TableCell>{stateDisplay(cr)}</TableCell>
                <TableCell className="text-right text-sm text-muted-foreground">
                  {cr.status === "completed" || cr.status === "failed"
                    ? formatElapsed(cr.updatedAt)
                    : formatElapsed(cr.createdAt)}
                </TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}

// --- Page ---

export default function CrawlRequestsIndex({ crawlRequests, counts }: Props) {
  const active = crawlRequests.filter(
    (cr) => cr.status === "pending" || cr.status === "processing"
  )
  const completed = crawlRequests.filter(
    (cr) => cr.status === "completed" || cr.status === "failed"
  )

  const activeCount = counts.pending + counts.processing
  const completedCount = counts.completed + counts.failed

  return (
    <PublicLayout title="Documentation Queue">
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
              Documentation Queue
            </h1>
            <p className="mt-4 text-lg text-muted-foreground">
              Documentation crawling and indexing tasks.
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={() =>
                router.reload({ only: ["crawlRequests", "counts"] })
              }
            >
              <RefreshCw className="size-4" />
              Refresh
            </Button>
            <Button nativeButton={false} render={<Link href="/crawl/new" />}>
              <Plus className="size-4" />
              Add Docs
            </Button>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        <Tabs defaultValue="active">
          <TabsList>
            <TabsTrigger value="active" className="gap-1.5">
              <span className="relative flex size-2">
                {activeCount > 0 && (
                  <span className="absolute inline-flex size-full animate-ping rounded-full bg-primary opacity-75" />
                )}
                <span
                  className={`relative inline-flex size-2 rounded-full ${activeCount > 0 ? "bg-primary" : "bg-muted-foreground/40"}`}
                />
              </span>
              Active Tasks ({activeCount})
            </TabsTrigger>
            <TabsTrigger value="completed" className="gap-1.5">
              <CheckCircle className="size-3.5" />
              Completed ({completedCount})
            </TabsTrigger>
          </TabsList>

          <TabsContent value="active" className="mt-4">
            <TaskTable tasks={active} />
          </TabsContent>

          <TabsContent value="completed" className="mt-4">
            <TaskTable tasks={completed} />
          </TabsContent>
        </Tabs>
      </section>
    </PublicLayout>
  )
}
