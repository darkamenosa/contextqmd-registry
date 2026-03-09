import { cn } from "@/lib/utils"

interface StatusBadgeProps {
  status: string
  showDot?: boolean
  children?: React.ReactNode
}

type StatusTone = "positive" | "warning" | "critical" | "neutral"

const statusTones: Record<string, StatusTone> = {
  active: "positive",
  published: "positive",
  fulfilled: "positive",
  paid: "positive",
  success: "positive",
  completed: "positive",
  suspended: "warning",
  pending: "warning",
  draft: "neutral",
  inactive: "neutral",
  failed: "critical",
  deleted: "critical",
  cancelled: "critical",
  expired: "critical",
}

const toneStyles: Record<StatusTone, { badge: string; dot: string }> = {
  positive: {
    badge:
      "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-400",
    dot: "bg-emerald-500",
  },
  warning: {
    badge:
      "bg-amber-50 text-amber-700 dark:bg-amber-950/50 dark:text-amber-400",
    dot: "bg-amber-500",
  },
  critical: {
    badge: "bg-red-50 text-red-700 dark:bg-red-950/50 dark:text-red-400",
    dot: "bg-red-500",
  },
  neutral: {
    badge: "bg-muted text-muted-foreground",
    dot: "bg-muted-foreground/50",
  },
}

function getTone(status: string): StatusTone {
  return statusTones[status.toLowerCase()] ?? "neutral"
}

export function StatusBadge({
  status,
  showDot = true,
  children,
}: StatusBadgeProps) {
  const tone = getTone(status)
  const styles = toneStyles[tone]

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium",
        styles.badge
      )}
    >
      {showDot && <span className={cn("size-1.5 rounded-full", styles.dot)} />}
      {children ??
        status.charAt(0).toUpperCase() + status.slice(1).toLowerCase()}
    </span>
  )
}
