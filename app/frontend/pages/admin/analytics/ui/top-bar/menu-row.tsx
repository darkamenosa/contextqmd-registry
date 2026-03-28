import type { ReactNode } from "react"

export default function MenuRow({
  label,
  hint,
  active,
  leftIcon,
  rightIcon,
}: {
  label: string
  hint?: string
  active?: boolean
  leftIcon?: ReactNode
  rightIcon?: ReactNode
}) {
  return (
    <span className="flex w-full items-center justify-between">
      <span
        className={`flex items-center ${active ? "font-semibold text-primary" : ""}`}
      >
        {leftIcon}
        {label}
      </span>
      {rightIcon ? (
        rightIcon
      ) : hint ? (
        <span className="rounded-md border border-border px-1.5 py-0.5 text-[11px] text-muted-foreground">
          {hint}
        </span>
      ) : null}
    </span>
  )
}
