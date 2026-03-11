import { Head, Link } from "@inertiajs/react"
import {
  ArrowRight,
  BookOpen,
  Clock,
  FileText,
  Layers,
  Plus,
} from "lucide-react"

import { formatTimeAgo } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { StatusBadge } from "@/components/admin/ui/status-badge"
import AppLayout from "@/layouts/app-layout"

interface Stats {
  libraryCount: number
  versionCount: number
  pageCount: number
  crawlPending: number
}

interface CrawlItem {
  id: number
  url: string
  sourceType: string
  status: string
  libraryName: string | null
  librarySlug: string | null
  createdAt: string
}

interface LibraryItem {
  namespace: string
  name: string
  displayName: string
  defaultVersion: string | null
  createdAt: string
}

interface Props {
  stats: Stats
  recentCrawls: CrawlItem[]
  recentLibraries: LibraryItem[]
}

export default function AppDashboard({
  stats,
  recentCrawls,
  recentLibraries,
}: Props) {
  return (
    <AppLayout>
      <Head title="Dashboard" />

      {/* Stats */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center gap-3">
              <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10">
                <BookOpen className="size-5 text-primary" />
              </div>
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
              <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10">
                <Layers className="size-5 text-primary" />
              </div>
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
              <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10">
                <FileText className="size-5 text-primary" />
              </div>
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
              <div className="flex size-10 items-center justify-center rounded-lg bg-orange-500/10">
                <Clock className="size-5 text-orange-500" />
              </div>
              <div>
                <div className="text-2xl font-bold">{stats.crawlPending}</div>
                <div className="text-xs text-muted-foreground">Crawl Queue</div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Quick Actions */}
      <div className="mt-6 flex gap-3">
        <Button
          nativeButton={false}
          render={<Link href="/crawl/new" />}
          size="sm"
        >
          <Plus className="size-4" />
          Submit URL
        </Button>
        <Button
          variant="outline"
          nativeButton={false}
          render={<Link href="/crawl" />}
          size="sm"
        >
          View Crawl Queue
        </Button>
        <Button
          variant="outline"
          nativeButton={false}
          render={<Link href="/libraries" />}
          size="sm"
        >
          Browse Libraries
          <ArrowRight className="size-4" />
        </Button>
      </div>

      {/* Two-column layout */}
      <div className="mt-8 grid gap-6 lg:grid-cols-2">
        {/* Recent Crawl Requests */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="text-base">Your Crawl Requests</CardTitle>
            <Button
              variant="ghost"
              size="sm"
              nativeButton={false}
              render={<Link href="/crawl" />}
            >
              View all
              <ArrowRight className="size-3" />
            </Button>
          </CardHeader>
          <CardContent>
            {recentCrawls.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No crawl requests yet. Submit a URL to get started.
              </p>
            ) : (
              <div className="space-y-3">
                {recentCrawls.map((cr) => (
                  <div
                    key={cr.id}
                    className="flex items-center justify-between gap-2 rounded-lg border p-3"
                  >
                    <div className="min-w-0 flex-1">
                      {cr.librarySlug ? (
                        <Link
                          href={`/libraries/${cr.librarySlug}`}
                          className="truncate text-sm font-medium hover:underline"
                        >
                          {cr.libraryName}
                        </Link>
                      ) : (
                        <p className="truncate text-sm font-medium">{cr.url}</p>
                      )}
                      <p className="truncate text-xs text-muted-foreground">
                        {cr.url} · {formatTimeAgo(cr.createdAt, true)}
                      </p>
                    </div>
                    <StatusBadge status={cr.status} showDot={false} />
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Recent Libraries */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="text-base">Recent Libraries</CardTitle>
            <Button
              variant="ghost"
              size="sm"
              nativeButton={false}
              render={<Link href="/libraries" />}
            >
              View all
              <ArrowRight className="size-3" />
            </Button>
          </CardHeader>
          <CardContent>
            {recentLibraries.length === 0 ? (
              <p className="text-sm text-muted-foreground">No libraries yet.</p>
            ) : (
              <div className="space-y-3">
                {recentLibraries.map((lib) => (
                  <Link
                    key={`${lib.namespace}/${lib.name}`}
                    href={`/libraries/${lib.namespace}/${lib.name}`}
                    className="flex items-center justify-between gap-2 rounded-lg border p-3 transition-colors hover:bg-muted/50"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">
                        {lib.displayName}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {lib.namespace}/{lib.name}
                      </p>
                    </div>
                    {lib.defaultVersion && (
                      <Badge variant="outline" className="text-xs">
                        v{lib.defaultVersion}
                      </Badge>
                    )}
                  </Link>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  )
}
