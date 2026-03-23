import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminProxyConfigDetail, AdminProxyLease } from "@/types"
import {
  Activity,
  ChevronLeft,
  Clock,
  Network,
  Pencil,
  Power,
  PowerOff,
  RefreshCw,
  Server,
  Shield,
  Trash2,
  Zap,
} from "lucide-react"

import { formatDateTime } from "@/lib/format-date"
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { StatusBadge } from "@/components/admin/ui/status-badge"
import AdminLayout from "@/layouts/admin-layout"

interface Props {
  proxyConfig: AdminProxyConfigDetail
  leases: AdminProxyLease[]
}

function HealthStatus({ config }: { config: AdminProxyConfigDetail }) {
  if (!config.active) {
    return (
      <div className="flex items-center gap-2">
        <StatusBadge status="inactive" />
        {config.disabledReason && (
          <span className="text-xs text-muted-foreground">
            {config.disabledReason}
          </span>
        )}
      </div>
    )
  }
  if (config.cooldownUntil && new Date(config.cooldownUntil) > new Date()) {
    return (
      <div className="flex items-center gap-2">
        <StatusBadge status="suspended">Cooldown</StatusBadge>
        <span className="text-xs text-muted-foreground">
          until {formatDateTime(config.cooldownUntil)}
        </span>
      </div>
    )
  }
  if (config.consecutiveFailures > 0) {
    return (
      <div className="flex items-center gap-2">
        <StatusBadge status="pending">
          {config.consecutiveFailures} consecutive failure
          {config.consecutiveFailures !== 1 && "s"}
        </StatusBadge>
      </div>
    )
  }
  return <StatusBadge status="active">Healthy</StatusBadge>
}

function CapacityRing({ active, max }: { active: number; max: number }) {
  const pct = max > 0 ? (active / max) * 100 : 0
  const radius = 36
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (pct / 100) * circumference
  const color =
    pct >= 90
      ? "stroke-red-500"
      : pct >= 60
        ? "stroke-amber-500"
        : "stroke-emerald-500"

  return (
    <div className="flex items-center gap-3">
      <svg width="80" height="80" viewBox="0 0 80 80">
        <circle
          cx="40"
          cy="40"
          r={radius}
          fill="none"
          className="stroke-muted"
          strokeWidth="6"
        />
        <circle
          cx="40"
          cy="40"
          r={radius}
          fill="none"
          className={color}
          strokeWidth="6"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          transform="rotate(-90 40 40)"
          style={{ transition: "stroke-dashoffset 0.5s ease" }}
        />
        <text
          x="40"
          y="37"
          textAnchor="middle"
          className="fill-foreground text-lg font-bold"
          fontSize="18"
        >
          {active}
        </text>
        <text
          x="40"
          y="52"
          textAnchor="middle"
          className="fill-muted-foreground text-[10px]"
          fontSize="10"
        >
          of {max}
        </text>
      </svg>
      <div>
        <div className="text-sm font-medium">Active Leases</div>
        <div className="text-xs text-muted-foreground">
          {max - active} slot{max - active !== 1 && "s"} available
        </div>
      </div>
    </div>
  )
}

