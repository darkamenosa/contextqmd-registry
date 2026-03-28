import { useEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"
import { X } from "lucide-react"

import { Button } from "@/components/ui/button"

import { lockBodyScroll } from "../lib/body-scroll-lock"
import {
  DeviceFilterForm,
  DeviceVersionFilterForm,
  GoalFilterForm,
  LocationFilterForm,
  PageFilterForm,
  PropertyFilterForm,
  ScreenSizeFilterForm,
  SourceFilterForm,
  UtmFilterForm,
  type DialogFormProps,
} from "./filter-dialog/forms"

type DialogType =
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

type FilterDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  type: DialogType
}

export default function FilterDialog({
  open,
  onOpenChange,
  type,
}: FilterDialogProps) {
  const [mounted] = useState(() => typeof document !== "undefined")
  const dialogRef = useRef<HTMLDivElement | null>(null)
  const [canApply, setCanApply] = useState(false)
  const applyRef = useRef<null | (() => void)>(null)

  useEffect(() => {
    if (!open) return
    return lockBodyScroll()
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onOpenChange(false)
      }
    }
    window.addEventListener("keydown", onKey)
    setTimeout(() => dialogRef.current?.focus(), 0)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onOpenChange])

  if (!mounted || !open) return null

  const formProps: DialogFormProps = {
    onDone: () => onOpenChange(false),
    onProvideControls: (apply, enabled) => {
      applyRef.current = apply
      setCanApply(enabled)
    },
  }

  return createPortal(
    <div
      className="fixed inset-0 z-[60] flex items-start justify-center bg-background/80 p-4 pt-10 backdrop-blur-xs md:pt-12 lg:pt-16"
      onClick={() => onOpenChange(false)}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
        className="relative mx-auto flex h-[84vh] max-h-[84vh] w-full max-w-6xl flex-col rounded-xl border border-border bg-card shadow-xl outline-hidden"
        onClick={(event) => event.stopPropagation()}
        onKeyDown={(event) => {
          if (
            event.key === "Enter" &&
            (event.metaKey ||
              event.ctrlKey ||
              event.shiftKey ||
              event.altKey) === false
          ) {
            if (canApply && applyRef.current) {
              event.preventDefault()
              applyRef.current()
            }
          }
        }}
      >
        <header className="flex flex-col gap-2 border-b border-border px-6 py-4 sm:flex-row sm:items-center sm:justify-between md:px-8 md:py-4">
          <h2 className="text-xl font-semibold text-foreground">
            {titleFor(type)}
          </h2>
          <div className="flex items-center gap-3">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => onOpenChange(false)}
              aria-label="Close filter dialog"
            >
              <X className="size-5" />
            </Button>
          </div>
        </header>

        <div className="flex-1 overflow-hidden">
          <div className="h-full overflow-y-auto p-6 md:p-8">
            <FilterDialogBody type={type} formProps={formProps} />
          </div>
        </div>

        <footer className="flex shrink-0 items-center justify-end gap-3 border-t border-border px-6 py-3 md:px-8 md:py-4">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={!canApply}
            onClick={() => applyRef.current && applyRef.current()}
          >
            Apply filter
          </Button>
        </footer>
      </div>
    </div>,
    document.body
  )
}

function FilterDialogBody({
  type,
  formProps,
}: {
  type: DialogType
  formProps: DialogFormProps
}) {
  switch (type) {
    case "page":
      return <PageFilterForm {...formProps} />
    case "location":
      return <LocationFilterForm {...formProps} />
    case "source":
      return <SourceFilterForm {...formProps} />
    case "utm":
      return <UtmFilterForm {...formProps} />
    case "browser":
      return <DeviceFilterForm {...formProps} dim="browser" />
    case "os":
      return <DeviceFilterForm {...formProps} dim="os" />
    case "browser_version":
      return <DeviceVersionFilterForm {...formProps} dim="browser_version" />
    case "os_version":
      return <DeviceVersionFilterForm {...formProps} dim="os_version" />
    case "size":
      return <ScreenSizeFilterForm {...formProps} />
    case "goal":
      return <GoalFilterForm {...formProps} />
    case "property":
      return <PropertyFilterForm {...formProps} />
    default:
      return null
  }
}

function titleFor(type: DialogType) {
  switch (type) {
    case "page":
      return "Filter by Page"
    case "location":
      return "Filter by Location"
    case "source":
      return "Filter by Source"
    case "utm":
      return "Filter by UTM tags"
    case "browser":
      return "Filter by Browser"
    case "browser_version":
      return "Filter by Browser Version"
    case "os":
      return "Filter by Operating System"
    case "os_version":
      return "Filter by OS Version"
    case "size":
      return "Filter by Screen Size"
    case "goal":
      return "Filter by Goal"
    case "property":
      return "Filter by Property"
    default:
      return "Filter"
  }
}
