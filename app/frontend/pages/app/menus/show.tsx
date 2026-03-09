import { useState } from "react"
import { Head, Link, router } from "@inertiajs/react"
import { AlertTriangle, Building2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

interface Account {
  id: number
  name: string
  role: string
}

interface CancelledAccount {
  membershipId: number
  accountId: number
  name: string
  role: string
  daysUntilDeletion: number
}

interface Props {
  accounts: Account[]
  cancelledAccounts: CancelledAccount[]
}

export default function MenusShow({ accounts, cancelledAccounts }: Props) {
  const [reactivating, setReactivating] = useState<CancelledAccount | null>(
    null
  )

  function handleReactivate() {
    if (!reactivating) return

    router.post(
      "/app/account_reactivation",
      { membership_id: reactivating.membershipId },
      { onSuccess: () => setReactivating(null) }
    )
  }

  return (
    <>
      <Head title="Select Account" />
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="w-full max-w-md space-y-6 px-4">
          <div className="text-center">
            <h1 className="text-2xl font-semibold tracking-tight">
              {accounts.length > 0 ? "Select an account" : "No active accounts"}
            </h1>
            <p className="mt-2 text-sm text-muted-foreground">
              {accounts.length > 0
                ? "Choose which account to open"
                : "You can reactivate a cancelled account below"}
            </p>
          </div>

          {accounts.length > 0 && (
            <div className="space-y-2">
              {accounts.map((account) => (
                <Link
                  key={account.id}
                  href={`/app/${account.id}/dashboard`}
                  className="flex items-center gap-3 rounded-lg border p-4 transition-colors hover:bg-accent"
                >
                  <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10">
                    <Building2 className="size-5 text-primary" />
                  </div>
                  <div className="flex-1">
                    <div className="font-medium">{account.name}</div>
                    <div className="text-sm text-muted-foreground capitalize">
                      {account.role}
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          )}

          {cancelledAccounts.length > 0 && (
            <>
              <div className="flex items-center gap-3">
                <div className="h-px flex-1 bg-border" />
                <span className="text-xs font-medium text-muted-foreground">
                  Cancelled
                </span>
                <div className="h-px flex-1 bg-border" />
              </div>

              <div className="space-y-2">
                {cancelledAccounts.map((account) => (
                  <div
                    key={account.accountId}
                    className="flex items-center gap-3 rounded-lg border border-amber-200 bg-amber-50/50 p-4 dark:border-amber-800/50 dark:bg-amber-950/20"
                  >
                    <div className="flex size-10 items-center justify-center rounded-lg bg-amber-100 dark:bg-amber-900/50">
                      <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                    </div>
                    <div className="flex-1">
                      <div className="font-medium">{account.name}</div>
                      <div className="text-sm text-amber-600 dark:text-amber-400">
                        {account.daysUntilDeletion > 0
                          ? `${account.daysUntilDeletion} days until deletion`
                          : "Deletion pending"}
                      </div>
                    </div>
                    {account.role === "owner" && (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => setReactivating(account)}
                      >
                        Reactivate
                      </Button>
                    )}
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      <Dialog
        open={reactivating !== null}
        onOpenChange={(open) => !open && setReactivating(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Reactivate &ldquo;{reactivating?.name}&rdquo;?
            </DialogTitle>
            <DialogDescription>
              This will cancel the scheduled deletion and restore full access to
              your account immediately.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setReactivating(null)}>
              Cancel
            </Button>
            <Button onClick={handleReactivate}>Reactivate account</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
