import { useEffect, useRef, useState } from "react"
import { Filter } from "lucide-react"

import { useClientComponent } from "@/hooks/use-client-component"
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
import { FILTER_PICKER_COLUMNS } from "./filter-utils"

const loadFilterDialogComponent = () =>
  import("../filter-dialog").then(({ default: component }) => component)

type FilterDialogType =
  | "page"
  | "location"
  | "source"
  | "utm"
  | "browser"
  | "browser_version"
  | "os"
  | "os_version"
  | "size"
  | "goal"
  | "property"

function filterDialogTypeForKey(key: string): FilterDialogType | null {
  switch (key) {
    case "page":
      return "page"
    case "location":
      return "location"
    case "source":
      return "source"
    case "utm":
      return "utm"
    case "browser":
      return "browser"
    case "browser_version":
      return "browser_version"
    case "os":
      return "os"
    case "os_version":
      return "os_version"
    case "size":
      return "size"
    case "goal":
      return "goal"
    case "property":
      return "property"
    default:
      return null
  }
}

export default function FilterMenu() {
  const { updateQuery } = useQueryContext()
  const [open, setOpen] = useState(false)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [dialogType, setDialogType] = useState<FilterDialogType>("page")
  const openDialogFrameRef = useRef<number | null>(null)
  const { Component: FilterDialogComponent, load: loadFilterDialog } =
    useClientComponent(loadFilterDialogComponent)

  useEffect(() => {
    return () => {
      if (openDialogFrameRef.current != null) {
        window.cancelAnimationFrame(openDialogFrameRef.current)
      }
    }
  }, [])

  const setFilter = (key: string, value: string) => {
    updateQuery((current) => ({
      ...current,
      filters: { ...current.filters, [key]: value },
    }))
  }

  const openFilterDialog = (nextType: FilterDialogType) => {
    setOpen(false)

    if (openDialogFrameRef.current != null) {
      window.cancelAnimationFrame(openDialogFrameRef.current)
    }

    openDialogFrameRef.current = window.requestAnimationFrame(() => {
      openDialogFrameRef.current = window.requestAnimationFrame(() => {
        void loadFilterDialog()
          .then(() => {
            setDialogType(nextType)
            setDialogOpen(true)
          })
          .catch((error) => {
            console.error("Failed to load filter dialog", error)
          })
          .finally(() => {
            openDialogFrameRef.current = null
          })
      })
    })
  }

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
        <Filter className="size-4" />
        <span className="hidden sm:inline">Filters</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        sideOffset={8}
        alignOffset={-6}
        className="w-64 rounded-md border border-border bg-popover p-1 shadow-md"
      >
        {FILTER_PICKER_COLUMNS.map((column, index) => (
          <div key={column.title} className="mb-1 last:mb-0">
            <DropdownMenuGroup>
              <DropdownMenuLabel className="text-[11px] font-extrabold tracking-wider text-primary uppercase">
                {column.title}
              </DropdownMenuLabel>
              {column.items.map((item) => (
                <DropdownMenuItem
                  key={item.label}
                  onClick={() => {
                    const dialogType = filterDialogTypeForKey(item.key)
                    if (dialogType) {
                      openFilterDialog(dialogType)
                    } else {
                      setFilter(item.key, item.value)
                      setOpen(false)
                    }
                  }}
                >
                  {item.label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
            {index < FILTER_PICKER_COLUMNS.length - 1 ? (
              <DropdownMenuSeparator />
            ) : null}
          </div>
        ))}
      </DropdownMenuContent>
      {FilterDialogComponent ? (
        <FilterDialogComponent
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          type={dialogType}
        />
      ) : null}
    </DropdownMenu>
  )
}
