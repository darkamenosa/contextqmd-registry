import { useEffect, useMemo, useRef, useState } from "react"
import { Check, ChevronDown } from "lucide-react"

import { Input } from "@/components/ui/input"

export default function SelectionTabDropdown({
  active,
  label,
  options,
  value,
  searchPlaceholder,
  onSelect,
}: {
  active: boolean
  label: string
  options: string[]
  value?: string
  searchPlaceholder: string
  onSelect: (next: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState("")
  const inputRef = useRef<HTMLInputElement | null>(null)
  const rootRef = useRef<HTMLDivElement | null>(null)

  const filtered = useMemo(() => {
    if (!search) return options
    return options.filter((option) =>
      option.toLowerCase().includes(search.toLowerCase())
    )
  }, [options, search])

  useEffect(() => {
    if (!open) return
    const id = window.requestAnimationFrame(() => {
      inputRef.current?.focus({ preventScroll: true })
    })
    return () => window.cancelAnimationFrame(id)
  }, [open])

  useEffect(() => {
    if (!open) return
    const handlePointerDown = (event: MouseEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) {
        setOpen(false)
        setSearch("")
      }
    }
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false)
        setSearch("")
      }
    }
    window.addEventListener("mousedown", handlePointerDown)
    window.addEventListener("keydown", handleEscape)
    return () => {
      window.removeEventListener("mousedown", handlePointerDown)
      window.removeEventListener("keydown", handleEscape)
    }
  }, [open])

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => {
          setOpen((current) => {
            const next = !current
            if (!next) setSearch("")
            return next
          })
        }}
        className={[
          "inline-flex items-center gap-1 border-b-2 pb-1 transition-colors",
          active
            ? "border-primary text-primary"
            : "border-transparent text-muted-foreground hover:text-primary",
        ].join(" ")}
      >
        {label}
        <ChevronDown className="size-3.5" aria-hidden="true" />
      </button>
      {open ? (
        <div className="absolute top-full right-0 z-30 mt-2 w-72 overflow-hidden rounded-2xl border border-border bg-popover text-popover-foreground shadow-xl ring-1 ring-foreground/10">
          <div className="border-b p-2">
            <Input
              ref={inputRef}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={searchPlaceholder}
            />
          </div>
          <div className="max-h-72 overflow-y-auto py-1 text-sm">
            {filtered.map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => {
                  onSelect(option)
                  setOpen(false)
                  setSearch("")
                }}
                className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left hover:bg-accent hover:text-accent-foreground"
              >
                <span className="truncate">{option}</span>
                {option === value ? (
                  <Check className="size-4 text-primary" aria-hidden="true" />
                ) : null}
              </button>
            ))}
            {filtered.length === 0 ? (
              <div className="px-3 py-2 text-sm text-muted-foreground">
                No matches
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  )
}
