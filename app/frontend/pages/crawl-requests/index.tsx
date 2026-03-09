import { Link } from "@inertiajs/react"
import {
  CheckCircle,
  Clock,
  ExternalLink,
  Loader2,
  Plus,
  XCircle,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
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
  submittedBy: string
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

function StatusBadge({ status }: { status: string }) {
  switch (status) {
    case "pending":
      return (
        <Badge variant="outline" className="gap-1">
          <Clock className="size-3" />
          Pending
        </Badge>
      )
    case "processing":
      return (
        <Badge variant="default" className="gap-1">
          <Loader2 className="size-3 animate-spin" />
          Processing
        </Badge>
      )
    case "completed":
      return (
        <Badge variant="secondary" className="gap-1">
          <CheckCircle className="size-3" />
          Completed
        </Badge>
      )
    case "failed":
      return (
        <Badge variant="destructive" className="gap-1">
          <XCircle className="size-3" />
          Failed
        </Badge>
      )
    default:
      return <Badge variant="outline">{status}</Badge>
  }
}

function SourceTypeBadge({ sourceType }: { sourceType: string }) {
  const labels: Record<string, string> = {
    github: "GitHub",
    gitlab: "GitLab",
    website: "Website",
    openapi: "OpenAPI",
    llms_txt: "LLMs.txt",
  }
  return (
    <Badge variant="outline" className="text-xs">
      {labels[sourceType] || sourceType}
    </Badge>
  )
}

function formatTimeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export default function CrawlRequestsIndex({ crawlRequests, counts }: Props) {
  return (
    <PublicLayout title="Crawl Queue">
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
              Crawl Queue
            </h1>
            <p className="mt-4 text-lg text-muted-foreground">
              Submit documentation URLs to be indexed into the registry.
            </p>
          </div>
          <Button
            nativeButton={false}
            render={<Link href="/crawl/new" />}
          >
            <Plus className="size-4" />
            Submit URL
          </Button>
        </div>

        {/* Stats */}
        <div className="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{counts.pending}</div>
              <div className="text-sm text-muted-foreground">Pending</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{counts.processing}</div>
              <div className="text-sm text-muted-foreground">Processing</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{counts.completed}</div>
              <div className="text-sm text-muted-foreground">Completed</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="text-2xl font-bold">{counts.failed}</div>
              <div className="text-sm text-muted-foreground">Failed</div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        {crawlRequests.length === 0 ? (
          <div className="mx-auto max-w-md py-16 text-center">
            <h2 className="mt-4 text-lg font-semibold">No crawl requests yet</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Submit a documentation URL to get started.
            </p>
          </div>
        ) : (
          <div className="rounded-xl border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>URL</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Library</TableHead>
                  <TableHead className="text-right">Submitted</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {crawlRequests.map((cr) => (
                  <TableRow key={cr.id}>
                    <TableCell>
                      <a
                        href={cr.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center gap-1 text-sm hover:underline"
                      >
                        <span className="max-w-xs truncate">{cr.url}</span>
                        <ExternalLink className="size-3 shrink-0" />
                      </a>
                      {cr.errorMessage && (
                        <p className="mt-1 text-xs text-destructive">
                          {cr.errorMessage}
                        </p>
                      )}
                    </TableCell>
                    <TableCell>
                      <SourceTypeBadge sourceType={cr.sourceType} />
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={cr.status} />
                    </TableCell>
                    <TableCell>
                      {cr.librarySlug ? (
                        <Link
                          href={`/libraries/${cr.librarySlug}`}
                          className="text-sm hover:underline"
                        >
                          {cr.libraryName}
                        </Link>
                      ) : (
                        <span className="text-sm text-muted-foreground">-</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground">
                      {formatTimeAgo(cr.createdAt)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>
    </PublicLayout>
  )
}
