import { useState } from "react"
import { Link, router, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import {
  ChevronDown,
  Command,
  LayoutDashboard,
  LogOut,
  Menu,
  Settings,
  Shield,
} from "lucide-react"

import { userInitials } from "@/lib/user-initials"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
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
  Sheet,
  SheetContent,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

const navLinks = [
  { href: "/libraries", label: "Libraries" },
  { href: "/rankings", label: "Rankings" },
  { href: "/crawl", label: "Queue" },
  { href: "/about", label: "About" },
]

export function SiteHeader() {
  const { currentIdentity } = usePage<SharedProps>().props
  const currentUrl = usePage().url
  const [open, setOpen] = useState(false)

  const isActive = (href: string) => {
    if (href === "/") return currentUrl === "/"
    return currentUrl === href || currentUrl.startsWith(`${href}/`)
  }

  return (
    <header className="sticky top-0 z-50 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="mx-auto flex h-16 max-w-7xl items-center px-4 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link href="/" className="flex shrink-0 items-center gap-2.5">
          <div className="flex size-8 items-center justify-center rounded-lg bg-foreground text-background">
            <Command className="size-4" />
          </div>
          <span className="font-semibold tracking-tight">ContextQMD</span>
        </Link>

        {/* Center nav */}
        <nav className="hidden flex-1 items-center justify-center gap-1 md:flex">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`rounded-md px-3 py-1.5 text-sm transition-colors ${
                isActive(link.href)
                  ? "font-medium text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Right: Auth + Mobile toggle */}
        <div className="ml-auto flex items-center gap-3">
          {currentIdentity ? (
            <DropdownMenu>
              <DropdownMenuTrigger className="hidden cursor-pointer items-center gap-2 rounded-full py-1 pr-3 pl-1 ring-offset-background outline-hidden transition-colors hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 sm:flex">
                <Avatar className="size-7">
                  <AvatarFallback className="bg-foreground text-xs font-medium text-background">
                    {userInitials(
                      currentIdentity.name ?? currentIdentity.email
                    )}
                  </AvatarFallback>
                </Avatar>
                <span className="text-sm font-medium">
                  {currentIdentity.name ?? currentIdentity.email.split("@")[0]}
                </span>
                <ChevronDown className="size-3.5 text-muted-foreground" />
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="end"
                className="min-w-56 rounded-lg"
                sideOffset={4}
              >
                <DropdownMenuGroup>
                  <DropdownMenuLabel className="p-0 font-normal">
                    <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
                      <Avatar className="size-10 rounded-lg after:rounded-lg">
                        <AvatarFallback className="rounded-lg bg-primary text-primary-foreground">
                          {userInitials(
                            currentIdentity.name ?? currentIdentity.email
                          )}
                        </AvatarFallback>
                      </Avatar>
                      <div className="grid flex-1 text-left text-sm leading-tight">
                        <span className="truncate font-medium">
                          {currentIdentity.name ?? "User"}
                        </span>
                        <span className="truncate text-xs">
                          {currentIdentity.email}
                        </span>
                      </div>
                    </div>
                  </DropdownMenuLabel>
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
                <DropdownMenuGroup>
                  <DropdownMenuItem onClick={() => router.visit("/app")}>
                    <LayoutDashboard />
                    Dashboard
                  </DropdownMenuItem>
                  <DropdownMenuItem
                    onClick={() => router.visit("/app/settings")}
                  >
                    <Settings />
                    Settings
                  </DropdownMenuItem>
                </DropdownMenuGroup>
                {currentIdentity.staff && (
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
          ) : (
            <>
              <Link
                href="/login"
                className="hidden text-sm text-muted-foreground transition-colors hover:text-foreground sm:block"
              >
                Log in
              </Link>
              <Button
                nativeButton={false}
                render={<Link href="/register" />}
                size="sm"
                className="hidden sm:inline-flex"
              >
                Get started
              </Button>
            </>
          )}

          <Sheet open={open} onOpenChange={setOpen}>
            <SheetTrigger
              render={
                <Button variant="ghost" size="icon" className="md:hidden" />
              }
            >
              <Menu className="size-5" />
              <span className="sr-only">Open menu</span>
            </SheetTrigger>
            <SheetContent
              side="left"
              className="flex w-full max-w-xs flex-col p-0"
              showCloseButton={false}
              aria-describedby={undefined}
            >
              <SheetTitle className="sr-only">Navigation menu</SheetTitle>
              <div className="flex items-center justify-between border-b px-4 py-3">
                <Link
                  href="/"
                  className="flex items-center gap-2.5"
                  onClick={() => setOpen(false)}
                >
                  <div className="flex size-7 items-center justify-center rounded-lg bg-foreground text-background">
                    <Command className="size-3.5" />
                  </div>
                  <span className="text-sm font-semibold tracking-tight">
                    ContextQMD
                  </span>
                </Link>
              </div>

              <nav className="flex flex-col p-2">
                {navLinks.map((link) => (
                  <Link
                    key={link.href}
                    href={link.href}
                    className={`rounded-lg px-4 py-3 text-[15px] transition-colors ${
                      isActive(link.href)
                        ? "bg-muted font-medium text-foreground"
                        : "text-muted-foreground hover:bg-muted hover:text-foreground"
                    }`}
                    onClick={() => setOpen(false)}
                  >
                    {link.label}
                  </Link>
                ))}
              </nav>

              {currentIdentity ? (
                <div className="mt-auto border-t">
                  <div className="flex items-center gap-3 border-b px-4 py-3">
                    <Avatar className="size-8">
                      <AvatarFallback className="bg-foreground text-xs font-medium text-background">
                        {userInitials(
                          currentIdentity.name ?? currentIdentity.email
                        )}
                      </AvatarFallback>
                    </Avatar>
                    <div className="min-w-0 flex-1">
                      {currentIdentity.name && (
                        <p className="truncate text-sm font-medium">
                          {currentIdentity.name}
                        </p>
                      )}
                      <p className="truncate text-xs text-muted-foreground">
                        {currentIdentity.email}
                      </p>
                    </div>
                  </div>
                  <nav className="flex flex-col p-2">
                    <Link
                      href="/app"
                      className="flex items-center gap-3 rounded-lg px-4 py-3 text-[15px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                      onClick={() => setOpen(false)}
                    >
                      <LayoutDashboard className="size-4" />
                      Dashboard
                    </Link>
                    <Link
                      href="/app/settings"
                      className="flex items-center gap-3 rounded-lg px-4 py-3 text-[15px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                      onClick={() => setOpen(false)}
                    >
                      <Settings className="size-4" />
                      Settings
                    </Link>
                    {currentIdentity.staff && (
                      <Link
                        href="/admin/dashboard"
                        className="flex items-center gap-3 rounded-lg px-4 py-3 text-[15px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                        onClick={() => setOpen(false)}
                      >
                        <Shield className="size-4" />
                        Admin
                      </Link>
                    )}
                  </nav>
                  <div className="border-t p-2">
                    <button
                      type="button"
                      onClick={() => {
                        setOpen(false)
                        router.delete("/logout")
                      }}
                      className="flex w-full items-center gap-3 rounded-lg px-4 py-3 text-[15px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                    >
                      <LogOut className="size-4" />
                      Log out
                    </button>
                  </div>
                </div>
              ) : (
                <div className="mt-auto flex flex-col gap-2 border-t p-4">
                  <Button
                    nativeButton={false}
                    render={
                      <Link href="/register" onClick={() => setOpen(false)} />
                    }
                    size="lg"
                    className="w-full"
                  >
                    Get started
                  </Button>
                  <Button
                    variant="outline"
                    nativeButton={false}
                    render={
                      <Link href="/login" onClick={() => setOpen(false)} />
                    }
                    size="lg"
                    className="w-full"
                  >
                    Log in
                  </Button>
                </div>
              )}
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  )
}
