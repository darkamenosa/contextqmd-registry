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
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <BookOpen className="size-5 text-muted-foreground" />
                <div>
                  <div className="text-2xl font-bold">{stats.libraryCount}</div>
                  <div className="text-xs text-muted-foreground">Libraries</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <Layers className="size-5 text-muted-foreground" />
                <div>
                  <div className="text-2xl font-bold">{stats.versionCount}</div>
                  <div className="text-xs text-muted-foreground">Versions</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <FileText className="size-5 text-muted-foreground" />
                <div>
                  <div className="text-2xl font-bold">{stats.pageCount}</div>
                  <div className="text-xs text-muted-foreground">Doc Pages</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <Users className="size-5 text-muted-foreground" />
                <div>
                  <div className="text-2xl font-bold">
                    {stats.identityCount}
                  </div>
                  <div className="text-xs text-muted-foreground">Users</div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Crawl Queue Stats */}
      <div>
        <h2 className="mb-3 text-sm font-medium text-muted-foreground">
          Crawl Queue
        </h2>
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <Clock className="size-5 text-orange-500" />
                <div>
                  <div className="text-2xl font-bold">{stats.crawlPending}</div>
                  <div className="text-xs text-muted-foreground">Pending</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <Loader2 className="size-5 text-blue-500" />
                <div>
                  <div className="text-2xl font-bold">
                    {stats.crawlProcessing}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    Processing
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <CheckCircle className="size-5 text-green-500" />
                <div>
                  <div className="text-2xl font-bold">
                    {stats.crawlCompleted}
                  </div>
                  <div className="text-xs text-muted-foreground">Completed</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <XCircle className="size-5 text-red-500" />
                <div>
                  <div className="text-2xl font-bold">{stats.crawlFailed}</div>
                  <div className="text-xs text-muted-foreground">Failed</div>
                </div>
              </div>
            </CardContent>
          </Card>
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
                  <TableHead>Library</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead>Submitted By</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">When</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {recentCrawls.map((cr) => (
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
                    <TableCell className="text-sm text-muted-foreground">
                      {cr.submittedBy}
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={cr.status} />
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground">
                      {formatTimeAgo(cr.createdAt)}
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
