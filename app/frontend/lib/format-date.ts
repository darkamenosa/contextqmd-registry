export function formatDateShort(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

export function formatCalendarDay(day: string): string {
  const [year, month, date] = day.split("-").map(Number)
  if (!year || !month || !date) return day

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, date, 12)))
}

export function formatDateShortUTC(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  })
}

export function formatDateTimeUTC(iso: string): string {
  return new Date(iso).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    timeZone: "UTC",
    timeZoneName: "short",
  })
}

/**
 * Shopify-style relative date formatting:
 * - < 1 min:        "Just now"
 * - 1–59 min:       "13 minutes ago"
 * - Today:          "Today at 10:30 am"
 * - Yesterday:      "Yesterday at 10:30 am"
 * - Last 7 days:    "Friday at 10:30 am"
 * - 7 days–1 year:  "Aug 14 at 10:30 am"
 * - > 1 year:       "Aug 14, 2016 at 10:30 am"
 */
export function formatDateTime(iso: string): string {
  const date = new Date(iso)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMin = Math.floor(diffMs / 60000)

  if (diffMin < 1) return "Just now"
  if (diffMin < 60) return `${diffMin} minute${diffMin === 1 ? "" : "s"} ago`

  const today = startOfDay(now)
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)
  const weekAgo = new Date(today)
  weekAgo.setDate(weekAgo.getDate() - 6)

  const time = formatTime(date)

  if (date >= today) return `Today at ${time}`
  if (date >= yesterday) return `Yesterday at ${time}`
  if (date >= weekAgo) return `${dayName(date)} at ${time}`

  const sameYear = date.getFullYear() === now.getFullYear()
  if (sameYear) return `${monthDay(date)} at ${time}`

  return `${monthDay(date)}, ${date.getFullYear()} at ${time}`
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function formatTime(d: Date): string {
  return d
    .toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    })
    .toLowerCase()
}

function dayName(d: Date): string {
  return d.toLocaleDateString("en-US", { weekday: "long" })
}

function monthDay(d: Date): string {
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

export function formatTimeAgo(iso: string, includeMinutes = false): string {
  const diff = Date.now() - new Date(iso).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return "just now"
  if (includeMinutes && minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 1) return "just now"
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function formatCount(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`
  return String(n)
}
