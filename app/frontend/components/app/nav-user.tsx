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
import { userInitials } from "@/lib/user-initials"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
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

export function NavUser() {
  const page = usePage<SharedProps>()
  const { currentUser, currentIdentity } = page.props
  const { isMobile } = useSidebar()
  const accountId = currentUser?.accountId ?? currentIdentity?.defaultAccountId
  const scopedPath = (path: string) =>
    withAccountScope(page.url, path, accountId)

  const displayName = currentUser?.name ?? currentIdentity?.name
  const name = displayName ?? "User"
  const email =
    currentUser?.email ?? currentIdentity?.email ?? "user@example.com"
  const initials = displayName ? userInitials(displayName) : "U"

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <SidebarMenuButton
                size="lg"
                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
              />
            }
          >
            <Avatar className="size-10 rounded-lg transition-[width,height] group-data-[collapsible=icon]:size-8">
              <AvatarFallback className="rounded-lg bg-primary text-primary-foreground">
                {initials}
              </AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left text-sm leading-tight">
              <span className="truncate font-medium">{name}</span>
              <span className="truncate text-xs">{email}</span>
            </div>
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
                  <Avatar className="size-10 rounded-lg">
                    <AvatarFallback className="rounded-lg bg-primary text-primary-foreground">
                      {initials}
                    </AvatarFallback>
                  </Avatar>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-medium">{name}</span>
                    <span className="truncate text-xs">{email}</span>
                  </div>
                </div>
              </DropdownMenuLabel>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuItem
                onClick={() => router.visit(scopedPath("/app/settings"))}
              >
                <UserCircle />
                Settings
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  router.visit(
                    withCurrentAccountScope(page.url, "/app/access_tokens")
                  )
                }
              >
                <KeyRound />
                Access Tokens
              </DropdownMenuItem>
            </DropdownMenuGroup>
            {(currentUser?.staff ?? currentIdentity?.staff) && (
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
            <DropdownMenuItem onClick={() => router.delete("/logout")}>
              <LogOut />
              Log out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
