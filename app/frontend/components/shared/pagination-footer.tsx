import { router } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import { ChevronLeft, ChevronRight } from "lucide-react"

import { Button } from "@/components/ui/button"

interface PaginationFooterProps {
  pagination: PaginationData
  /** Build the URL params for a given page number */
  buildParams?: (page: number) => Record<string, string | number | null>
  /** The URL path to navigate to (defaults to current page) */
  href?: string
}

export function PaginationFooter({
  pagination,
  buildParams,
  href,
}: PaginationFooterProps) {
  if (pagination.pages <= 1) return null

  function goToPage(page: number) {
    const params = buildParams ? buildParams(page) : { page }
    router.get(href || window.location.pathname, params, {
      preserveState: true,
      preserveScroll: true,
    })
  }

  return (
    <div className="flex items-center justify-center gap-2 px-4 py-3 text-xs text-muted-foreground">
      <Button
        variant="ghost"
        size="icon"
        className="size-6"
        disabled={!pagination.hasPrevious}
        onClick={() => goToPage(pagination.page - 1)}
      >
        <ChevronLeft className="size-3.5" />
      </Button>
      <span className="min-w-12 text-center tabular-nums">
        {pagination.from}&ndash;{pagination.to} of {pagination.total}
      </span>
      <Button
        variant="ghost"
        size="icon"
        className="size-6"
        disabled={!pagination.hasNext}
        onClick={() => goToPage(pagination.page + 1)}
      >
        <ChevronRight className="size-3.5" />
      </Button>
    </div>
  )
}
