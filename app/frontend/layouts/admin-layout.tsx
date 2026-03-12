import type { ReactNode } from "react"

import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar"
import { AppSidebar } from "@/components/admin/app-sidebar"
import { AdminSiteHeader } from "@/components/admin/site-header"

interface AdminLayoutProps {
  children: ReactNode
}

export default function AdminLayout({ children }: AdminLayoutProps) {
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <AdminSiteHeader />
        <div className="@container/main flex min-w-0 flex-1 flex-col gap-4 overflow-hidden p-4">
          {children}
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
