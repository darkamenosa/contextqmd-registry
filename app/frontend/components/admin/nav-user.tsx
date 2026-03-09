import { router, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { ArrowLeft, EllipsisVertical, LogOut, UserCircle } from "lucide-react"

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
  const { currentUser, currentIdentity } = usePage<SharedProps>().props
  const { isMobile } = useSidebar()

  const displayName = currentUser?.name ?? currentIdentity?.name
  const name = displayName ?? "User"
  const email =
    currentUser?.email ?? currentIdentity?.email ?? "user@example.com"
  const initials = displayName ? userInitials(displayName) : "U"
  const accountId = currentUser?.accountId ?? currentIdentity?.defaultAccountId
  const hasAccount = accountId != null
  const appPath = (path: string) => path.replace(/^\/app/, `/app/${accountId}`)

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
            {hasAccount && (
              <>
                <DropdownMenuGroup>
                  <DropdownMenuItem
                    onClick={() => router.visit(appPath("/app/settings"))}
                  >
                    <UserCircle />
                    Settings
                  </DropdownMenuItem>
                  <DropdownMenuItem
                    onClick={() => router.visit(appPath("/app"))}
                  >
                    <ArrowLeft />
                    Back to App
                  </DropdownMenuItem>
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
              </>
            )}
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
