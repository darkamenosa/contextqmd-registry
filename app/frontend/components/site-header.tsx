import { useState } from "react"
import { Link, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { Command, Menu } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

const navLinks = [
  { href: "/", label: "Home" },
  { href: "/libraries", label: "Libraries" },
  { href: "/crawl", label: "Crawl Queue" },
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
          <span className="font-semibold tracking-tight">
            ContextQMD
          </span>
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
            <Button
              nativeButton={false}
              render={<Link href="/app" />}
              size="sm"
            >
              Dashboard
            </Button>
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

              {!currentIdentity && (
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
