import type { HexHighlightSelection } from "@/components/analytics/hex-highlights"

import { formatCompactLocation } from "../../ui/profile/formatters"
import type {
  LiveEvent,
  LiveSession,
  LiveSessionSnapshot,
  LiveStats,
} from "../types"
import { sortEventsAsc } from "./live-event-buffer"

const SESSION_CARD_WIDTH = 320
const SESSION_CARD_EDGE_PADDING = 12
const SESSION_CARD_VERTICAL_OFFSET = 18
const SESSION_CARD_ESTIMATED_HEIGHT = 212

function clamp(value: number, min: number, max: number) {
  if (max < min) return min
  return Math.min(Math.max(value, min), max)
}

export function getSessionCardAnchorStyle(anchor: HexHighlightSelection) {
  const left = clamp(
    anchor.x - SESSION_CARD_WIDTH / 2,
    SESSION_CARD_EDGE_PADDING,
    anchor.width - SESSION_CARD_WIDTH - SESSION_CARD_EDGE_PADDING
  )
  const top = clamp(
    anchor.y - SESSION_CARD_ESTIMATED_HEIGHT - SESSION_CARD_VERTICAL_OFFSET,
    SESSION_CARD_EDGE_PADDING,
    anchor.height - SESSION_CARD_ESTIMATED_HEIGHT - SESSION_CARD_EDGE_PADDING
  )

  return {
    left: `${left}px`,
    top: `${top}px`,
    width: `${SESSION_CARD_WIDTH}px`,
  }
}

export function sortInitialEvents(stats: LiveStats): LiveStats {
  return {
    ...stats,
    recentEvents: sortEventsAsc(stats.recentEvents),
    liveSessions: stats.liveSessions.map((session: LiveSession) => ({
      ...session,
      recentEvents: sortEventsAsc(session.recentEvents),
    })),
  }
}

function parseTimestamp(value?: string | null) {
  if (!value) return null
  const timestamp = Date.parse(value)
  return Number.isFinite(timestamp) ? timestamp : null
}

export function liveSessionDurationSeconds(
  session: Pick<LiveSessionSnapshot, "active" | "startedAt" | "lastSeenAt">,
  nowMs = Date.now()
) {
  const startedAt = parseTimestamp(session.startedAt)
  if (startedAt == null) return 0

  const endedAt =
    session.active === false ? parseTimestamp(session.lastSeenAt) : nowMs

  return Math.max(0, Math.round(((endedAt ?? nowMs) - startedAt) / 1000))
}

export function displayCountryLabel(country?: string | null) {
  const value = country?.trim()
  return value || null
}

export function liveEventDescription(event: LiveEvent) {
  if (event.eventName === "pageview" && event.page) {
    return { verb: "visited", target: event.page }
  }
  if (event.eventName.startsWith("exit_")) {
    return { verb: "exited to", target: event.page || event.label }
  }

  const name =
    event.eventName !== event.label
      ? event.eventName
      : event.label.replace(/^Viewed page\s*/, "").trim() || event.eventName

  return { verb: "performed", target: name, onPage: event.page }
}

export function liveEventLocation(event: LiveEvent) {
  const compact = formatCompactLocation(
    {
      city: event.city,
      region: event.region,
      country: event.country,
      countryCode: event.countryCode,
    },
    { flagShown: true }
  )

  return compact || event.locationLabel?.trim() || null
}

export function deviceLabel(type?: string | null) {
  const normalized = (type ?? "").toLowerCase()
  if (normalized === "mobile") return "Mobile"
  if (normalized === "tablet") return "Tablet"
  return "Desktop"
}

export function formatRelativeTime(value: string) {
  const seconds = Math.max(
    0,
    Math.round((Date.now() - new Date(value).getTime()) / 1000)
  )

  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  return `${Math.floor(seconds / 3600)}h ago`
}

export function formatDuration(value: number) {
  const totalSeconds = Math.max(0, value)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60

  return `${minutes} min ${String(seconds).padStart(2, "0")} sec`
}
