import {
  Activity,
  BarChart3,
  LayoutDashboard,
  Settings2,
  Users,
  Webhook,
  Zap,
} from "lucide-react"

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from "@/components/ui/sidebar"
import { NavUser } from "@/components/admin/nav-user"
import { TeamSwitcher } from "@/components/admin/team-switcher"
import { NavMain } from "@/components/shared/nav-main"

const navOverview = [
  {
    title: "Dashboard",
    url: "/admin/dashboard",
    icon: LayoutDashboard,
  },
  {
    title: "Customers",
    url: "/admin/customers",
    icon: Users,
  },
]

const navAnalytics = [
  {
    title: "Live",
    url: "/admin/analytics/live",
    icon: Activity,
  },
  {
    title: "Reports",
    url: "/admin/analytics/reports",
    icon: BarChart3,
  },
]

const navSystem = [
  {
    title: "Jobs",
    url: "/admin/jobs",
    icon: Zap,
    external: true,
  },
  {
    title: "Webhooks",
    url: "/admin/webhooks",
    icon: Webhook,
  },
  {
    title: "Settings",
    url: "#",
    icon: Settings2,
    items: [
      { title: "General", url: "/admin/settings" },
      { title: "Team", url: "/admin/settings/team" },
      { title: "Billing", url: "/admin/settings/billing" },
    ],
  },
]

export function AppSidebar(props: React.ComponentProps<typeof Sidebar>) {
  return (
    <Sidebar collapsible="icon" {...props}>
      <SidebarHeader>
        <TeamSwitcher />
      </SidebarHeader>
      <SidebarContent>
        <NavMain items={navOverview} />
        <NavMain label="Analytics" items={navAnalytics} />
        <NavMain label="System" items={navSystem} />
      </SidebarContent>
      <SidebarFooter>
        <NavUser />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}