export default function AdminProxyConfigShow({
  proxyConfig: config,
  leases,
}: Props) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [toggling, setToggling] = useState(false)
  const [resetting, setResetting] = useState(false)

  function handleDelete() {
    setDeleting(true)
    router.delete(`/admin/proxy_configs/${config.id}`, {
      onFinish: () => setDeleting(false),
    })
  }

  function handleToggleActive() {
    setToggling(true)
    router.patch(
      `/admin/proxy_configs/${config.id}`,
      { proxy_config: { active: !config.active } },
      {
        preserveScroll: true,
        onFinish: () => setToggling(false),
      }
    )
  }

  function handleResetHealth() {
    setResetting(true)
    router.patch(
      `/admin/proxy_configs/${config.id}`,
      {
        proxy_config: {
          consecutive_failures: 0,
          cooldown_until: null,
          last_error_class: null,
        },
      },
      {
        preserveScroll: true,
        onFinish: () => setResetting(false),
      }
    )
  }

  const activeLeases = leases.filter((l) => l.active)

  return (
    <AdminLayout>
      <Head title={config.name} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <Link
              href="/admin/proxy_configs"
              aria-label="Back to proxy pool"
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <ChevronLeft className="size-4" />
            </Link>
            <h1 className="min-w-0 truncate text-lg font-semibold">
              {config.name}
            </h1>
            <Badge variant="outline" className="font-mono text-xs">
              {config.scheme}://{config.host}:{config.port}
            </Badge>
          </div>
          <div className="flex items-center gap-2">
            {config.consecutiveFailures > 0 && (
              <Button
                variant="outline"
                size="sm"
                onClick={handleResetHealth}
                disabled={resetting}
              >
                <RefreshCw
                  className={`size-4 ${resetting ? "animate-spin" : ""}`}
                />
                Reset Health
              </Button>
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={handleToggleActive}
              disabled={toggling}
            >
              {config.active ? (
                <>
                  <PowerOff className="size-4" />
                  Disable
                </>
              ) : (
                <>
                  <Power className="size-4" />
                  Enable
                </>
              )}
            </Button>
            <Button
              variant="outline"
              size="sm"
              nativeButton={false}
              render={<Link href={`/admin/proxy_configs/${config.id}/edit`} />}
            >
              <Pencil className="size-4" />
              Edit
            </Button>
            <Button
              variant="destructive"
              size="sm"
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 className="size-4" />
              Delete
            </Button>
          </div>
        </div>

        {/* Main + sidebar grid */}
        <div className="grid items-start gap-4 lg:grid-cols-5">
          <div className="flex flex-col gap-4 lg:col-span-3">
            {/* Connection details */}
            <Card>
              <CardHeader>
                <CardTitle>Connection Details</CardTitle>
              </CardHeader>
              <CardContent>
                <dl className="grid grid-cols-1 gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-muted-foreground">Name</dt>
                    <dd className="mt-0.5 font-medium">{config.name}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Provider</dt>
                    <dd className="mt-0.5 font-medium">
                      {config.provider || (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Scheme</dt>
                    <dd className="mt-0.5">
                      <Badge variant="outline" className="uppercase">
                        {config.scheme}
                      </Badge>
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Host</dt>
                    <dd className="mt-0.5 font-mono text-sm">{config.host}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Port</dt>
                    <dd className="mt-0.5 font-mono text-sm">{config.port}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Username</dt>
                    <dd className="mt-0.5 font-mono text-sm">
                      {config.username || (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Kind</dt>
                    <dd className="mt-0.5 capitalize">
                      {config.kind || (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Usage Scope</dt>
                    <dd className="mt-0.5">
                      <Badge variant="secondary">{config.usageScope}</Badge>
                    </dd>
                  </div>
                  {config.notes && (
                    <div className="sm:col-span-2">
                      <dt className="text-muted-foreground">Notes</dt>
                      <dd className="mt-0.5 text-sm">{config.notes}</dd>
                    </div>
                  )}
                </dl>
              </CardContent>
            </Card>

            {/* Health & Performance */}
            <Card>
              <CardHeader>
                <CardTitle>Health & Performance</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  <div>
                    <dt className="mb-1 text-sm text-muted-foreground">
                      Status
                    </dt>
                    <dd>
                      <HealthStatus config={config} />
                    </dd>
                  </div>
                  <dl className="grid grid-cols-1 gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                    <div>
                      <dt className="text-muted-foreground">
                        Consecutive Failures
                      </dt>
                      <dd className="mt-0.5 font-mono text-lg font-bold">
                        {config.consecutiveFailures}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">Last Error</dt>
                      <dd className="mt-0.5 font-mono text-xs">
                        {config.lastErrorClass || (
                          <span className="text-muted-foreground">None</span>
                        )}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">Last Success</dt>
                      <dd className="mt-0.5 text-sm">
                        {config.lastSuccessAt ? (
                          formatDateTime(config.lastSuccessAt)
                        ) : (
                          <span className="text-muted-foreground">Never</span>
                        )}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">Last Failure</dt>
                      <dd className="mt-0.5 text-sm">
                        {config.lastFailureAt ? (
                          formatDateTime(config.lastFailureAt)
                        ) : (
                          <span className="text-muted-foreground">Never</span>
                        )}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">Last Target</dt>
                      <dd className="mt-0.5 font-mono text-xs">
                        {config.lastTargetHost || (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">Created</dt>
                      <dd className="mt-0.5 text-sm">
                        {formatDateTime(config.createdAt)}
                      </dd>
                    </div>
                  </dl>
                </div>
              </CardContent>
            </Card>

            {/* Active Leases */}
            <Card>
              <CardHeader>
                <CardTitle>Recent Leases</CardTitle>
                <CardDescription>
                  {activeLeases.length} active, {leases.length} total shown
                </CardDescription>
              </CardHeader>
              <CardContent className="p-0">
                {leases.length === 0 ? (
                  <p className="px-6 pb-6 text-sm text-muted-foreground">
                    No leases recorded yet.
                  </p>
                ) : (
                  <>
                    <div className="divide-y sm:hidden">
                      {leases.map((lease) => (
                        <article key={lease.id} className="space-y-3 px-4 py-4">
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0">
                              <p className="font-mono text-xs break-all">
                                {lease.sessionKey}
                              </p>
                              <div className="mt-2 flex flex-wrap gap-2">
                                <Badge variant="secondary" className="text-xs">
                                  {lease.usageScope}
                                </Badge>
                                {lease.stickySession && (
                                  <Badge
                                    variant="outline"
                                    className="text-[10px]"
                                  >
                                    sticky
                                  </Badge>
                                )}
                              </div>
                            </div>
                            {lease.active ? (
                              <StatusBadge status="active" />
                            ) : lease.releasedAt ? (
                              <StatusBadge status="completed">
                                Released
                              </StatusBadge>
                            ) : (
                              <StatusBadge status="expired" />
                            )}
                          </div>
                          <div className="grid grid-cols-2 gap-3 text-xs text-muted-foreground">
                            <div>
                              <p className="uppercase">Target</p>
                              <p className="mt-1 break-all text-foreground">
                                {lease.targetHost || "—"}
                              </p>
                            </div>
                            <div>
                              <p className="uppercase">Last seen</p>
                              <p className="mt-1 text-foreground">
                                {formatDateTime(lease.lastSeenAt)}
                              </p>
                            </div>
                          </div>
                        </article>
                      ))}
                    </div>

                    <div className="hidden overflow-x-auto sm:block">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="pl-4">Session</TableHead>
                            <TableHead className="hidden sm:table-cell">
                              Scope
                            </TableHead>
                            <TableHead className="hidden sm:table-cell">
                              Target
                            </TableHead>
                            <TableHead className="pr-4 sm:pr-2">
                              Status
                            </TableHead>
                            <TableHead className="hidden pr-4 text-right sm:table-cell">
                              Last Seen
                            </TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {leases.map((lease) => (
                            <TableRow key={lease.id}>
                              <TableCell className="pl-4 font-mono text-xs">
                                {lease.sessionKey.length > 24
                                  ? `${lease.sessionKey.slice(0, 24)}...`
                                  : lease.sessionKey}
                                {lease.stickySession && (
                                  <Badge
                                    variant="outline"
                                    className="ml-2 text-[10px]"
                                  >
                                    sticky
                                  </Badge>
                                )}
                              </TableCell>
                              <TableCell className="hidden sm:table-cell">
                                <Badge variant="secondary" className="text-xs">
                                  {lease.usageScope}
                                </Badge>
                              </TableCell>
                              <TableCell className="hidden font-mono text-xs text-muted-foreground sm:table-cell">
                                {lease.targetHost || "—"}
                              </TableCell>
                              <TableCell className="pr-4 sm:pr-2">
                                {lease.active ? (
                                  <StatusBadge status="active" />
                                ) : lease.releasedAt ? (
                                  <StatusBadge status="completed">
                                    Released
                                  </StatusBadge>
                                ) : (
                                  <StatusBadge status="expired" />
                                )}
                              </TableCell>
                              <TableCell className="hidden pr-4 text-right text-xs text-muted-foreground sm:table-cell">
                                {formatDateTime(lease.lastSeenAt)}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  </>
                )}
              </CardContent>
            </Card>
          </div>

          {/* Sidebar */}
          <div className="flex flex-col gap-4 lg:col-span-2">
            {/* Capacity */}
            <Card>
              <CardHeader>
                <CardTitle>Capacity</CardTitle>
              </CardHeader>
              <CardContent>
                <CapacityRing
                  active={config.activeLeaseCount}
                  max={config.maxConcurrency}
                />
              </CardContent>
            </Card>

            {/* Configuration */}
            <Card>
              <CardHeader>
                <CardTitle>Configuration</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center gap-3">
                  <Zap className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Priority</div>
                    <div className="font-mono text-xs text-muted-foreground">
                      {config.priority}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Server className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Max Concurrency</div>
                    <div className="font-mono text-xs text-muted-foreground">
                      {config.maxConcurrency} slots
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Clock className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Lease TTL</div>
                    <div className="font-mono text-xs text-muted-foreground">
                      {config.leaseTtlSeconds}s
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Network className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Sticky Sessions</div>
                    <div className="text-xs text-muted-foreground">
                      {config.supportsStickySessions
                        ? "Supported"
                        : "Not supported"}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Shield className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Kind</div>
                    <div className="text-xs text-muted-foreground capitalize">
                      {config.kind || "Not set"}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <Activity className="size-4 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">Scope</div>
                    <div className="text-xs text-muted-foreground">
                      {config.usageScope}
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Quick actions */}
            <Card>
              <CardHeader>
                <CardTitle>Quick Actions</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  className="justify-start"
                  nativeButton={false}
                  render={
                    <Link href={`/admin/proxy_configs/${config.id}/edit`} />
                  }
                >
                  <Pencil className="size-4" />
                  Edit configuration
                </Button>
                {config.consecutiveFailures > 0 && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="justify-start"
                    onClick={handleResetHealth}
                    disabled={resetting}
                  >
                    <RefreshCw className="size-4" />
                    Reset health counters
                  </Button>
                )}
                {!config.active && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="justify-start"
                    onClick={handleToggleActive}
                    disabled={toggling}
                  >
                    <Power className="size-4" />
                    Re-enable proxy
                  </Button>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {/* Delete confirmation */}
      <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete &ldquo;{config.name}&rdquo;?</DialogTitle>
            <DialogDescription>
              This will permanently delete this proxy configuration and all its
              lease history. Active connections using this proxy will fail. This
              cannot be undone.
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
