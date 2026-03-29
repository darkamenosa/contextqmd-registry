import { startTransition, useEffect, useMemo, useRef, useState } from "react"
import {
  Activity,
  ChevronDown,
  ChevronUp,
  Clock3,
  Cpu,
  CreditCard,
  Eye,
  Globe,
  Loader2,
  Route,
  Share2,
  Smartphone,
  Zap,
} from "lucide-react"

import { formatCalendarDay, formatDateTime } from "@/lib/format-date"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog"
import DeviceTypeIcon from "@/components/analytics/device-type-icon"
import VisitorAvatar from "@/components/analytics/visitor-avatar"

import {
  fetchProfileJourney,
  fetchProfileSession,
  fetchProfileSessions,
} from "../api"
import { getBrowserIcon, getOSIcon } from "../lib/device-visuals"
import { getSourceFaviconDomain } from "../lib/source-visuals"
import { useQueryContext } from "../query-context"
import type {
  ProfileJourneyPayload,
  ProfileListItem,
  ProfileSessionItem,
  ProfileSessionPayload,
} from "../types"
import {
  formatCompactNumber,
  formatProfileDuration,
  maskEmail,
} from "./profile/formatters"
import {
  ProfileBrowserInline,
  ProfileDeviceInline,
  ProfileLocationText,
  ProfileOSInline,
  ProfileSourceInline,
} from "./profile/primitives"
import {
  ActivityHeatmap,
  LocationList,
  SectionChips,
  SessionSourceSummary,
  TopPagesList,
} from "./profile/profile-insights"

type EventKind = "pageview" | "payment" | "event"

function classifyEvent(
  item: ProfileSessionPayload["events"][number]
): EventKind {
  if (item.eventName === "pageview" || item.label.startsWith("Viewed page")) {
    return "pageview"
  }
  if (
    item.eventName.toLowerCase().includes("payment") ||
    item.label.toLowerCase().includes("paid")
  ) {
    return "payment"
  }
  return "event"
}

function EventLabel({
  label,
  page,
  className,
}: {
  label: string
  page?: string | null
  className?: string
}) {
  const pagePath = page || label.match(/^Viewed page (\/\S*)/)?.[1]
  if (pagePath) {
    const prefix = label.replace(pagePath, "").trimEnd()
    return (
      <span className={className}>
        {prefix ? `${prefix} ` : ""}
        <a
          href={pagePath}
          target="_blank"
          rel="noopener noreferrer"
          className="underline decoration-muted-foreground/40 underline-offset-2 hover:decoration-foreground"
          onClick={(e) => e.stopPropagation()}
        >
          {pagePath}
        </a>
      </span>
    )
  }
  return <span className={className}>{label}</span>
}

function EventIcon({ kind }: { kind: EventKind }) {
  switch (kind) {
    case "pageview":
      return <Eye className="size-3.5 shrink-0 text-blue-500" />
    case "payment":
      return <CreditCard className="size-3.5 shrink-0 text-emerald-600" />
    default:
      return <Zap className="size-3.5 shrink-0 text-amber-500" />
  }
}

function shouldShowSecondaryPageLine(
  label: string,
  page?: string | null
): boolean {
  if (!page) return false

  const normalizedLabel = label.toLowerCase()
  const normalizedPage = page.toLowerCase()
  return !normalizedLabel.includes(normalizedPage)
}

