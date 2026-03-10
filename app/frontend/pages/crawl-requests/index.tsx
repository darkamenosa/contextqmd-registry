import { Link, router } from "@inertiajs/react"
import {
  CheckCircle,
  Clock,
  Loader2,
  Plus,
  RefreshCw,
  XCircle,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
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

const sourceTypeLabels: Record<string, string> = {
  github: "GitHub",
  gitlab: "GitLab",
  website: "Website",
  openapi: "OpenAPI",
  llms_txt: "LLMs.txt",
}

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
          {cr.librarySlug ? (
            <Link
              href={`/libraries/${cr.librarySlug}`}
              className="hover:underline"
            >
              {cr.libraryName}
            </Link>
          ) : (
            "Done"
          )}
        </span>
      )
    case "failed":
      return (
        <span className="flex items-center gap-1.5 text-sm text-destructive">
          <XCircle className="size-3.5" />
          {cr.errorMessage || "Failed"}
        </span>
      )
    default:
      return (
        <span className="text-sm text-muted-foreground">{cr.status}</span>
      )
  }
}

function formatElapsed(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return "< 1 minute"
  if (minutes < 60) return `${minutes} minute${minutes !== 1 ? "s" : ""}`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} hour${hours !== 1 ? "s" : ""}`
  const days = Math.floor(hours / 24)
  return `${days} day${days !== 1 ? "s" : ""}`
}

function shortenUrl(url: string): string {
  try {
    const u = new URL(url)
    return u.pathname.length > 1 ? `${u.hostname}${u.pathname}` : u.hostname
  } catch {
    return url
  }
}

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
            <TableHead>SOURCE</TableHead>
            <TableHead>TASK TYPE</TableHead>
            <TableHead>STATE</TableHead>
            <TableHead className="text-right">ELAPSED TIME</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {tasks.map((cr) => (
            <TableRow key={cr.id}>
              <TableCell>
                <a
                  href={cr.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-primary hover:underline"
                >
                  {shortenUrl(cr.url)}
                </a>
              </TableCell>
              <TableCell>
                <Badge variant="outline" className="text-xs">
                  {sourceTypeLabels[cr.sourceType] || cr.sourceType}
                </Badge>
              </TableCell>
              <TableCell>{stateDisplay(cr)}</TableCell>
              <TableCell className="text-right text-sm text-muted-foreground">
                {cr.status === "completed" || cr.status === "failed"
                  ? `${formatElapsed(cr.updatedAt)} ago`
                  : formatElapsed(cr.createdAt)}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}

export default function CrawlRequestsIndex({ crawlRequests, counts }: Props) {
  const active = crawlRequests.filter(
    (cr) => cr.status === "pending" || cr.status === "processing",
  )
  const completed = crawlRequests.filter(
    (cr) => cr.status === "completed" || cr.status === "failed",
  )

  const activeCount = counts.pending + counts.processing
  const completedCount = counts.completed + counts.failed

  return (
    <PublicLayout title="Add Documentation">
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
            <Button
              nativeButton={false}
              render={<Link href="/crawl/new" />}
            >
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
              <Loader2 className="size-3.5" />
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
