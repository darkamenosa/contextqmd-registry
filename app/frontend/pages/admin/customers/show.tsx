import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import type { AdminCustomerDetail, AdminCustomerMembership } from "@/types"
import { ChevronLeft } from "lucide-react"

import { formatDateShort } from "@/lib/format-date"
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
import { StatusBadge } from "@/components/admin/ui/status-badge"
import AdminLayout from "@/layouts/admin-layout"

interface Props {
  customer: AdminCustomerDetail
  isSelf: boolean
}

type IdentityAction = "suspend" | "unsuspend" | "grant_staff" | "revoke_staff"

// ─── Overview ───────────────────────────────────────────────────────────────

function OverviewCard({ customer }: { customer: AdminCustomerDetail }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Customer details</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-4 text-sm">
          <div className="col-span-2">
            <dt className="text-muted-foreground">Email</dt>
            <dd className="mt-0.5 font-medium">{customer.email}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Name</dt>
            <dd className="mt-0.5 font-medium">{customer.name || "—"}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Auth method</dt>
            <dd className="mt-0.5 font-medium">{customer.authMethod}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Joined</dt>
            <dd className="mt-0.5 font-medium">
              {formatDateShort(customer.createdAt)}
            </dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Accounts</dt>
            <dd className="mt-0.5 font-medium">
              {customer.memberships.length}
            </dd>
          </div>
        </dl>
      </CardContent>
    </Card>
  )
}

// ─── Membership Row ─────────────────────────────────────────────────────────

function MembershipRow({
  membership: m,
  onReactivate,
}: {
  membership: AdminCustomerMembership
  onReactivate: () => void
}) {
  return (
    <tr className="border-t transition-colors hover:bg-muted/50">
      <td className="px-4 py-3 text-sm font-medium">{m.accountName}</td>
      <td className="px-4 py-3 text-sm">{m.name}</td>
      <td className="px-4 py-3 text-sm">
        <Badge variant="outline" className="text-muted-foreground capitalize">
          {m.role}
        </Badge>
      </td>
      <td className="px-4 py-3 text-sm">
        {m.accountCancelled ? (
          <div className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <StatusBadge status="cancelled" />
              {m.daysUntilDeletion !== null && (
                <span className="text-xs text-muted-foreground">
                  {m.daysUntilDeletion}d left
                </span>
              )}
            </div>
            {m.canReactivate && (
              <Button
                size="sm"
                variant="outline"
                className="h-7 w-fit"
                onClick={onReactivate}
              >
                Reactivate account
              </Button>
            )}
          </div>
        ) : (
          <StatusBadge status={m.active ? "active" : "inactive"} />
        )}
      </td>
      <td className="px-4 py-3 text-sm">{formatDateShort(m.createdAt)}</td>
    </tr>
  )
}

// ─── Memberships ────────────────────────────────────────────────────────────

