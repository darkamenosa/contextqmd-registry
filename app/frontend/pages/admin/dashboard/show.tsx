import { Head, Link } from "@inertiajs/react"
import {
  BookOpen,
  CheckCircle,
  Clock,
  ExternalLink,
  FileText,
  Layers,
  Loader2,
  Users,
  XCircle,
} from "lucide-react"

import { formatTimeAgo } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { StatusBadge } from "@/components/admin/ui/status-badge"
import AdminLayout from "@/layouts/admin-layout"

interface Stats {
  libraryCount: number
  versionCount: number
  pageCount: number
  identityCount: number
  crawlPending: number
  crawlProcessing: number
  crawlCompleted: number
  crawlFailed: number
}

interface CrawlItem {
  id: number
  url: string
  sourceType: string
  status: string
  errorMessage: string | null
  submittedBy: string
  libraryName: string | null
  librarySlug: string | null
  createdAt: string
}

interface Props {
  stats: Stats
  recentCrawls: CrawlItem[]
}

function CrawlStatusBadge({ status }: { status: string }) {
  switch (status) {
    case "pending":
      return (
        <StatusBadge status={status} showDot={false}>
          <Clock className="size-3" />
          Pending
        </StatusBadge>
      )
    case "processing":
      return (
        <StatusBadge status={status} showDot={false}>
          <Loader2 className="size-3 animate-spin" />
          Processing
        </StatusBadge>
      )
    case "completed":
      return (
        <StatusBadge status={status} showDot={false}>
          <CheckCircle className="size-3" />
          Completed
        </StatusBadge>
      )
    case "failed":
      return (
        <StatusBadge status={status} showDot={false}>
          <XCircle className="size-3" />
          Failed
        </StatusBadge>
      )
    default:
      return <StatusBadge status={status} showDot={false} />
  }
}

export default function AdminDashboard({ stats, recentCrawls }: Props) {
  return (
    <AdminLayout>
      <Head title="Admin Dashboard" />

      {/* Registry Stats */}
      <div>
        <h1 className="text-lg font-semibold">Dashboard</h1>
        <h2 className="mt-4 mb-3 text-sm font-medium text-muted-foreground">
          Registry
        </h2>
        {/* Mobile: pills */}
        <div className="flex flex-wrap gap-2 sm:hidden">
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <BookOpen className="size-3" />
            {stats.libraryCount} libraries
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Layers className="size-3" />
            {stats.versionCount} versions
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <FileText className="size-3" />
            {stats.pageCount} pages
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Users className="size-3" />
            {stats.identityCount} users
          </Badge>
        </div>
        {/* Desktop: single card strip with dividers */}
        <div className="hidden grid-cols-4 divide-x rounded-lg border bg-card text-card-foreground sm:grid">
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <BookOpen className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.libraryCount}</div>
              <div className="text-xs text-muted-foreground">Libraries</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Layers className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.versionCount}</div>
              <div className="text-xs text-muted-foreground">Versions</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <FileText className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.pageCount}</div>
              <div className="text-xs text-muted-foreground">Doc Pages</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Users className="size-4 text-muted-foreground" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.identityCount}</div>
              <div className="text-xs text-muted-foreground">Users</div>
            </div>
          </div>
        </div>
      </div>

      {/* Crawl Queue Stats */}
      <div>
        <h2 className="mb-3 text-sm font-medium text-muted-foreground">
          Crawl Queue
        </h2>
        {/* Mobile: pills */}
        <div className="flex flex-wrap gap-2 sm:hidden">
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Clock className="size-3 text-orange-500" />
            {stats.crawlPending} pending
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <Loader2 className="size-3 text-blue-500" />
            {stats.crawlProcessing} processing
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <CheckCircle className="size-3 text-green-500" />
            {stats.crawlCompleted} completed
          </Badge>
          <Badge variant="secondary" className="gap-1.5 px-2.5 py-1 text-xs">
            <XCircle className="size-3 text-red-500" />
            {stats.crawlFailed} failed
          </Badge>
        </div>
        {/* Desktop: single card strip with dividers */}
        <div className="hidden grid-cols-4 divide-x rounded-lg border bg-card text-card-foreground sm:grid">
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Clock className="size-4 text-orange-500" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.crawlPending}</div>
              <div className="text-xs text-muted-foreground">Pending</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <Loader2 className="size-4 text-blue-500" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.crawlProcessing}</div>
              <div className="text-xs text-muted-foreground">Processing</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <CheckCircle className="size-4 text-green-500" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.crawlCompleted}</div>
              <div className="text-xs text-muted-foreground">Completed</div>
            </div>
          </div>
          <div className="flex items-center gap-3 px-4 py-3">
            <div className="rounded-md bg-muted p-2">
              <XCircle className="size-4 text-red-500" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stats.crawlFailed}</div>
              <div className="text-xs text-muted-foreground">Failed</div>
            </div>
          </div>
        </div>
      </div>

      {/* Recent Crawl Requests */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">Recent Crawl Requests</CardTitle>
          <Button
            variant="ghost"
            size="sm"
            nativeButton={false}
            render={<Link href="/crawl" />}
          >
            View all
          </Button>
        </CardHeader>
        <CardContent>
          {recentCrawls.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No crawl requests yet.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="pl-4">Library</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead className="hidden sm:table-cell">
                    Submitted By
                  </TableHead>
                  <TableHead className="pr-4 sm:pr-2">Status</TableHead>
                  <TableHead className="hidden pr-4 text-right sm:table-cell">
                    When
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {recentCrawls.map((cr) => (
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
                        className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
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
                    <TableCell className="hidden text-sm text-muted-foreground sm:table-cell">
                      {cr.submittedBy}
                    </TableCell>
                    <TableCell className="pr-4 sm:pr-2">
                      <CrawlStatusBadge status={cr.status} />
                    </TableCell>
                    <TableCell className="hidden pr-4 text-right text-sm text-muted-foreground sm:table-cell">
                      {formatTimeAgo(cr.createdAt, true)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </AdminLayout>
  )
}
