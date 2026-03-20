import type { SharedProps } from "@/types"

import { userInitials } from "@/lib/user-initials"

export function currentUserSummary(props: SharedProps) {
  const { currentUser, currentIdentity } = props
  const displayName = currentUser?.name ?? currentIdentity?.name

  return {
    accountId: currentUser?.accountId ?? currentIdentity?.defaultAccountId,
    email: currentUser?.email ?? currentIdentity?.email ?? "user@example.com",
    hasAccount:
      (currentUser?.accountId ?? currentIdentity?.defaultAccountId) != null,
    initials: displayName ? userInitials(displayName) : "U",
    name: displayName ?? "User",
    staff: currentUser?.staff ?? currentIdentity?.staff ?? false,
  }
}
