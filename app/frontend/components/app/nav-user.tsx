import { router, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import {
  EllipsisVertical,
  KeyRound,
  LogOut,
  Shield,
  UserCircle,
} from "lucide-react"

import { withAccountScope, withCurrentAccountScope } from "@/lib/account-scope"
import { prefetchAppShellPage } from "@/lib/app-shell-prefetch"
import { currentUserSummary } from "@/lib/current-user"
import { flushPublicShellCache } from "@/lib/public-shell-prefetch"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar"
import { NavUserSummary } from "@/components/shared/nav-user-summary"

export function NavUser() {
  const page = usePage<SharedProps>()
  const summary = currentUserSummary(page.props)
  const { isMobile } = useSidebar()
  const scopedPath = (path: string) =>
    withAccountScope(page.url, path, summary.accountId)
  const settingsPath = scopedPath("/app/settings")
  const accessTokensPath = withCurrentAccountScope(
    page.url,
    "/app/access_tokens"
  )

  function handleMenuOpenChange(open: boolean) {
    if (!open) return

    prefetchAppShellPage(settingsPath)
    prefetchAppShellPage(accessTokensPath)
  }

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu onOpenChange={handleMenuOpenChange}>
          <DropdownMenuTrigger
            render={
              <SidebarMenuButton
                size="lg"
                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
              />
            }
          >
            <NavUserSummary
              email={summary.email}
              initials={summary.initials}
              name={summary.name}
            />
            <EllipsisVertical className="ml-auto size-4" />
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="min-w-56 rounded-lg"
            side={isMobile ? "bottom" : "right"}
            align="end"
            sideOffset={4}
          >
            <DropdownMenuGroup>
              <DropdownMenuLabel className="p-0 font-normal">
                <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
                  <NavUserSummary
                    compact
                    email={summary.email}
                    initials={summary.initials}
                    name={summary.name}
                  />
                </div>
              </DropdownMenuLabel>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuItem onClick={() => router.visit(settingsPath)}>
                <UserCircle />
                Settings
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => router.visit(accessTokensPath)}>
                <KeyRound />
                Access Tokens
              </DropdownMenuItem>
            </DropdownMenuGroup>
            {summary.staff && (
              <>
                <DropdownMenuSeparator />
                <DropdownMenuGroup>
                  <DropdownMenuItem
                    onClick={() => router.visit("/admin/dashboard")}
                  >
                    <Shield />
                    Admin
                  </DropdownMenuItem>
                </DropdownMenuGroup>
              </>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem
              onClick={() =>
                router.delete("/logout", {
                  onSuccess: () => flushPublicShellCache(),
                })
              }
            >
              <LogOut />
              Log out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
