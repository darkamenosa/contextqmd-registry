import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminCrawlRequestDetail } from "@/types"
import {
  AlertTriangle,
  BookOpen,
  CheckCircle2,
  ChevronLeft,
  Clock,
  ExternalLink,
  Loader2,
  MoreHorizontal,
  RefreshCw,
  Trash2,
  XCircle,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { StatusBadge } from "@/components/admin/ui/status-badge"
import { HydratedDateTime } from "@/components/shared/hydrated-date-time"
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import AdminLayout from "@/layouts/admin-layout"

interface Props {
  crawlRequest: AdminCrawlRequestDetail
}

function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return "—"
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  const secs = seconds % 60
  if (minutes < 60) return `${minutes}m ${secs}s`
  const hours = Math.floor(minutes / 60)
  const mins = minutes % 60
  return `${hours}h ${mins}m`
}

function truncateUrl(url: string, max = 60): string {
  try {
    const u = new URL(url)
    const display = u.host + u.pathname
    return display.length > max ? display.slice(0, max) + "..." : display
  } catch {
    return url.length > max ? url.slice(0, max) + "..." : url
  }
}

interface TimelineStep {
  label: string
  time: string | null
  status: "done" | "active" | "upcoming" | "error"
}

function Timeline({ steps }: { steps: TimelineStep[] }) {
  const dotStyles = {
    done: "bg-emerald-500",
    active: "bg-amber-500 animate-pulse",
    upcoming: "bg-muted-foreground/30",
    error: "bg-red-500",
  }

  const lineStyles = {
    done: "bg-emerald-500",
    active: "bg-amber-500",
    upcoming: "bg-muted-foreground/20",
    error: "bg-red-500",
  }

  return (
    <div className="flex flex-col gap-0">
      {steps.map((step, i) => (
        <div key={step.label} className="flex gap-3">
          <div className="flex flex-col items-center">
            <div
              className={`mt-1.5 size-2.5 rounded-full ${dotStyles[step.status]}`}
            />
            {i < steps.length - 1 && (
              <div className={`mt-1 h-8 w-px ${lineStyles[step.status]}`} />
            )}
          </div>
          <div className="pb-4">
            <div className="text-sm font-medium">{step.label}</div>
            <div className="text-xs text-muted-foreground">
              {step.time ? <HydratedDateTime iso={step.time} /> : "—"}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

function ProgressBar({ current, total }: { current: number; total: number }) {
  const pct = total > 0 ? Math.min((current / total) * 100, 100) : 0
  return (
    <div className="space-y-1.5">
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>
          {current} / {total} pages
        </span>
        <span>{Math.round(pct)}%</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-amber-500 transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  )
}

export default function AdminCrawlRequestShow({ crawlRequest: cr }: Props) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [cancelling, setCancelling] = useState(false)
  const [retrying, setRetrying] = useState(false)

  const canCancel = cr.status === "pending" || cr.status === "processing"
  const canRetry = cr.status === "failed" || cr.status === "cancelled"

  function handleDelete() {
    setDeleting(true)
    router.delete(`/admin/crawl_requests/${cr.id}`, {
      onFinish: () => setDeleting(false),
    })
  }

  function handleCancel() {
    setCancelling(true)
    router.post(`/admin/crawl_requests/${cr.id}/cancellation`, undefined, {
      preserveScroll: true,
      onFinish: () => setCancelling(false),
    })
  }

  function handleRetry() {
    setRetrying(true)
    router.post(`/admin/crawl_requests/${cr.id}/retry`, undefined, {
      onFinish: () => setRetrying(false),
    })
  }

  const progressCurrent = (cr.metadata?.progress_current as number) ?? null
  const progressTotal = (cr.metadata?.progress_total as number) ?? null

  const timelineSteps: TimelineStep[] = [
    {
      label: "Created",
      time: cr.createdAt,
      status: "done",
    },
    {
      label: "Started",
      time: cr.startedAt,
      status: cr.startedAt
        ? cr.status === "processing"
          ? "active"
          : "done"
        : "upcoming",
    },
    {
      label:
        cr.status === "failed"
          ? "Failed"
          : cr.status === "cancelled"
            ? "Cancelled"
            : "Completed",
      time: cr.completedAt,
      status: cr.completedAt
        ? cr.status === "failed" || cr.status === "cancelled"
          ? "error"
          : "done"
        : cr.status === "processing"
          ? "upcoming"
          : "upcoming",
    },
  ]

  return (
    <AdminLayout>
      <Head title={`Crawl #${cr.id}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex min-w-0 items-center gap-2.5">
            <Link
              href="/admin/crawl_requests"
              aria-label="Back to crawl requests"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <h1 className="min-w-0 truncate text-lg font-semibold">
              Crawl #{cr.id}
            </h1>
            <SourceTypeIcon
              sourceType={cr.sourceType}
              showLabel
              size="size-4"
              className="text-muted-foreground"
            />
            <StatusBadge status={cr.status} />
          </div>

          {/* Desktop actions */}
          <div className="hidden items-center gap-2 sm:flex">
            {canCancel && (
              <Button
                variant="outline"
                size="sm"
                onClick={handleCancel}
                disabled={cancelling}
              >
                <XCircle className="size-4" />
                Cancel
              </Button>
            )}
            {canRetry && (
              <Button
                variant="outline"
                size="sm"
                onClick={handleRetry}
                disabled={retrying}
              >
                <RefreshCw
                  className={`size-4 ${retrying ? "animate-spin" : ""}`}
                />
                Retry
              </Button>
            )}
            <Button
              variant="destructive"
              size="sm"
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 className="size-4" />
              Delete
            </Button>
          </div>

          {/* Mobile overflow menu */}
          <div className="sm:hidden">
            <DropdownMenu>
              <DropdownMenuTrigger className="inline-flex h-8 items-center justify-center rounded-md border border-input bg-background px-3 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground">
                <MoreHorizontal className="size-4" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {canCancel && (
                  <DropdownMenuItem
                    onClick={handleCancel}
                    disabled={cancelling}
                  >
                    <XCircle className="mr-2 size-4" />
                    Cancel
                  </DropdownMenuItem>
                )}
                {canRetry && (
                  <DropdownMenuItem onClick={handleRetry} disabled={retrying}>
                    <RefreshCw className="mr-2 size-4" />
                    Retry
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onClick={() => setDeleteOpen(true)}
                  className="text-destructive focus:text-destructive"
                >
                  <Trash2 className="mr-2 size-4" />
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>

        {/* Stats row — mobile pills */}
        <div className="flex flex-wrap gap-2 sm:hidden">
          <Badge variant="outline" className="text-xs">
            <Clock className="mr-1 size-3" />
            {formatDuration(cr.durationSeconds)}
          </Badge>
          <Badge variant="outline" className="text-xs capitalize">
            {cr.requestedBundleVisibility}
          </Badge>
        </div>

        {/* Main + sidebar grid */}
        <div className="grid items-start gap-4 lg:grid-cols-5">
          <div className="flex flex-col gap-4 lg:col-span-3">
            {/* Error card — only for failed */}
            {cr.status === "failed" && cr.errorMessage && (
              <Card className="border-red-200 dark:border-red-900">
                <CardHeader className="pb-3">
                  <CardTitle className="flex items-center gap-2 text-red-700 dark:text-red-400">
                    <AlertTriangle className="size-4" />
                    Error Details
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <pre className="max-h-48 overflow-auto rounded-md bg-red-50 p-3 font-mono text-xs whitespace-pre-wrap text-red-800 dark:bg-red-950/30 dark:text-red-300">
                    {cr.errorMessage}
                  </pre>
                </CardContent>
              </Card>
            )}

            {/* Processing progress — only when processing */}
            {cr.status === "processing" && (
              <Card className="border-amber-200 dark:border-amber-900">
                <CardHeader className="pb-3">
                  <CardTitle className="flex items-center gap-2 text-amber-700 dark:text-amber-400">
                    <Loader2 className="size-4 animate-spin" />
                    In Progress
                  </CardTitle>
                  {cr.statusMessage && (
                    <CardDescription>{cr.statusMessage}</CardDescription>
                  )}
                </CardHeader>
                {progressCurrent !== null && progressTotal !== null && (
                  <CardContent>
                    <ProgressBar
                      current={progressCurrent}
                      total={progressTotal}
                    />
                  </CardContent>
                )}
              </Card>
            )}

            {/* Result card — only for completed */}
            {cr.status === "completed" && cr.libraryId && (
              <Card className="border-emerald-200 dark:border-emerald-900">
                <CardHeader className="pb-3">
                  <CardTitle className="flex items-center gap-2 text-emerald-700 dark:text-emerald-400">
                    <CheckCircle2 className="size-4" />
                    Result
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <dl className="grid grid-cols-1 gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                    <div>
                      <dt className="text-muted-foreground">Library</dt>
                      <dd className="mt-0.5">
                        <Link
                          href={`/admin/libraries/${cr.libraryId}`}
                          className="inline-flex items-center gap-1.5 font-medium hover:underline"
                        >
                          <BookOpen className="size-3.5" />
                          {cr.libraryDisplayName || cr.librarySlug}
                        </Link>
                      </dd>
                    </div>
                    {cr.librarySourceUrl && (
                      <div>
                        <dt className="text-muted-foreground">Source</dt>
                        <dd className="mt-0.5">
                          <a
                            href={cr.librarySourceUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:underline"
                          >
                            {truncateUrl(cr.librarySourceUrl, 40)}
                            <ExternalLink className="size-3" />
                          </a>
                        </dd>
                      </div>
                    )}
                  </dl>
                </CardContent>
              </Card>
            )}

            {/* Request Details */}
            <Card>
              <CardHeader>
                <CardTitle>Request Details</CardTitle>
              </CardHeader>
              <CardContent>
                <dl className="grid grid-cols-1 gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                  <div className="sm:col-span-2">
                    <dt className="text-muted-foreground">URL</dt>
                    <dd className="mt-0.5">
                      <a
                        href={cr.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1.5 font-mono text-xs break-all hover:underline"
                      >
                        {cr.url}
                        <ExternalLink className="size-3 shrink-0" />
                      </a>
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Source Type</dt>
                    <dd className="mt-0.5">
                      <SourceTypeIcon
                        sourceType={cr.sourceType}
                        showLabel
                        size="size-4"
                      />
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Visibility</dt>
                    <dd className="mt-0.5 capitalize">
                      {cr.requestedBundleVisibility}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Submitter</dt>
                    <dd className="mt-0.5">
                      <span className="font-medium">{cr.creatorName}</span>
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Duration</dt>
                    <dd className="mt-0.5 font-mono">
                      {formatDuration(cr.durationSeconds)}
                    </dd>
                  </div>
                  {cr.statusMessage && (
                    <div className="sm:col-span-2">
                      <dt className="text-muted-foreground">Status Message</dt>
                      <dd className="mt-0.5 text-sm">{cr.statusMessage}</dd>
                    </div>
                  )}
                </dl>
              </CardContent>
            </Card>

            {/* Metadata */}
            {cr.metadata && Object.keys(cr.metadata).length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle>Metadata</CardTitle>
                </CardHeader>
                <CardContent>
                  <pre className="max-h-64 overflow-auto rounded-md bg-muted p-3 font-mono text-xs">
                    {JSON.stringify(cr.metadata, null, 2)}
                  </pre>
                </CardContent>
              </Card>
            )}
          </div>

          {/* Sidebar */}
          <div className="flex flex-col gap-4 lg:col-span-2">
            {/* Timeline */}
            <Card>
              <CardHeader>
                <CardTitle>Timeline</CardTitle>
              </CardHeader>
              <CardContent>
                <Timeline steps={timelineSteps} />
                <dl className="mt-2 grid grid-cols-1 gap-y-2 border-t pt-3 text-xs text-muted-foreground">
                  <div className="flex justify-between">
                    <dt>Created</dt>
                    <dd>
                      <HydratedDateTime iso={cr.createdAt} />
                    </dd>
                  </div>
                  {cr.startedAt && (
                    <div className="flex justify-between">
                      <dt>Started</dt>
                      <dd>
                        <HydratedDateTime iso={cr.startedAt} />
                      </dd>
                    </div>
                  )}
                  {cr.completedAt && (
                    <div className="flex justify-between">
                      <dt>Finished</dt>
                      <dd>
                        <HydratedDateTime iso={cr.completedAt} />
                      </dd>
                    </div>
                  )}
                </dl>
              </CardContent>
            </Card>

            {/* Actions */}
            <Card>
              <CardHeader>
                <CardTitle>Actions</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-2">
                {canRetry && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="justify-start"
                    onClick={handleRetry}
                    disabled={retrying}
                  >
                    <RefreshCw
                      className={`size-4 ${retrying ? "animate-spin" : ""}`}
                    />
                    Retry with same URL
                  </Button>
                )}
                {canCancel && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="justify-start"
                    onClick={handleCancel}
                    disabled={cancelling}
                  >
                    <XCircle className="size-4" />
                    Cancel crawl
                  </Button>
                )}
                <Button
                  variant="outline"
                  size="sm"
                  className="justify-start text-destructive hover:text-destructive"
                  onClick={() => setDeleteOpen(true)}
                >
                  <Trash2 className="size-4" />
                  Delete request
                </Button>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {/* Delete confirmation */}
      <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete crawl request?</DialogTitle>
            <DialogDescription>
              This will permanently delete this crawl request record. The
              associated library and pages will not be affected. This cannot be
              undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeleteOpen(false)}
              disabled={deleting}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDelete}
              disabled={deleting}
            >
              {deleting ? "Deleting..." : "Yes, delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  )
}
