import { usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { LayoutDashboard, Plus } from "lucide-react"

import { withAccountScope } from "@/lib/account-scope"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from "@/components/ui/sidebar"
import { NavUser } from "@/components/app/nav-user"
import { TeamSwitcher } from "@/components/app/team-switcher"
import { NavMain } from "@/components/shared/nav-main"

export function AppSidebar(props: React.ComponentProps<typeof Sidebar>) {
  const page = usePage<SharedProps>()
  const accountId =
    page.props.currentUser?.accountId ??
    page.props.currentIdentity?.defaultAccountId
  const scopedPath = (path: string) =>
    withAccountScope(page.url, path, accountId)
  const navMain = [
    {
      title: "Dashboard",
      url: scopedPath("/app/dashboard"),
      icon: LayoutDashboard,
    },
    {
      title: "Submit Docs",
      url: scopedPath("/app/crawl/new"),
      icon: Plus,
    },
  ]

  return (
    <Sidebar collapsible="icon" {...props}>
      <SidebarHeader>
        <TeamSwitcher />
      </SidebarHeader>
      <SidebarContent>
        <NavMain items={navMain} />
      </SidebarContent>
      <SidebarFooter>
        <NavUser />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}
