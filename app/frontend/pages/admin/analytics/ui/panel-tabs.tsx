import type { ReactNode } from "react"
import { ChevronDown } from "lucide-react"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

export function PanelTabs({ children }: { children: ReactNode }) {
  return (
    <div className="flex items-center gap-4 text-sm font-semibold">
      {children}
    </div>
  )
}

export function PanelTab({
  active,
  onClick,
  children,
}: {
  active: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "rounded-none border-b-2 pb-1 transition-colors",
        active
          ? "border-primary text-primary"
          : "border-transparent text-muted-foreground hover:text-primary",
      ].join(" ")}
    >
      {children}
    </button>
  )
}

type PanelTabDropdownProps = {
  active: boolean
  label: string
  options: Array<{ label: string; value: string }>
  onSelect: (value: string) => void
}

export function PanelTabDropdown({
  active,
  label,
  options,
  onSelect,
}: PanelTabDropdownProps) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={[
          "inline-flex items-center gap-1 border-b-2 pb-1 transition-colors",
          active
            ? "border-primary text-primary"
            : "border-transparent text-muted-foreground hover:text-primary",
        ].join(" ")}
      >
        {label}
        <ChevronDown className="size-3.5" aria-hidden="true" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48 text-sm">
        {options.map((option) => (
          <DropdownMenuItem
            key={option.value}
            onClick={() => onSelect(option.value)}
            className="cursor-pointer"
          >
            {option.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
