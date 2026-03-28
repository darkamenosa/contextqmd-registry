import { Layers } from "lucide-react"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

import { useQueryContext } from "../../query-context"
import { useSiteContext } from "../../site-context"

export default function SegmentMenu() {
  const site = useSiteContext()
  const { query, updateQuery } = useQueryContext()
  const activeSegment = (query.filters as Record<string, string | undefined>)
    .segment

  const applySegment = (segmentId: string | null) => {
    updateQuery((current) => {
      const nextFilters = { ...current.filters }
      if (segmentId) {
        nextFilters.segment = segmentId
      } else {
        delete nextFilters.segment
      }
      return { ...current, filters: nextFilters }
    })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
        <Layers className="size-4" />
        <span className="hidden sm:inline">
          {activeSegment
            ? (site.segments.find((segment) => segment.id === activeSegment)
                ?.name ?? "Segment")
            : "Segments"}
        </span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Saved segments</DropdownMenuLabel>
          {site.segments.map((segment) => (
            <DropdownMenuItem
              key={segment.id}
              onClick={() => applySegment(segment.id)}
              className="hover:bg-accent data-[selected=true]:bg-primary/10"
            >
              {segment.name}
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onClick={() => applySegment(null)}
          className="hover:bg-accent"
        >
          All visitors
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
