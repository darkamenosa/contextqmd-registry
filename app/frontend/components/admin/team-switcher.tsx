import { adminShellPrefetchProps } from "@/lib/admin-shell-prefetch"
import { SidebarBrand } from "@/components/shared/sidebar-brand"

export function TeamSwitcher() {
  const dashboardPath = "/admin/dashboard"

  return (
    <SidebarBrand
      href={dashboardPath}
      subtitle="Platform"
      linkProps={adminShellPrefetchProps(dashboardPath)}
    />
  )
}
