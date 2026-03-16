import { router } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import {
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
} from "lucide-react"

import { Button } from "@/components/ui/button"

interface PaginationFooterProps {
  pagination: PaginationData
  /** Build the URL params for a given page number */
  buildParams?: (page: number) => Record<string, string | number | null>
  /** The URL path to navigate to (defaults to current page) */
  href?: string
}

/**
 * Build the list of page slots to render.
 * Always shows first, last, current, and 1 neighbor on each side.
 * Gaps are represented as null.
 */
function buildPageSlots(current: number, total: number): (number | null)[] {
  if (total <= 7) {
    return Array.from({ length: total }, (_, i) => i + 1)
  }

  const slots = new Set<number>()
  slots.add(1)
  slots.add(total)
  for (
    let i = Math.max(2, current - 1);
    i <= Math.min(total - 1, current + 1);
    i++
  ) {
    slots.add(i)
  }

  const sorted = Array.from(slots).sort((a, b) => a - b)
  const result: (number | null)[] = []

  for (let i = 0; i < sorted.length; i++) {
    if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
      result.push(null)
    }
    result.push(sorted[i])
  }

  return result
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

  const slots = buildPageSlots(pagination.page, pagination.pages)

  return (
    <nav
      aria-label="Pagination"
      className="mt-8 flex flex-col items-center gap-3"
    >
      {/* Page buttons */}
      <div className="flex items-center gap-1">
        {/* First page */}
        <Button
          variant="ghost"
          size="icon"
          className="hidden size-8 sm:inline-flex"
          disabled={pagination.page === 1}
          onClick={() => goToPage(1)}
          aria-label="First page"
        >
          <ChevronsLeft className="size-4" />
        </Button>

        {/* Previous */}
        <Button
          variant="ghost"
          size="icon"
          className="size-8"
          disabled={!pagination.hasPrevious}
          onClick={() => goToPage(pagination.page - 1)}
          aria-label="Previous page"
        >
          <ChevronLeft className="size-4" />
        </Button>

        {/* Numbered page buttons */}
        {slots.map((slot, idx) =>
          slot === null ? (
            <span
              key={`ellipsis-${idx}`}
              className="flex size-8 items-center justify-center text-sm text-muted-foreground select-none"
              aria-hidden
            >
              &hellip;
            </span>
          ) : (
            <Button
              key={slot}
              variant={slot === pagination.page ? "default" : "ghost"}
              size="icon"
              className="size-8 text-sm tabular-nums"
              onClick={() => goToPage(slot)}
              aria-label={`Page ${slot}`}
              aria-current={slot === pagination.page ? "page" : undefined}
            >
              {slot}
            </Button>
          )
        )}

        {/* Next */}
        <Button
          variant="ghost"
          size="icon"
          className="size-8"
          disabled={!pagination.hasNext}
          onClick={() => goToPage(pagination.page + 1)}
          aria-label="Next page"
        >
          <ChevronRight className="size-4" />
        </Button>

        {/* Last page */}
        <Button
          variant="ghost"
          size="icon"
          className="hidden size-8 sm:inline-flex"
          disabled={pagination.page === pagination.pages}
          onClick={() => goToPage(pagination.pages)}
          aria-label="Last page"
        >
          <ChevronsRight className="size-4" />
        </Button>
      </div>

      {/* Range summary */}
      <p className="text-xs text-muted-foreground tabular-nums">
        Showing {pagination.from}&ndash;{pagination.to} of {pagination.total}
      </p>
    </nav>
  )
}
