import { Link } from "@inertiajs/react"
import {
  ArrowUpRight,
  BarChart3,
  BookOpen,
  Clock,
  FileText,
  Medal,
  Trophy,
} from "lucide-react"

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
import PublicLayout from "@/layouts/public-layout"

interface RankedLibrary {
  rank: number
  namespace: string
  name: string
  displayName: string
  pageCount: number
  versionCount: number
  daysSinceUpdate: number
  freshnessPct: number
  score: number
  licenseStatus: string | null
  updatedAt: string
}

interface Props {
  libraries: RankedLibrary[]
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

function formatTimeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const hours = Math.floor(diff / 3600000)
  if (hours < 1) return "just now"
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export default function RankingsIndex({ libraries, totalLibraries }: Props) {
  const topLibrary = libraries[0]

  return (
    <PublicLayout
      title="Rankings — ContextQMD"
      seo={{
        description:
          "See the top-ranked documentation libraries on ContextQMD, scored by coverage, versions, and freshness.",
      }}
    >
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-8 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
              Rankings
            </h1>
            <p className="mt-4 text-lg text-muted-foreground">
              Libraries ranked by documentation coverage, version activity, and
              freshness.
            </p>
          </div>
          <Badge variant="outline" className="self-start text-sm">
            {totalLibraries} libraries
          </Badge>
        </div>

        {/* Scoring explanation */}
        <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Card>
            <CardContent className="flex items-start gap-3 pt-6">
              <FileText className="mt-0.5 size-5 shrink-0 text-primary" />
              <div>
                <div className="font-medium">Pages</div>
                <div className="text-sm text-muted-foreground">
                  More doc pages = better coverage
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
                  More versions = actively maintained
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
                  Recently updated = current docs
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Rankings Table */}
      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
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
                  <TableHead className="w-12">RANK</TableHead>
                  <TableHead>LIBRARY</TableHead>
                  <TableHead className="text-right">PAGES</TableHead>
                  <TableHead className="text-right">VERSIONS</TableHead>
                  <TableHead>FRESHNESS</TableHead>
                  <TableHead className="text-right">SCORE</TableHead>
                  <TableHead className="text-right">UPDATED</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {libraries.map((lib) => (
                  <TableRow key={`${lib.namespace}/${lib.name}`}>
                    <TableCell>
                      <RankBadge rank={lib.rank} />
                    </TableCell>
                    <TableCell>
                      <Link
                        href={`/libraries/${lib.namespace}/${lib.name}`}
                        className="group flex items-center gap-2"
                      >
                        <div>
                          <span className="font-medium text-primary group-hover:underline">
                            {lib.displayName}
                          </span>
                          <span className="ml-2 text-sm text-muted-foreground">
                            /{lib.namespace}/{lib.name}
                          </span>
                        </div>
                        <ArrowUpRight className="size-3.5 opacity-0 transition-opacity group-hover:opacity-100" />
                      </Link>
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {lib.pageCount}
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {lib.versionCount}
                    </TableCell>
                    <TableCell>
                      <FreshnessBar pct={lib.freshnessPct} />
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm font-semibold">
                      {lib.score}
                    </TableCell>
                    <TableCell className="text-right text-sm text-muted-foreground">
                      {formatTimeAgo(lib.updatedAt)}
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
