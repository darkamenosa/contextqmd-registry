import { Link, router } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import {
  CheckCircle,
  Clock,
  ExternalLink,
  FolderOpen,
  Loader2,
  Plus,
  RefreshCw,
  Sparkles,
  XCircle,
} from "lucide-react"

import { formatTimeAgo } from "@/lib/format-date"
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
import { PaginationFooter } from "@/components/shared/pagination-footer"
import { getSourceTypeConfig } from "@/components/shared/source-type-icon"
import PublicLayout from "@/layouts/public-layout"

interface CrawlRequestItem {
  id: number
  url: string
  sourceType: string
  status: string
  libraryName: string | null
  librarySlug: string | null
  createdAt: string
  updatedAt: string
  statusMessage: string | null
  progressCurrent: number | null
  progressTotal: number | null
}

interface Counts {
  pending: number
  processing: number
  completed: number
  failed: number
}

interface Props {
  crawlRequests: CrawlRequestItem[]
  pagination: PaginationData
  activeTab: string
  counts: Counts
}

// --- Helpers ---

function stateDisplay(cr: CrawlRequestItem) {
  switch (cr.status) {
    case "pending":
      return (
        <span className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Clock className="size-3.5" />
          {cr.statusMessage || "Waiting"}
        </span>
      )
    case "processing": {
      const pct =
        cr.progressCurrent && cr.progressTotal
          ? Math.round((cr.progressCurrent / cr.progressTotal) * 100)
          : null
      return (
        <div className="flex flex-col gap-1">
          <span className="flex items-center gap-1.5 text-sm text-primary">
            <Loader2 className="size-3.5 animate-spin" />
            {cr.statusMessage || "Crawling..."}
          </span>
          {pct !== null && (
            <div className="flex items-center gap-2">
              <div className="h-1.5 w-20 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary transition-all"
                  style={{ width: `${pct}%` }}
                />
              </div>
              <span className="text-xs text-muted-foreground">
                {cr.progressCurrent}/{cr.progressTotal}
              </span>
            </div>
          )}
        </div>
      )
    }
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

function shortenUrl(url: string): string {
  try {
    const u = new URL(url)
    return u.pathname.length > 1 ? `${u.hostname}${u.pathname}` : u.hostname
  } catch {
    return url
  }
}

// --- Task Table ---

function ActiveEmptyState() {
  return (
    <div className="flex flex-col items-center py-20">
      <div className="relative mb-6">
        <div className="flex size-16 items-center justify-center rounded-2xl border border-dashed border-border/80 bg-muted/40">
          <Sparkles className="size-7 text-muted-foreground/60" />
        </div>
        <div className="absolute -top-1 -right-1 flex size-5 items-center justify-center rounded-full bg-primary text-primary-foreground">
          <Plus className="size-3" />
        </div>
      </div>
      <h3 className="text-base font-semibold tracking-tight">
        No active tasks
      </h3>
      <p className="mt-1.5 max-w-sm text-center text-sm/6 text-muted-foreground">
        Submit a documentation URL to start crawling. We&apos;ll fetch, parse,
        and index it into the registry.
      </p>
      <Button
        nativeButton={false}
        render={<Link href="/crawl/new" />}
        className="mt-5"
        size="sm"
      >
        <Plus className="size-3.5" />
        Add Docs
      </Button>
    </div>
  )
}

function CompletedEmptyState() {
  return (
    <div className="flex flex-col items-center py-20">
      <div className="mb-6 flex size-16 items-center justify-center rounded-2xl border border-border/60 bg-muted/30">
        <FolderOpen className="size-7 text-muted-foreground/50" />
      </div>
      <h3 className="text-base font-semibold tracking-tight">
        Nothing here yet
      </h3>
      <p className="mt-1.5 max-w-sm text-center text-sm/6 text-muted-foreground">
        Completed and failed crawl tasks will appear here once they finish
        processing.
      </p>
    </div>
  )
}

function TaskTable({
  tasks,
  variant,
  pagination,
  activeTab,
}: {
  tasks: CrawlRequestItem[]
  variant: "active" | "completed"
  pagination: PaginationData
  activeTab: string
}) {
  if (tasks.length === 0) {
    return variant === "active" ? <ActiveEmptyState /> : <CompletedEmptyState />
  }

  return (
    <div className="overflow-x-auto rounded-xl border">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead className="pl-4 text-xs font-medium tracking-wider text-muted-foreground/70">
              LIBRARY
            </TableHead>
            <TableHead className="text-xs font-medium tracking-wider text-muted-foreground/70">
              SOURCE
            </TableHead>
            <TableHead className="pr-4 text-xs font-medium tracking-wider text-muted-foreground/70 sm:pr-2">
              STATE
            </TableHead>
            <TableHead className="hidden pr-4 text-right text-xs font-medium tracking-wider text-muted-foreground/70 sm:table-cell">
              TIME
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {tasks.map((cr) => {
            const source = getSourceTypeConfig(cr.sourceType)
            return (
              <TableRow key={cr.id}>
                <TableCell className="pl-4">
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
                <TableCell className="pr-4 sm:pr-2">
                  {stateDisplay(cr)}
                </TableCell>
                <TableCell className="hidden pr-4 text-right text-sm text-muted-foreground sm:table-cell">
                  {cr.status === "completed" || cr.status === "failed"
                    ? formatTimeAgo(cr.updatedAt, true)
                    : formatTimeAgo(cr.createdAt, true)}
                </TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
      <PaginationFooter
        pagination={pagination}
        buildParams={(page) => ({ tab: activeTab, page })}
      />
    </div>
  )
}

// --- Page ---

export default function CrawlRequestsIndex({
  crawlRequests,
  pagination,
  activeTab,
  counts,
}: Props) {
  const activeCount = counts.pending + counts.processing
  const completedCount = counts.completed + counts.failed

  function handleTabChange(tab: string) {
    router.get("/crawl", { tab }, { preserveState: true, preserveScroll: true })
  }

  return (
    <PublicLayout title="Documentation Queue">
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-16 sm:pb-12 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-5xl">
              Documentation Queue
            </h1>
            <p className="mt-2 text-base text-muted-foreground sm:mt-4 sm:text-lg">
              Track active and completed documentation crawl jobs submitted to
              the registry.
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={() =>
                router.reload({
                  only: ["crawlRequests", "counts", "pagination"],
                })
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
        <Tabs value={activeTab} onValueChange={handleTabChange}>
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

          <TabsContent value={activeTab} className="mt-4">
            <TaskTable
              tasks={crawlRequests}
              variant={activeTab === "completed" ? "completed" : "active"}
              pagination={pagination}
              activeTab={activeTab}
            />
          </TabsContent>
        </Tabs>
      </section>
    </PublicLayout>
  )
}
