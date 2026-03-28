import { useEffect, useRef, useState } from "react"
import { Activity, ChevronDown, ExternalLink, Eye, Zap } from "lucide-react"

import { flagFromIso2 } from "../../lib/country-flag"
import {
  formatRelativeTime,
  liveEventDescription,
  liveEventLocation,
} from "../lib/live-utils"
import type { LiveEvent } from "../types"

const MAX_VISIBLE_EVENTS = 50
const NEW_EVENT_ANIMATION_MS = 900

function liveEventIcon(eventName: string) {
  if (eventName === "pageview")
    return <Eye className="size-3 text-blue-500/70" />
  if (eventName.startsWith("exit_"))
    return <ExternalLink className="size-3 text-orange-500/70" />
  return <Zap className="size-3 text-amber-500/70" />
}

export default function LiveEventsPanel({
  title,
  events,
  active = true,
  emptyMessage = "Waiting for activity...",
  hydrated,
  onSelectEvent,
  variant = "overlay",
}: {
  title?: string
  events: LiveEvent[]
  active?: boolean
  emptyMessage?: string
  hydrated: boolean
  onSelectEvent?: (event: LiveEvent) => void
  variant?: "overlay" | "card"
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const bottomRef = useRef<HTMLDivElement>(null)
  const [isAtBottom, setIsAtBottom] = useState(true)
  const prevCountRef = useRef(0)
  const previousEventIdsRef = useRef<Set<number> | null>(null)
  const [hasNewEvents, setHasNewEvents] = useState(false)
  const [isCollapsed, setIsCollapsed] = useState(false)
  const [freshEventIds, setFreshEventIds] = useState<number[]>([])

  const displayEvents = events
    .filter((event) => event.eventName !== "engagement")
    .slice(-MAX_VISIBLE_EVENTS)

  useEffect(() => {
    const element = scrollRef.current
    if (element) element.scrollTop = element.scrollHeight
  }, [])

  useEffect(() => {
    let nextEventsFrame: number | null = null

    if (displayEvents.length > prevCountRef.current) {
      if (isAtBottom && !isCollapsed) {
        const element = scrollRef.current
        if (element) element.scrollTop = element.scrollHeight
      } else {
        nextEventsFrame = requestAnimationFrame(() => {
          setHasNewEvents(true)
        })
      }
    }
    prevCountRef.current = displayEvents.length

    return () => {
      if (nextEventsFrame !== null) cancelAnimationFrame(nextEventsFrame)
    }
  }, [displayEvents.length, isAtBottom, isCollapsed])

  useEffect(() => {
    const previousIds = previousEventIdsRef.current
    const nextIds = new Set(displayEvents.map((event) => event.id))
    previousEventIdsRef.current = nextIds

    if (!previousIds) return

    const appendedIds = displayEvents
      .map((event) => event.id)
      .filter((id) => !previousIds.has(id))

    if (appendedIds.length === 0) return

    setFreshEventIds((current) =>
      Array.from(new Set([...current, ...appendedIds]))
    )

    const timeoutId = window.setTimeout(() => {
      setFreshEventIds((current) =>
        current.filter((id) => !appendedIds.includes(id))
      )
    }, NEW_EVENT_ANIMATION_MS)

    return () => {
      clearTimeout(timeoutId)
    }
  }, [displayEvents])

  useEffect(() => {
    if (!isCollapsed) {
      const element = scrollRef.current
      if (element) {
        requestAnimationFrame(() => {
          element.scrollTop = element.scrollHeight
        })
      }
    }
  }, [isCollapsed])

  const handleScroll = () => {
    const element = scrollRef.current
    if (!element) return
    const atBottom =
      element.scrollHeight - element.scrollTop - element.clientHeight < 30
    setIsAtBottom(atBottom)
    if (atBottom) setHasNewEvents(false)
  }

  const scrollToBottom = () => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
    setHasNewEvents(false)
  }

  const isOverlay = variant === "overlay"
  const sectionClassName = isOverlay
    ? "relative overflow-hidden rounded-xl border border-border/60 bg-card/85 shadow-lg backdrop-blur-md"
    : "relative rounded-xl border border-border bg-card"

  return (
    <section className={sectionClassName}>
      <div className="flex items-center gap-2.5 border-b border-border/50 px-3.5 py-2.5">
        <div className="relative flex size-2 items-center justify-center">
          {active ? (
            <>
              <span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-50" />
              <span className="relative inline-flex size-2 rounded-full bg-emerald-500" />
            </>
          ) : (
            <span className="relative inline-flex size-2 rounded-full bg-muted-foreground/40" />
          )}
        </div>
        <span className="flex-1 truncate text-xs font-semibold tracking-wide text-foreground/90">
          {title || "Live activity"}
        </span>
        {displayEvents.length > 0 && (
          <span className="rounded-full bg-muted/60 px-2 py-0.5 text-[10px] font-medium text-muted-foreground tabular-nums">
            {displayEvents.length}
          </span>
        )}
        <button
          type="button"
          onClick={() => {
            setIsCollapsed((collapsed) => !collapsed)
            if (hasNewEvents) setHasNewEvents(false)
          }}
          className="rounded-md p-0.5 text-muted-foreground/60 transition hover:bg-muted/40 hover:text-foreground"
          aria-label={
            isCollapsed ? "Expand activity feed" : "Collapse activity feed"
          }
        >
          <ChevronDown
            className={`size-3.5 transition-transform duration-200 ${isCollapsed ? "rotate-180" : ""}`}
          />
        </button>
      </div>

      <div
        className={`grid transition-[grid-template-rows] duration-300 ease-out ${isCollapsed ? "grid-rows-[0fr]" : "grid-rows-[1fr]"}`}
      >
        <div className="overflow-hidden">
          <div
            ref={scrollRef}
            onScroll={handleScroll}
            className={`overflow-y-auto px-2 py-1 ${isOverlay ? "max-h-[14rem] min-h-[6rem]" : "max-h-[16rem] min-h-[6rem]"}`}
          >
            <div className="flex min-h-full flex-col justify-end">
              {displayEvents.length > 0 ? (
                <div className="flex flex-col">
                  {displayEvents.map((event) => {
                    const description = liveEventDescription(event)
                    const isLink =
                      description.target.startsWith("/") ||
                      description.target.startsWith("http")
                    const location = liveEventLocation(event)
                    const flag = flagFromIso2(event.countryCode ?? undefined)

                    return (
                      <div
                        key={event.id}
                        className={`group flex items-start gap-2.5 rounded-lg px-2 py-2 transition hover:bg-muted/40 ${
                          freshEventIds.includes(event.id)
                            ? "animate-in duration-300 fade-in-0 slide-in-from-bottom-2"
                            : ""
                        }`}
                      >
                        <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-md bg-muted/50 text-muted-foreground/60 transition group-hover:bg-muted group-hover:text-muted-foreground">
                          {liveEventIcon(event.eventName)}
                        </span>

                        <div className="min-w-0 flex-1">
                          <div className="flex items-baseline gap-1 text-[13px] leading-tight">
                            <button
                              type="button"
                              className="shrink-0 font-semibold text-foreground hover:underline hover:underline-offset-2"
                              onClick={() => onSelectEvent?.(event)}
                            >
                              {event.name || "Visitor"}
                            </button>
                            {location && (
                              <span className="shrink-0 text-xs text-muted-foreground/60">
                                from{" "}
                                {flag && location !== "unknown location" && (
                                  <span className="text-xs leading-none">
                                    {flag}
                                  </span>
                                )}{" "}
                                <span className="font-medium text-foreground/80">
                                  {location}
                                </span>
                              </span>
                            )}
                            <span className="shrink-0 text-xs text-muted-foreground/60">
                              {description.verb}
                            </span>
                            <span className="min-w-0 truncate">
                              {isLink ? (
                                <a
                                  href={description.target}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-[11px] text-foreground transition hover:bg-muted"
                                >
                                  {description.target}
                                </a>
                              ) : (
                                <span className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-[11px] text-foreground/80">
                                  {description.target}
                                </span>
                              )}
                            </span>
                          </div>

                          <div className="mt-0.5 flex items-center gap-2 text-[10px] text-muted-foreground/50">
                            <span className="tabular-nums">
                              {hydrated
                                ? formatRelativeTime(event.occurredAt)
                                : " "}
                            </span>
                            {!event.active &&
                            event.lastSeenAt &&
                            event.lastSeenAt !== event.occurredAt ? (
                              <>
                                <span className="text-muted-foreground/30">
                                  ·
                                </span>
                                <span>
                                  last active{" "}
                                  {hydrated
                                    ? formatRelativeTime(event.lastSeenAt)
                                    : " "}
                                </span>
                              </>
                            ) : null}
                            {description.onPage ? (
                              <>
                                <span className="text-muted-foreground/30">
                                  ·
                                </span>
                                <span>on</span>
                                <a
                                  href={description.onPage}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="truncate underline decoration-muted-foreground/20 underline-offset-2 hover:text-foreground"
                                >
                                  {description.onPage}
                                </a>
                              </>
                            ) : null}
                          </div>
                        </div>
                      </div>
                    )
                  })}
                  <div ref={bottomRef} />
                </div>
              ) : (
                <div className="flex flex-col items-center justify-center py-8 text-center">
                  <Activity className="mb-2 size-4 text-muted-foreground/30" />
                  <span className="text-xs text-muted-foreground">
                    {emptyMessage}
                  </span>
                </div>
              )}
            </div>
          </div>

          {hasNewEvents && !isCollapsed ? (
            <button
              type="button"
              onClick={scrollToBottom}
              className="absolute bottom-3 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1.5 text-[11px] font-medium text-foreground shadow-lg transition hover:bg-muted/80"
            >
              <ChevronDown className="size-3" />
              New events
            </button>
          ) : null}
        </div>
      </div>

      {isCollapsed && hasNewEvents ? (
        <div className="border-t border-border/50 px-3.5 py-1.5">
          <button
            type="button"
            onClick={() => {
              setIsCollapsed(false)
              setHasNewEvents(false)
            }}
            className="flex items-center gap-1.5 text-[11px] font-medium text-blue-600 transition hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300"
          >
            <span className="relative flex size-1.5">
              <span className="absolute inline-flex size-full animate-ping rounded-full bg-blue-400 opacity-75" />
              <span className="relative inline-flex size-1.5 rounded-full bg-blue-500" />
            </span>
            New events available
          </button>
        </div>
      ) : null}
    </section>
  )
}
