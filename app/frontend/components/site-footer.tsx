import { Link } from "@inertiajs/react"
import { Command } from "lucide-react"

export function SiteFooter() {
  return (
    <footer className="border-t bg-background">
      <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
        <div className="grid grid-cols-2 gap-8 sm:grid-cols-3">
          <div>
            <h3 className="text-sm font-semibold">Registry</h3>
            <ul className="mt-4 flex flex-col gap-2 text-sm text-muted-foreground">
              <li>
                <Link
                  href="/libraries"
                  className="transition-colors hover:text-foreground"
                >
                  Libraries
                </Link>
              </li>
              <li>
                <Link
                  href="/rankings"
                  className="transition-colors hover:text-foreground"
                >
                  Rankings
                </Link>
              </li>
              <li>
                <Link
                  href="/crawl"
                  className="transition-colors hover:text-foreground"
                >
                  Queue
                </Link>
              </li>
            </ul>
          </div>
          <div>
            <h3 className="text-sm font-semibold">Project</h3>
            <ul className="mt-4 flex flex-col gap-2 text-sm text-muted-foreground">
              <li>
                <Link
                  href="/about"
                  className="transition-colors hover:text-foreground"
                >
                  About
                </Link>
              </li>
              <li>
                <a
                  href="https://github.com/contextqmd/contextqmd"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="transition-colors hover:text-foreground"
                >
                  GitHub
                </a>
              </li>
              <li>
                <Link
                  href="/contact"
                  className="transition-colors hover:text-foreground"
                >
                  Contact
                </Link>
              </li>
            </ul>
          </div>
          <div>
            <h3 className="text-sm font-semibold">Legal</h3>
            <ul className="mt-4 flex flex-col gap-2 text-sm text-muted-foreground">
              <li>
                <Link
                  href="/privacy"
                  className="transition-colors hover:text-foreground"
                >
                  Privacy Policy
                </Link>
              </li>
              <li>
                <Link
                  href="/terms"
                  className="transition-colors hover:text-foreground"
                >
                  Terms of Service
                </Link>
              </li>
            </ul>
          </div>
        </div>
        <div className="mt-8 flex items-center justify-between border-t pt-8 text-sm text-muted-foreground">
          <Link href="/" className="flex items-center gap-2">
            <div className="flex size-6 items-center justify-center rounded-lg bg-foreground text-background">
              <Command className="size-3" />
            </div>
            <span className="font-semibold tracking-tight">ContextQMD</span>
          </Link>
          <span>
            &copy; {new Date().getFullYear()} ContextQMD. All rights reserved.
          </span>
        </div>
      </div>
    </footer>
  )
}
