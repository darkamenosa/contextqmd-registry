import { Link } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import {
  ArrowUpRight,
  BarChart3,
  BookOpen,
  Clock,
  FileText,
  Medal,
  Trophy,
} from "lucide-react"

import { formatTimeAgo } from "@/lib/format-date"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { PaginationFooter } from "@/components/shared/pagination-footer"
import PublicLayout from "@/layouts/public-layout"

interface RankedLibrary {
  rank: number
  slug: string
  displayName: string
  homepageUrl: string | null
  sourceType: string | null
  pageCount: number
  versionCount: number
  freshnessPct: number
  updatedAt: string
}

interface Props {
  libraries: RankedLibrary[]
  pagination: PaginationData
  totalLibraries: number
}

function RankBadge({ rank }: { rank: number }) {
  if (rank === 1) {
    return (
      <div className="flex size-8 items-center justify-center rounded-full bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400">
        <Trophy className="size-4" />
      </div>
    )
  }
  if (rank === 2) {
    return (
      <div className="flex size-8 items-center justify-center rounded-full bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400">
        <Medal className="size-4" />
      </div>
    )
  }
  if (rank === 3) {
    return (
      <div className="flex size-8 items-center justify-center rounded-full bg-orange-100 text-orange-600 dark:bg-orange-900/30 dark:text-orange-400">
        <Medal className="size-4" />
      </div>
    )
  }
  return (
    <div className="flex size-8 items-center justify-center rounded-full bg-muted text-sm font-medium text-muted-foreground">
      {rank}
    </div>
  )
}

function FreshnessBar({ pct }: { pct: number }) {
  const color =
    pct >= 80
      ? "bg-green-500"
      : pct >= 50
        ? "bg-yellow-500"
        : pct >= 20
          ? "bg-orange-500"
          : "bg-red-500"

  return (
    <div className="flex items-center gap-2">
      <div className="h-2 w-16 overflow-hidden rounded-full bg-muted">
        <div
          className={`h-full rounded-full ${color}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="text-xs text-muted-foreground">{pct}%</span>
    </div>
  )
}

export default function RankingsIndex({
  libraries,
  pagination,
  totalLibraries,
}: Props) {
  return (
    <PublicLayout
      title="Rankings — ContextQMD"
      seo={{
        description:
          "Documentation coverage rankings for libraries on ContextQMD. Sorted by page count, versions, and freshness.",
      }}
    >
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-16 sm:pb-12 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-5xl">
              Rankings
            </h1>
            <p className="mt-2 text-base text-muted-foreground sm:mt-4 sm:text-lg">
              Libraries ranked by documentation coverage — page count, version
              depth, and how recently docs were updated.
            </p>
          </div>
          <Badge variant="outline" className="self-start text-sm">
            {totalLibraries} libraries
          </Badge>
        </div>

        <div className="mt-4 hidden gap-4 sm:mt-8 sm:grid sm:grid-cols-3">
          <Card>
            <CardContent className="flex items-start gap-3 pt-6">
              <FileText className="mt-0.5 size-5 shrink-0 text-primary" />
              <div>
                <div className="font-medium">Pages</div>
                <div className="text-sm text-muted-foreground">
                  Total doc pages indexed for this library
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex items-start gap-3 pt-6">
              <BookOpen className="mt-0.5 size-5 shrink-0 text-primary" />
              <div>
                <div className="font-medium">Versions</div>
                <div className="text-sm text-muted-foreground">
                  Number of indexed documentation versions
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex items-start gap-3 pt-6">
              <Clock className="mt-0.5 size-5 shrink-0 text-primary" />
              <div>
                <div className="font-medium">Freshness</div>
                <div className="text-sm text-muted-foreground">
                  How recently the docs were updated
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Rankings Table */}
      <section className="mx-auto max-w-7xl px-4 pb-12 sm:px-6 sm:pb-24 lg:px-8">
        {libraries.length === 0 ? (
          <div className="mx-auto max-w-md py-16 text-center">
            <BarChart3 className="mx-auto size-12 text-muted-foreground/50" />
            <h2 className="mt-4 text-lg font-semibold">
              No libraries ranked yet
            </h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Libraries will appear here once docs are indexed.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-12 pl-4">RANK</TableHead>
                  <TableHead>LIBRARY</TableHead>
                  <TableHead className="text-right">PAGES</TableHead>
                  <TableHead className="pr-4 text-right sm:pr-2">
                    VERSIONS
                  </TableHead>
                  <TableHead className="hidden sm:table-cell">
                    FRESHNESS
                  </TableHead>
                  <TableHead className="hidden pr-4 text-right sm:table-cell">
                    UPDATED
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {libraries.map((lib) => (
                  <TableRow key={lib.slug}>
                    <TableCell className="pl-4">
                      <RankBadge rank={lib.rank} />
                    </TableCell>
                    <TableCell>
                      <Link
                        href={`/libraries/${lib.slug}`}
                        className="group flex items-center gap-2"
                      >
                        <div>
                          <span className="font-medium text-primary group-hover:underline">
                            {lib.displayName}
                          </span>
                          <span className="ml-2 hidden text-sm text-muted-foreground sm:inline">
                            {lib.slug}
                          </span>
                        </div>
                        <ArrowUpRight className="size-3.5 opacity-0 transition-opacity group-hover:opacity-100" />
                      </Link>
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {lib.pageCount}
                    </TableCell>
                    <TableCell className="pr-4 text-right font-mono text-sm sm:pr-2">
                      {lib.versionCount}
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <FreshnessBar pct={lib.freshnessPct} />
                    </TableCell>
                    <TableCell className="hidden pr-4 text-right text-sm text-muted-foreground sm:table-cell">
                      {formatTimeAgo(lib.updatedAt)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <PaginationFooter pagination={pagination} />
          </div>
        )}
      </section>
    </PublicLayout>
  )
}
