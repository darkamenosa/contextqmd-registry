import { usePage } from "@inertiajs/react"

import { buildBreadcrumbs } from "@/lib/breadcrumbs"
import { SidebarBreadcrumbHeader } from "@/components/shared/sidebar-breadcrumb-header"

function getBreadcrumbs(url: string) {
  const path = url.split("?")[0].split("#")[0]
  const scopedMatch = path.match(/^\/app\/(\d+)(?:\/(.*))?$/)
  const basePath = scopedMatch ? `/app/${scopedMatch[1]}` : "/app"
  let stripped: string

  if (scopedMatch) {
    stripped = scopedMatch[2] || ""
  } else if (path === "/app") {
    return [{ label: "Dashboard" }]
  } else if (path.startsWith("/app/")) {
    stripped = path.slice("/app/".length)
  } else {
    return [{ label: "Dashboard" }]
  }

  if (!stripped || stripped === "dashboard") {
    return [{ label: "Dashboard" }]
  }

  return buildBreadcrumbs({ path: `${basePath}/${stripped}`, basePath })
}

export function AppSiteHeader() {
  const { url } = usePage()

  return <SidebarBreadcrumbHeader breadcrumbs={getBreadcrumbs(url)} />
}