function MembershipsCard({
  customer,
  onReactivateAccount,
}: {
  customer: AdminCustomerDetail
  onReactivateAccount: (membershipId: number, accountName: string) => void
}) {
  const count = customer.memberships.length

  return (
    <Card>
      <CardHeader>
        <CardTitle>Account memberships</CardTitle>
        <CardDescription>
          {count === 0
            ? "No account memberships"
            : `${count} account${count !== 1 ? "s" : ""}`}
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-t">
                <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                  Account
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                  Name
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                  Role
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                  Status
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                  Joined
                </th>
              </tr>
            </thead>
            <tbody>
              {count > 0 ? (
                customer.memberships.map((m) => (
                  <MembershipRow
                    key={m.id}
                    membership={m}
                    onReactivate={() =>
                      onReactivateAccount(m.id, m.accountName)
                    }
                  />
                ))
              ) : (
                <tr>
                  <td
                    colSpan={5}
                    className="h-24 text-center text-sm text-muted-foreground"
                  >
                    This identity has no account memberships yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

// ─── Identity Card (sidebar) ────────────────────────────────────────────────

function IdentityCard({
  customer,
  isSelf,
  onSuspend,
  onUnsuspend,
  onGrantStaff,
  onRevokeStaff,
}: {
  customer: AdminCustomerDetail
  isSelf: boolean
  onSuspend: () => void
  onUnsuspend: () => void
  onGrantStaff: () => void
  onRevokeStaff: () => void
}) {
  const isSuspended = customer.status === "suspended"

  return (
    <Card>
      <CardHeader>
        <CardTitle>Identity</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col">
        {/* Login status */}
        <div className="flex flex-col gap-2 pb-4">
          <span className="text-sm font-medium">Login status</span>
          <div className="flex items-center gap-2">
            <StatusBadge status={customer.status} />
            {isSuspended && customer.suspendedAt && (
              <span className="text-xs text-muted-foreground">
                since {formatDateShort(customer.suspendedAt)}
              </span>
            )}
          </div>
          <p className="text-sm text-muted-foreground">
            {isSuspended
              ? "Suspended. Cannot sign in."
              : "Can sign in normally."}
          </p>
          {!isSelf &&
            (isSuspended ? (
              <Button
                size="sm"
                variant="outline"
                className="w-fit"
                onClick={onUnsuspend}
              >
                Unsuspend
              </Button>
            ) : (
              <Button
                size="sm"
                variant="outline"
                className="w-fit"
                onClick={onSuspend}
              >
                Suspend
              </Button>
            ))}
        </div>

        <div className="border-t" />

        {/* Staff access */}
        <div className="flex flex-col gap-2 py-4">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium">Staff access</span>
            <Badge
              variant={customer.staff ? "secondary" : "outline"}
              className="text-muted-foreground"
            >
              {customer.staff ? "Staff" : "No access"}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            {customer.staff
              ? "Has access to the admin panel."
              : "Cannot access the admin panel."}
          </p>
          {!isSelf &&
            (customer.staff ? (
              <Button
                size="sm"
                variant="outline"
                className="w-fit"
                onClick={onRevokeStaff}
              >
                Revoke access
              </Button>
            ) : (
              <Button
                size="sm"
                variant="outline"
                className="w-fit"
                onClick={onGrantStaff}
              >
                Grant access
              </Button>
            ))}
        </div>
      </CardContent>
    </Card>
  )
}

// ─── Page ───────────────────────────────────────────────────────────────────

export default function AdminCustomerShow({ customer, isSelf }: Props) {
  const [actionOpen, setActionOpen] = useState(false)
  const [pendingAction, setPendingAction] = useState<IdentityAction | null>(
    null
  )
  const [actionProcessing, setActionProcessing] = useState(false)
  const [reactivateAccount, setReactivateAccount] = useState<{
    membershipId: number
    accountName: string
  } | null>(null)

  const actionMeta = (() => {
    if (pendingAction === "suspend") {
      return {
        title: "Suspend this customer?",
        description:
          "This customer will no longer be able to sign in until unsuspended.",
        confirmLabel: "Yes, suspend",
        confirmVariant: "destructive" as const,
      }
    }

    if (pendingAction === "unsuspend") {
      return {
        title: "Unsuspend this customer?",
        description: "This customer will regain sign-in access immediately.",
        confirmLabel: "Yes, unsuspend",
        confirmVariant: "default" as const,
      }
    }

    if (pendingAction === "grant_staff") {
      return {
        title: "Grant staff access?",
        description:
          "This customer will gain access to the admin panel immediately.",
        confirmLabel: "Yes, grant access",
        confirmVariant: "default" as const,
      }
    }

    if (pendingAction === "revoke_staff") {
      return {
        title: "Revoke staff access?",
        description: "This customer will lose access to the admin panel.",
        confirmLabel: "Yes, revoke access",
        confirmVariant: "destructive" as const,
      }
    }

    return null
  })()

  function openActionDialog(action: IdentityAction) {
    setPendingAction(action)
    setActionOpen(true)
  }

  function handleActionOpenChange(open: boolean) {
    setActionOpen(open)

    if (!open && !actionProcessing) {
      setPendingAction(null)
    }
  }

  function handleActionConfirm() {
    if (!pendingAction) return

    const requestOptions = {
      onSuccess: () => {
        setActionOpen(false)
        setPendingAction(null)
      },
      onFinish: () => setActionProcessing(false),
    }

    setActionProcessing(true)

    if (pendingAction === "suspend") {
      router.post(
        `/admin/customers/${customer.id}/suspension`,
        {},
        requestOptions
      )
    } else if (pendingAction === "unsuspend") {
      router.delete(
        `/admin/customers/${customer.id}/suspension`,
        requestOptions
      )
    } else if (pendingAction === "grant_staff") {
      router.post(
        `/admin/customers/${customer.id}/staff_access`,
        {},
        requestOptions
      )
    } else {
      router.delete(
        `/admin/customers/${customer.id}/staff_access`,
        requestOptions
      )
    }
  }

  function handleReactivateAccount() {
    if (!reactivateAccount) return

    router.post(
      `/admin/customers/${customer.id}/account_reactivation`,
      { membership_id: reactivateAccount.membershipId },
      {
        onSuccess: () => setReactivateAccount(null),
      }
    )
  }

  return (
    <AdminLayout>
      <Head title={customer.name || customer.email} />

      <div className="flex flex-col gap-4">
        {/* Page header */}
        <div className="flex items-center gap-2.5">
          <Link
            href="/admin/customers"
            aria-label="Back to customers"
            className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <h1 className="min-w-0 truncate text-lg font-semibold">
            {customer.name || customer.email}
          </h1>
          <StatusBadge status={customer.status} />
        </div>

        {/* Main + sidebar grid */}
        <div className="grid items-start gap-4 lg:grid-cols-5">
          <div className="flex flex-col gap-4 lg:col-span-3">
            <OverviewCard customer={customer} />
            <MembershipsCard
              customer={customer}
              onReactivateAccount={(membershipId, accountName) =>
                setReactivateAccount({ membershipId, accountName })
              }
            />
          </div>
          <div className="lg:col-span-2">
            <IdentityCard
              customer={customer}
              isSelf={isSelf}
              onSuspend={() => openActionDialog("suspend")}
              onUnsuspend={() => openActionDialog("unsuspend")}
              onGrantStaff={() => openActionDialog("grant_staff")}
              onRevokeStaff={() => openActionDialog("revoke_staff")}
            />
          </div>
        </div>
      </div>

      {/* Identity action confirmation */}
      <Dialog open={actionOpen} onOpenChange={handleActionOpenChange}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{actionMeta?.title}</DialogTitle>
            <DialogDescription>{actionMeta?.description}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => handleActionOpenChange(false)}
              disabled={actionProcessing}
            >
              Cancel
            </Button>
            <Button
              variant={actionMeta?.confirmVariant}
              onClick={handleActionConfirm}
              disabled={actionProcessing}
            >
              {actionMeta?.confirmLabel}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Account reactivation confirmation */}
      <Dialog
        open={reactivateAccount !== null}
        onOpenChange={(open) => !open && setReactivateAccount(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Reactivate &ldquo;{reactivateAccount?.accountName}&rdquo;?
            </DialogTitle>
            <DialogDescription>
              This will cancel the scheduled deletion. The account and all its
              data will be preserved.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setReactivateAccount(null)}
            >
              Cancel
            </Button>
            <Button onClick={handleReactivateAccount}>
              Reactivate account
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  )
}
