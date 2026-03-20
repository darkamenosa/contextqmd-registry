import { usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"

import { withAccountScope } from "@/lib/account-scope"
import { SidebarBrand } from "@/components/shared/sidebar-brand"

export function TeamSwitcher() {
  const page = usePage<SharedProps>()
  const { currentUser, currentIdentity } = page.props
  const accountId = currentUser?.accountId ?? currentIdentity?.defaultAccountId
  const scopedAppPath = withAccountScope(page.url, "/app", accountId)

  return <SidebarBrand href={scopedAppPath} subtitle="Workspace" />
}
