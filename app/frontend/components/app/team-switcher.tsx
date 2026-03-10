import { Link, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { Command } from "lucide-react"

import { withAccountScope } from "@/lib/account-scope"
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"

export function TeamSwitcher() {
  const page = usePage<SharedProps>()
  const { currentUser, currentIdentity } = page.props
  const accountId = currentUser?.accountId ?? currentIdentity?.defaultAccountId
  const scopedAppPath = withAccountScope(page.url, "/app", accountId)

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <SidebarMenuButton
          render={<Link href={scopedAppPath} />}
          size="lg"
          className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
        >
          <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
            <Command className="size-4" />
          </div>
          <div className="grid flex-1 text-left text-sm leading-tight">
            <span className="truncate font-medium">ContextQMD</span>
            <span className="truncate text-xs">Workspace</span>
          </div>
        </SidebarMenuButton>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
