import {
  Activity,
  BarChart3,
  BookOpen,
  LayoutDashboard,
  Network,
  Radar,
  Settings2,
  Users,
  Webhook,
  Zap,
} from "lucide-react"

import { adminShellPrefetchProps } from "@/lib/admin-shell-prefetch"
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
    title: "Libraries",
    url: "/admin/libraries",
    icon: BookOpen,
  },
  {
    title: "Crawl Requests",
    url: "/admin/crawl_requests",
    icon: Radar,
  },
  {
    title: "Users",
    url: "/admin/users",
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
    url: "/admin/analytics",
    icon: BarChart3,
  },
]

const navSystem = [
  {
    title: "Proxy Pool",
    url: "/admin/proxy_configs",
    icon: Network,
  },
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
      { title: "Analytics", url: "/admin/settings/analytics" },
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
        <NavMain
          items={navOverview}
          linkPropsForUrl={adminShellPrefetchProps}
        />
        <NavMain
          label="Analytics"
          items={navAnalytics}
          linkPropsForUrl={adminShellPrefetchProps}
        />
        <NavMain
          label="System"
          items={navSystem}
          linkPropsForUrl={adminShellPrefetchProps}
        />
      </SidebarContent>
      <SidebarFooter>
        <NavUser />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}
