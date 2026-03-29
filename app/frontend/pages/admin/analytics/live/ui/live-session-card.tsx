import { useEffect, useState } from "react"
import { Users, X } from "lucide-react"

import VisitorAvatar from "@/components/analytics/visitor-avatar"

import { flagFromIso2 } from "../../lib/country-flag"
import { formatCompactLocation } from "../../ui/profile/formatters"
import {
  ProfileBrowserInline,
  ProfileDeviceInline,
  ProfileOSInline,
} from "../../ui/profile/primitives"
import {
  deviceLabel,
  formatDuration,
  formatRelativeTime,
  liveSessionDurationSeconds,
} from "../lib/live-utils"
import type { LiveSession } from "../types"

function useLiveDuration(session: LiveSession) {
  const [nowMs, setNowMs] = useState(() => {
    const startedAtMs = Date.parse(session.startedAt ?? "")
    return Number.isFinite(startedAtMs) ? startedAtMs : 0
  })

  useEffect(() => {
    if (!session.active) return

    const id = setInterval(() => setNowMs(Date.now()), 1000)
    return () => clearInterval(id)
  }, [session.active, session.id])

  return liveSessionDurationSeconds(session, nowMs)
}

export default function LiveSessionCard({
  session,
  onClose,
  onSelectSession,
  sessionsAtCell,
}: {
  session: LiveSession
  onClose: () => void
  onSelectSession: (sessionId: string) => void
  sessionsAtCell: LiveSession[]
}) {
  const liveDuration = useLiveDuration(session)
  const sessionStatus = session.active
    ? "Live now"
    : session.lastSeenAt
      ? `Last active ${formatRelativeTime(session.lastSeenAt)}`
      : "Session ended"
  const locationLabel = formatCompactLocation(
    {
      city: session.city,
      region: session.region,
      country: session.country,
      countryCode: session.countryCode,
    },
    { flagShown: true }
  )
  const locationFlag = flagFromIso2(session.countryCode ?? undefined)

  return (
    <section className="overflow-hidden rounded-xl border border-border/60 bg-card/90 shadow-lg backdrop-blur-md">
      {/* Identity */}
      <div className="flex items-start gap-3 px-4 py-2.5">
        <VisitorAvatar name={session.name} size={40} />
        <div className="min-w-0 flex-1">
          <div className="flex items-start gap-2">
            <span className="truncate text-sm/5 font-semibold text-foreground">
              {session.name}
            </span>
            <span
              className={`shrink-0 rounded-full px-2 py-0.5 text-xs/4 font-medium ${
                session.active
                  ? "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
                  : "bg-muted text-muted-foreground"
              }`}
            >
              {sessionStatus}
            </span>
            <button
              type="button"
              className="-mr-1 ml-auto shrink-0 rounded-md p-1 text-muted-foreground/50 transition hover:bg-muted hover:text-foreground"
              onClick={onClose}
              aria-label="Close visitor details"
            >
              <X className="size-4" />
            </button>
          </div>
          <div className="mt-0.5 truncate text-xs/4 text-muted-foreground">
            {session.identified
              ? session.email || "Identified visitor"
              : "Anonymous visitor"}
          </div>
          {locationLabel && (
            <div className="mt-1 text-xs/4 text-muted-foreground">
              <span className="truncate">
                {locationFlag ? `${locationFlag} ` : ""}
                {locationLabel}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Device environment */}
      {(session.deviceType || session.os || session.browser) && (
        <div className="flex flex-wrap items-center gap-1.5 border-t border-border/40 px-4 py-2 text-xs/4 text-muted-foreground">
          {session.deviceType && (
            <ProfileDeviceInline
              deviceType={session.deviceType}
              label={deviceLabel(session.deviceType)}
              iconClassName="size-3.5 text-muted-foreground"
            />
          )}
          {session.deviceType && session.os && (
            <span className="text-muted-foreground/30">·</span>
          )}
          {session.os && (
            <ProfileOSInline
              os={session.os}
              iconClassName="size-3.5"
              textClassName="truncate"
            />
          )}
          {(session.deviceType || session.os) && session.browser && (
            <span className="text-muted-foreground/30">·</span>
          )}
          {session.browser && (
            <ProfileBrowserInline
              browser={session.browser}
              iconClassName="size-3.5"
              textClassName="truncate"
            />
          )}
        </div>
      )}

      {sessionsAtCell.length > 1 ? (
        <div className="flex flex-col gap-2 border-t border-border/40 px-4 py-2">
          <div className="flex items-center gap-1.5 text-xs/4 font-medium tracking-wide text-muted-foreground/70 uppercase">
            <Users className="size-3" />
            <span>{sessionsAtCell.length} sessions here</span>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {sessionsAtCell.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`rounded-full border px-2.5 py-1 text-xs/4 font-medium transition ${
                  item.id === session.id
                    ? "border-primary/30 bg-primary/10 text-primary"
                    : "border-border bg-background/50 text-muted-foreground hover:bg-muted hover:text-foreground"
                }`}
                onClick={() => onSelectSession(item.id)}
              >
                {item.name}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div className="border-t border-border/40 px-4 py-1.5">
        <div className="flex items-center justify-between border-b border-border/30 py-1.5">
          <span className="text-xs/4 text-muted-foreground">Referrer</span>
          <span className="truncate pl-3 text-right text-xs/4 font-medium text-foreground">
            {session.source || "Direct / None"}
          </span>
        </div>
        <div className="flex items-center justify-between border-b border-border/30 py-1.5">
          <span className="text-xs/4 text-muted-foreground">Current URL</span>
          <span className="truncate pl-3 text-right font-mono text-xs/4 font-medium text-foreground">
            {session.currentPage || "/"}
          </span>
        </div>
        <div className="flex items-center justify-between border-b border-border/30 py-1.5">
          <span className="text-xs/4 text-muted-foreground">Session time</span>
          <span className="text-xs/4 font-medium text-foreground tabular-nums">
            {formatDuration(liveDuration)}
          </span>
        </div>
        <div className="flex items-center justify-between py-1.5">
          <span className="text-xs/4 text-muted-foreground">Total visits</span>
          <span className="text-xs/4 font-medium text-foreground">
            {session.totalVisits}
          </span>
        </div>
      </div>
    </section>
  )
}
