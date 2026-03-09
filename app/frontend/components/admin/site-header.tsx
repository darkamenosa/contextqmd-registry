import { usePage } from "@inertiajs/react"

import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb"
import { Separator } from "@/components/ui/separator"
import { SidebarTrigger } from "@/components/ui/sidebar"

function getBreadcrumbs(url: string): { label: string; href?: string }[] {
  const path = url.split("?")[0].split("#")[0]
  const stripped = path.replace(/^\/admin\/?/, "")
  if (!stripped || stripped === "dashboard") {
    return [{ label: "Dashboard" }]
  }
  const segments = stripped.split("/").filter(Boolean)
  return segments.map((segment, i) => ({
    label: segment
      .replace(/[-_]/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase()),
    href:
      i < segments.length - 1
        ? `/admin/${segments.slice(0, i + 1).join("/")}`
        : undefined,
  }))
}

export function AdminSiteHeader() {
  const { url } = usePage()
  const breadcrumbs = getBreadcrumbs(url)

  return (
    <header className="flex h-16 shrink-0 items-center gap-2 border-b transition-[width,height] ease-linear group-has-data-[collapsible=icon]/sidebar-wrapper:h-12">
      <div className="flex items-center gap-2 px-4">
        <SidebarTrigger className="-ml-1" />
        <Separator
          orientation="vertical"
          className="mr-2 data-[orientation=vertical]:h-4"
        />
        <Breadcrumb>
          <BreadcrumbList>
            {breadcrumbs.map((crumb, i) => (
              <BreadcrumbItem key={crumb.label}>
                {i > 0 && <BreadcrumbSeparator className="hidden md:block" />}
                {crumb.href ? (
                  <BreadcrumbLink href={crumb.href} className="hidden md:block">
                    {crumb.label}
                  </BreadcrumbLink>
                ) : (
                  <BreadcrumbPage>{crumb.label}</BreadcrumbPage>
                )}
              </BreadcrumbItem>
            ))}
          </BreadcrumbList>
        </Breadcrumb>
      </div>
    </header>
  )
}
