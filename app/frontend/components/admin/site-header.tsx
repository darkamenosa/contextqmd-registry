import { usePage } from "@inertiajs/react"

import { buildBreadcrumbs } from "@/lib/breadcrumbs"
import { SidebarBreadcrumbHeader } from "@/components/shared/sidebar-breadcrumb-header"

function getBreadcrumbs(url: string) {
  const path = url.split("?")[0].split("#")[0]
  return buildBreadcrumbs({ path: path, basePath: "/admin" })
}

export function AdminSiteHeader() {
  const { url } = usePage()

  return <SidebarBreadcrumbHeader breadcrumbs={getBreadcrumbs(url)} />
}