export default function ProfileJourneySheet({
  open,
  onOpenChange,
  profile,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  profile: ProfileListItem | null
}) {
  const { query } = useQueryContext()
  const [data, setData] = useState<ProfileJourneyPayload | null>(null)
  const [loading, setLoading] = useState(false)
  const [sortOldest, setSortOldest] = useState(false)
  const [selectedActivityDay, setSelectedActivityDay] = useState<{
    date: string
    count: number
  } | null>(null)
  const [expandedSessionIds, setExpandedSessionIds] = useState<number[]>([])
  const [sessionPayloads, setSessionPayloads] = useState<
    Record<number, ProfileSessionPayload>
  >({})
  const [sessionLoadingIds, setSessionLoadingIds] = useState<number[]>([])

  const PAGE_SIZE = 20
  const [sessions, setSessions] = useState<ProfileSessionItem[]>([])
  const [sessionsPage, setSessionsPage] = useState(1)
  const [sessionsHasMore, setSessionsHasMore] = useState(false)
  const [sessionsLoading, setSessionsLoading] = useState(false)
  const requestIdRef = useRef(0)
  const sessionsRequestIdRef = useRef(0)
  const sessionsAbortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    if (!open || !profile) return

    const controller = new AbortController()
    const nextRequestId = requestIdRef.current + 1
    requestIdRef.current = nextRequestId
    startTransition(() => {
      setLoading(true)
      setExpandedSessionIds([])
      setSelectedActivityDay(null)
      setSessionPayloads({})
      setSessions([])
      setSessionsPage(1)
      setSessionsHasMore(false)
    })

    Promise.all([fetchProfileJourney(profile.id, query, controller.signal)])
      .then(([journeyData]) => {
        if (requestIdRef.current !== nextRequestId) return
        setData(journeyData)
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (requestIdRef.current !== nextRequestId) return
        setLoading(false)
      })

    return () => controller.abort()
  }, [open, profile, query])

  const selectedActivityDateParam = selectedActivityDay?.date

  useEffect(() => {
    if (!open || !profile) return

    sessionsAbortRef.current?.abort()
    const controller = new AbortController()
    sessionsAbortRef.current = controller
    const nextSessionsRequestId = sessionsRequestIdRef.current + 1
    sessionsRequestIdRef.current = nextSessionsRequestId

    startTransition(() => {
      setSessionsLoading(true)
      setExpandedSessionIds([])
      setSessionLoadingIds([])
      setSessions([])
      setSessionsPage(1)
      setSessionsHasMore(false)
    })

    fetchProfileSessions(
      profile.id,
      {
        limit: PAGE_SIZE,
        page: 1,
        date: selectedActivityDateParam,
      },
      controller.signal
    )
      .then((result) => {
        if (sessionsRequestIdRef.current !== nextSessionsRequestId) return
        setSessions(result.sessions)
        setSessionsHasMore(result.hasMore)
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (sessionsRequestIdRef.current !== nextSessionsRequestId) return
        setSessionsLoading(false)
      })

    return () => controller.abort()
  }, [open, profile, selectedActivityDateParam])

  const loadMoreSessions = () => {
    if (!profile || sessionsLoading || !sessionsHasMore) return

    sessionsAbortRef.current?.abort()
    const controller = new AbortController()
    sessionsAbortRef.current = controller
    const nextPage = sessionsPage + 1
    const nextSessionsRequestId = sessionsRequestIdRef.current + 1
    sessionsRequestIdRef.current = nextSessionsRequestId
    setSessionsLoading(true)

    fetchProfileSessions(
      profile.id,
      { limit: PAGE_SIZE, page: nextPage, date: selectedActivityDateParam },
      controller.signal
    )
      .then((result) => {
        if (sessionsRequestIdRef.current !== nextSessionsRequestId) return
        setSessions((prev) => [...prev, ...result.sessions])
        setSessionsHasMore(result.hasMore)
        setSessionsPage(nextPage)
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (sessionsRequestIdRef.current !== nextSessionsRequestId) return
        setSessionsLoading(false)
      })
  }

  const resolvedProfile = data?.profile || profile
  const orderedSessions = useMemo(() => {
    const sorted = [...sessions].sort((a, b) => {
      const at = new Date(a.startedAt || 0).getTime()
      const bt = new Date(b.startedAt || 0).getTime()
      return sortOldest ? at - bt : bt - at
    })
    return sorted
  }, [sessions, sortOldest])

  const loadSession = (session: ProfileSessionItem) => {
    if (!profile) return

    const isExpanded = expandedSessionIds.includes(session.visitId)

    if (sessionPayloads[session.visitId]) {
      setExpandedSessionIds((current) =>
        current.includes(session.visitId)
          ? current.filter((id) => id !== session.visitId)
          : [...current, session.visitId]
      )
      return
    }

    if (isExpanded) {
      setExpandedSessionIds((current) =>
        current.filter((id) => id !== session.visitId)
      )
      return
    }

    const controller = new AbortController()
    setExpandedSessionIds((current) =>
      current.includes(session.visitId)
        ? current
        : [...current, session.visitId]
    )
    setSessionLoadingIds((current) =>
      current.includes(session.visitId)
        ? current
        : [...current, session.visitId]
    )

    fetchProfileSession(profile.id, session.visitId, query, controller.signal)
      .then((value) => {
        setSessionPayloads((current) => ({
          ...current,
          [session.visitId]: value,
        }))
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        setSessionLoadingIds((current) =>
          current.filter((id) => id !== session.visitId)
        )
      })
  }

  const activityDataset = useMemo(() => {
    const fromApi = data?.activity
    if (fromApi?.length && fromApi.some((a) => a.count > 0)) return fromApi

    return orderedSessions.map((session) => ({
      startedAt: session.startedAt,
      count: session.eventsCount,
    }))
  }, [data, orderedSessions])

  const insightGroups = {
    devices: resolvedProfile?.devicesUsed || [],
    browsers: resolvedProfile?.browsersUsed || [],
    oses: resolvedProfile?.osesUsed || [],
    sources: resolvedProfile?.sourcesUsed || [],
    locations: resolvedProfile?.locationsUsed || [],
    topPages: resolvedProfile?.topPages || [],
  }
  const hasProfileLocation = Boolean(
    resolvedProfile?.city || resolvedProfile?.region || resolvedProfile?.country
  )
  const selectedActivityDayLabel = selectedActivityDay
    ? formatCalendarDay(selectedActivityDay.date)
    : null

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="inset-0 max-h-none max-w-none translate-x-0 translate-y-0 rounded-none p-0 sm:inset-auto sm:top-1/2 sm:left-1/2 sm:max-h-[88vh] sm:max-w-7xl sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-xl"
        showCloseButton
      >
        <div className="sr-only">
          <DialogTitle>{resolvedProfile?.name || "Visitor"}</DialogTitle>
          <DialogDescription>
            Visitor profile and session details
          </DialogDescription>
        </div>

        {loading && !data ? (
          <div className="flex h-64 items-center justify-center">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="h-dvh overflow-y-auto sm:h-[84vh] lg:grid lg:h-[84vh] lg:max-h-[84vh] lg:grid-cols-[260px_minmax(0,1fr)_320px] lg:overflow-hidden">
            <aside className="border-b border-border px-4 py-5 lg:overflow-y-auto lg:border-r lg:border-b-0">
              <div className="flex flex-col items-center text-center">
                <VisitorAvatar name={resolvedProfile?.name || "?"} size={72} />
                <div className="mt-3 flex items-center gap-1.5">
                  <h2 className="text-base font-semibold text-foreground">
                    {resolvedProfile?.name || "Visitor"}
                  </h2>
                  {resolvedProfile?.identified ? (
                    <span className="inline-flex rounded-full border border-emerald-200 bg-emerald-50 px-1.5 py-px text-xs font-medium text-emerald-700">
                      User
                    </span>
                  ) : null}
                </div>
                <p className="mt-1.5 text-xs text-muted-foreground">
                  {resolvedProfile?.identified && resolvedProfile?.email
                    ? resolvedProfile.email
                    : maskEmail(resolvedProfile?.email || "")}
                </p>
              </div>

              <div className="mt-5 grid grid-cols-2 gap-2">
                {[
                  {
                    label: "Visits",
                    value: formatCompactNumber(resolvedProfile?.totalVisits),
                  },
                  {
                    label: "Sessions",
                    value: formatCompactNumber(resolvedProfile?.totalSessions),
                  },
                  {
                    label: "Pageviews",
                    value: formatCompactNumber(resolvedProfile?.totalPageviews),
                  },
                  {
                    label: "Events",
                    value: formatCompactNumber(resolvedProfile?.totalEvents),
                  },
                ].map((item) => (
                  <div
                    key={item.label}
                    className="rounded-lg border border-border bg-muted/20 px-3 py-2.5"
                  >
                    <p className="text-xs text-muted-foreground">
                      {item.label}
                    </p>
                    <p className="mt-1 text-lg font-semibold text-foreground">
                      {item.value}
                    </p>
                  </div>
                ))}
              </div>

              <section className="mt-4 rounded-lg border border-border bg-muted/20 px-3.5 py-3.5">
                <h3 className="text-xs font-semibold tracking-[0.12em] text-muted-foreground uppercase">
                  Profile summary
                </h3>
                <div className="mt-3 space-y-2 text-xs">
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">Status</span>
                    <span className="font-medium text-foreground capitalize">
                      {resolvedProfile?.status || "—"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">First seen</span>
                    <span className="text-right font-medium text-foreground">
                      {resolvedProfile?.firstSeenAt
                        ? formatDateTime(resolvedProfile.firstSeenAt)
                        : "—"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">Last seen</span>
                    <span className="text-right font-medium text-foreground">
                      {resolvedProfile?.lastSeenAt
                        ? formatDateTime(resolvedProfile.lastSeenAt)
                        : "—"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">Latest source</span>
                    <span className="max-w-[12rem] truncate text-right font-medium text-foreground">
                      {resolvedProfile?.source || "Direct/None"}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">Latest page</span>
                    {resolvedProfile?.currentPage ? (
                      <a
                        href={resolvedProfile.currentPage}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="max-w-[12rem] truncate text-right font-medium text-foreground underline decoration-muted-foreground/30 underline-offset-2 hover:decoration-foreground"
                      >
                        {resolvedProfile.currentPage}
                      </a>
                    ) : (
                      <span className="font-medium text-foreground">—</span>
                    )}
                  </div>
                  {hasProfileLocation ? (
                    <div className="flex justify-between gap-3">
                      <span className="text-muted-foreground">
                        Latest location
                      </span>
                      <span className="max-w-[12rem] text-right font-medium text-foreground">
                        <ProfileLocationText
                          city={resolvedProfile?.city}
                          region={resolvedProfile?.region}
                          country={resolvedProfile?.country}
                          countryCode={resolvedProfile?.countryCode}
                        />
                      </span>
                    </div>
                  ) : null}
                </div>
              </section>
            </aside>

            <section className="border-b border-border lg:flex lg:min-h-0 lg:flex-col lg:overflow-hidden lg:border-b-0">
              <div className="flex items-center justify-between border-b border-border px-5 py-3">
                <div className="space-y-1.5">
                  <h3 className="text-sm font-medium text-foreground">
                    Session journey
                  </h3>
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.sessions ?? 0} sessions
                    </span>
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.pageviews ?? 0} pageviews
                    </span>
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.events ?? 0} events
                    </span>
                    {selectedActivityDayLabel ? (
                      <>
                        <span className="rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-blue-700">
                          Showing {selectedActivityDayLabel}
                        </span>
                        <button
                          type="button"
                          onClick={() => setSelectedActivityDay(null)}
                          className="rounded-full border border-border px-2 py-0.5 text-muted-foreground transition-colors hover:text-foreground"
                        >
                          Clear
                        </button>
                      </>
                    ) : null}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setSortOldest((value) => !value)}
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-card px-2.5 py-1 text-xs font-medium text-muted-foreground hover:text-foreground"
                >
                  {sortOldest ? "OLDEST FIRST" : "NEWEST FIRST"}
                </button>
              </div>

              <div className="px-4 py-4 lg:flex-1 lg:overflow-y-auto">
                {sessionsLoading && orderedSessions.length === 0 ? (
                  <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                    <Loader2 className="mr-2 size-3.5 animate-spin" />
                    Loading sessions...
                  </div>
                ) : orderedSessions.length > 0 ? (
                  <div className="space-y-2.5">
                    {orderedSessions.map((session) => {
                      const sessionPayload = sessionPayloads[session.visitId]
                      const isOpen = expandedSessionIds.includes(
                        session.visitId
                      )
                      const isSessionLoading = sessionLoadingIds.includes(
                        session.visitId
                      )

                      return (
                        <article
                          key={session.visitId}
                          className="rounded-xl border border-border bg-card"
                        >
                          <button
                            type="button"
                            className="flex w-full items-start justify-between gap-3 px-4 py-3.5 text-left"
                            onClick={() => loadSession(session)}
                          >
                            <div className="min-w-0 flex-1 space-y-2.5">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="rounded-full bg-muted/60 px-2.5 py-0.5 text-xs font-medium text-foreground">
                                  {session.startedAt
                                    ? formatDateTime(session.startedAt)
                                    : "Unknown session"}
                                </span>
                                {session.source ? (
                                  <span className="rounded-full border border-border px-2.5 py-0.5 text-xs text-muted-foreground">
                                    <ProfileSourceInline
                                      source={session.source}
                                      iconClassName="size-3.5"
                                    />
                                  </span>
                                ) : null}
                              </div>

                              <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 text-xs text-muted-foreground">
                                <ProfileDeviceInline
                                  deviceType={session.deviceType}
                                  label={session.deviceType}
                                  textClassName="capitalize"
                                />
                                <ProfileOSInline os={session.os} />
                                <ProfileBrowserInline
                                  browser={session.browser}
                                />
                                {session.country ||
                                session.countryCode ||
                                session.region ||
                                session.city ? (
                                  <span className="inline-flex items-center gap-1.5">
                                    <ProfileLocationText
                                      city={session.city}
                                      region={session.region}
                                      country={session.country}
                                      countryCode={session.countryCode}
                                    />
                                  </span>
                                ) : null}
                              </div>

                              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                                <span>
                                  <span className="text-xs tracking-[0.12em] uppercase">
                                    Duration
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {formatProfileDuration(
                                      session.durationSeconds
                                    )}
                                  </span>
                                </span>
                                <span>
                                  <span className="text-xs tracking-[0.12em] uppercase">
                                    Pageviews
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {session.pageviewsCount}
                                  </span>
                                </span>
                                <span>
                                  <span className="text-xs tracking-[0.12em] uppercase">
                                    Events
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {session.eventsCount}
                                  </span>
                                </span>
                              </div>

                              <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
                                <span className="inline-flex items-center gap-1">
                                  <Route className="size-3" />
                                  <span>
                                    {session.entryPage || "—"} {"->"}{" "}
                                    {session.exitPage ||
                                      session.currentPage ||
                                      "—"}
                                  </span>
                                </span>
                                {session.lastEventAt ? (
                                  <span className="inline-flex items-center gap-1">
                                    <Clock3 className="size-3" />
                                    <span>
                                      Active{" "}
                                      {formatDateTime(session.lastEventAt)}
                                    </span>
                                  </span>
                                ) : null}
                              </div>
                            </div>

                            <div className="inline-flex shrink-0 items-center gap-1 rounded-full border border-border bg-muted/20 px-2.5 py-1 text-xs font-medium text-muted-foreground">
                              <span>
                                {isOpen ? "Hide events" : "Show events"}
                              </span>
                              {isOpen ? (
                                <ChevronUp className="size-3.5" />
                              ) : (
                                <ChevronDown className="size-3.5" />
                              )}
                            </div>
                          </button>

                          {isOpen ? (
                            <div className="border-t border-border px-4 py-3">
                              {isSessionLoading && !sessionPayload ? (
                                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                                  <Loader2 className="size-3.5 animate-spin" />
                                  Loading session events...
                                </div>
                              ) : sessionPayload?.events?.length ? (
                                <div className="flex flex-col gap-2">
                                  <SessionSourceSummary
                                    sourceSummary={sessionPayload.sourceSummary}
                                  />
                                  {sessionPayload.events.map((item) => {
                                    const kind = classifyEvent(item)
                                    const isPayment = kind === "payment"

                                    return (
                                      <div
                                        key={item.id}
                                        className={`flex items-start gap-2.5 rounded-lg px-2.5 py-1.5 ${
                                          isPayment
                                            ? "bg-emerald-50/60"
                                            : "bg-muted/20"
                                        }`}
                                      >
                                        <div className="mt-px">
                                          <EventIcon kind={kind} />
                                        </div>
                                        <div className="min-w-0 flex-1">
                                          <EventLabel
                                            label={item.label}
                                            page={item.page}
                                            className={`text-xs ${
                                              isPayment
                                                ? "font-medium text-emerald-700"
                                                : "text-foreground"
                                            }`}
                                          />
                                          {shouldShowSecondaryPageLine(
                                            item.label,
                                            item.page
                                          ) ? (
                                            <p className="mt-0.5 text-xs text-muted-foreground">
                                              <a
                                                href={item.page!}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="underline decoration-muted-foreground/40 underline-offset-2 hover:decoration-foreground"
                                                onClick={(e) =>
                                                  e.stopPropagation()
                                                }
                                              >
                                                {item.page}
                                              </a>
                                            </p>
                                          ) : null}
                                        </div>
                                        <time className="shrink-0 text-xs text-muted-foreground">
                                          {new Intl.DateTimeFormat("en-US", {
                                            hour: "numeric",
                                            minute: "2-digit",
                                          }).format(new Date(item.occurredAt))}
                                        </time>
                                      </div>
                                    )
                                  })}
                                </div>
                              ) : (
                                <p className="text-xs text-muted-foreground">
                                  No events for this session in the current
                                  filter scope.
                                </p>
                              )}
                            </div>
                          ) : null}
                        </article>
                      )
                    })}

                    {sessionsHasMore ? (
                      <button
                        type="button"
                        onClick={loadMoreSessions}
                        disabled={sessionsLoading}
                        className="flex w-full items-center justify-center gap-2 rounded-lg border border-border py-2 text-xs font-medium text-muted-foreground hover:bg-muted/30 hover:text-foreground disabled:opacity-50"
                      >
                        {sessionsLoading ? (
                          <>
                            <Loader2 className="size-3.5 animate-spin" />
                            Loading...
                          </>
                        ) : (
                          "Show more sessions"
                        )}
                      </button>
                    ) : null}
                  </div>
                ) : selectedActivityDay ? (
                  <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                    No sessions on {selectedActivityDayLabel}.
                  </div>
                ) : (
                  <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                    No sessions for this visitor.
                  </div>
                )}
              </div>
            </section>

            <aside className="border-t border-border px-4 py-5 lg:overflow-y-auto lg:border-t-0 lg:border-l">
              <div className="space-y-4">
                <section className="space-y-1.5">
                  <h3 className="flex items-center gap-1.5 text-xs font-semibold tracking-[0.12em] text-muted-foreground uppercase">
                    <Activity className="size-3" />
                    Activity
                  </h3>
                  <ActivityHeatmap
                    sessionEvents={activityDataset}
                    selectedDay={selectedActivityDay}
                    onSelectDay={setSelectedActivityDay}
                  />
                </section>

                <SectionChips
                  title="Devices used"
                  icon={Smartphone}
                  items={insightGroups.devices}
                  empty="No device history yet"
                  renderItemIcon={(label) => (
                    <DeviceTypeIcon
                      type={label.toLowerCase()}
                      className="size-3.5"
                    />
                  )}
                />
                <SectionChips
                  title="Browsers used"
                  icon={Globe}
                  items={insightGroups.browsers}
                  empty="No browser history yet"
                  renderItemIcon={(label) => (
                    <img
                      alt=""
                      src={`/images/icon/browser/${getBrowserIcon(label)}`}
                      className="size-3.5 shrink-0 object-contain"
                    />
                  )}
                />
                <SectionChips
                  title="Operating systems"
                  icon={Cpu}
                  items={insightGroups.oses}
                  empty="No OS history yet"
                  renderItemIcon={(label) => (
                    <img
                      alt=""
                      src={`/images/icon/os/${getOSIcon(label)}`}
                      className="size-3.5 shrink-0 object-contain"
                    />
                  )}
                />
                <SectionChips
                  title="Sources used"
                  icon={Share2}
                  items={insightGroups.sources}
                  empty="No source history yet"
                  renderItemIcon={(label) => {
                    const domain = getSourceFaviconDomain(label)
                    return domain ? (
                      <img
                        alt=""
                        src={`/favicon/sources/${domain}`}
                        className="size-3.5 shrink-0 object-contain"
                      />
                    ) : null
                  }}
                />
                <LocationList items={insightGroups.locations} />
                <TopPagesList items={insightGroups.topPages} />
              </div>
            </aside>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
