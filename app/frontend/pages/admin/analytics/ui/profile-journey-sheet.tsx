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
  MapPin,
  Route,
  Share2,
  Smartphone,
  Zap,
} from "lucide-react"

import { formatDateTime } from "@/lib/format-date"
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
  formatProfileLocation,
  maskEmail,
} from "./profile/formatters"
import {
  ProfileBrowserInline,
  ProfileDeviceInline,
  ProfileLocationText,
  ProfileOSInline,
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
  const [expandedSessionId, setExpandedSessionId] = useState<number | null>(
    null
  )
  const [sessionPayloads, setSessionPayloads] = useState<
    Record<number, ProfileSessionPayload>
  >({})
  const [sessionLoadingId, setSessionLoadingId] = useState<number | null>(null)

  const PAGE_SIZE = 20
  const [sessions, setSessions] = useState<ProfileSessionItem[]>([])
  const [sessionsPage, setSessionsPage] = useState(1)
  const [sessionsHasMore, setSessionsHasMore] = useState(false)
  const [sessionsLoading, setSessionsLoading] = useState(false)
  const requestIdRef = useRef(0)

  useEffect(() => {
    if (!open || !profile) return

    const controller = new AbortController()
    const nextRequestId = requestIdRef.current + 1
    requestIdRef.current = nextRequestId
    startTransition(() => {
      setLoading(true)
      setExpandedSessionId(null)
      setSessionPayloads({})
      setSessions([])
      setSessionsPage(1)
      setSessionsHasMore(false)
    })

    Promise.all([
      fetchProfileJourney(profile.id, query, controller.signal),
      fetchProfileSessions(
        profile.id,
        { limit: PAGE_SIZE, page: 1 },
        controller.signal
      ),
    ])
      .then(([journeyData, sessionsData]) => {
        if (requestIdRef.current !== nextRequestId) return
        setData(journeyData)
        setSessions(sessionsData.sessions)
        setSessionsHasMore(sessionsData.hasMore)
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

  const loadMoreSessions = () => {
    if (!profile || sessionsLoading || !sessionsHasMore) return

    const nextPage = sessionsPage + 1
    setSessionsLoading(true)

    fetchProfileSessions(profile.id, { limit: PAGE_SIZE, page: nextPage })
      .then((result) => {
        setSessions((prev) => [...prev, ...result.sessions])
        setSessionsHasMore(result.hasMore)
        setSessionsPage(nextPage)
      })
      .catch((error: Error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => setSessionsLoading(false))
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
    if (sessionPayloads[session.visitId]) {
      setExpandedSessionId((current) =>
        current === session.visitId ? null : session.visitId
      )
      return
    }

    const controller = new AbortController()
    setExpandedSessionId(session.visitId)
    setSessionLoadingId(session.visitId)

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
      .finally(() =>
        setSessionLoadingId((current) =>
          current === session.visitId ? null : current
        )
      )
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
  const profileLocation = useMemo(() => {
    return formatProfileLocation({
      city: resolvedProfile?.city,
      region: resolvedProfile?.region,
      country: resolvedProfile?.country,
    })
  }, [resolvedProfile])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="max-h-[88vh] w-full overflow-hidden p-0 sm:max-w-7xl"
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
          <div className="grid h-[84vh] max-h-[84vh] grid-cols-1 lg:grid-cols-[260px_minmax(0,1fr)_320px]">
            <aside className="overflow-y-auto border-b border-border px-4 py-5 lg:border-r lg:border-b-0">
              <div className="flex flex-col items-center text-center">
                <VisitorAvatar name={resolvedProfile?.name || "?"} size={72} />
                <div className="mt-2.5 flex items-center gap-1.5">
                  <h2 className="text-base font-semibold text-foreground">
                    {resolvedProfile?.name || "Visitor"}
                  </h2>
                  {resolvedProfile?.identified ? (
                    <span className="inline-flex rounded-full border border-emerald-200 bg-emerald-50 px-1.5 py-px text-[10px] font-medium text-emerald-700">
                      User
                    </span>
                  ) : null}
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {resolvedProfile?.identified && resolvedProfile?.email
                    ? resolvedProfile.email
                    : maskEmail(resolvedProfile?.email || "")}
                </p>
              </div>

              <div className="mt-5 grid grid-cols-2 gap-1.5">
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
                    className="rounded-lg border border-border bg-muted/20 px-2.5 py-2"
                  >
                    <p className="text-[10px] text-muted-foreground">
                      {item.label}
                    </p>
                    <p className="mt-0.5 text-base font-semibold text-foreground">
                      {item.value}
                    </p>
                  </div>
                ))}
              </div>

              <section className="mt-4 rounded-lg border border-border bg-muted/20 px-3 py-3">
                <h3 className="text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
                  Profile summary
                </h3>
                <div className="mt-2 space-y-1.5 text-[11px]">
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
                    <span className="truncate text-right font-medium text-foreground">
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
                        className="truncate text-right font-medium text-foreground underline decoration-muted-foreground/30 underline-offset-2 hover:decoration-foreground"
                      >
                        {resolvedProfile.currentPage}
                      </a>
                    ) : (
                      <span className="font-medium text-foreground">—</span>
                    )}
                  </div>
                  {profileLocation ? (
                    <div className="flex justify-between gap-3">
                      <span className="text-muted-foreground">
                        Latest location
                      </span>
                      <span className="truncate text-right font-medium text-foreground">
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

            <section className="flex min-h-0 flex-col overflow-hidden border-b border-border lg:border-b-0">
              <div className="flex items-center justify-between border-b border-border px-5 py-3">
                <div className="space-y-1.5">
                  <h3 className="text-sm font-medium text-foreground">
                    Session journey
                  </h3>
                  <div className="flex flex-wrap items-center gap-1.5 text-[11px]">
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.sessions ?? 0} sessions
                    </span>
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.pageviews ?? 0} pageviews
                    </span>
                    <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-muted-foreground">
                      {data?.summary.events ?? 0} events
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setSortOldest((value) => !value)}
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-card px-2.5 py-1 text-[11px] font-medium text-muted-foreground hover:text-foreground"
                >
                  {sortOldest ? "OLDEST FIRST" : "NEWEST FIRST"}
                </button>
              </div>

              <div className="flex-1 overflow-y-auto px-4 py-4">
                {orderedSessions.length > 0 ? (
                  <div className="space-y-2.5">
                    {orderedSessions.map((session) => {
                      const sessionPayload = sessionPayloads[session.visitId]
                      const isOpen = expandedSessionId === session.visitId

                      return (
                        <article
                          key={session.visitId}
                          className="rounded-xl border border-border bg-card"
                        >
                          <button
                            type="button"
                            className="flex w-full items-start justify-between gap-3 px-4 py-3 text-left"
                            onClick={() => loadSession(session)}
                          >
                            <div className="min-w-0 flex-1 space-y-2">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="rounded-full bg-muted/60 px-2.5 py-0.5 text-[11px] font-medium text-foreground">
                                  {session.startedAt
                                    ? formatDateTime(session.startedAt)
                                    : "Unknown session"}
                                </span>
                                {session.source ? (
                                  <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] text-muted-foreground">
                                    {session.source}
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
                                session.region ||
                                session.city ? (
                                  <span className="inline-flex items-center gap-1.5">
                                    <MapPin className="size-3.5" />
                                    <ProfileLocationText
                                      city={session.city}
                                      region={session.region}
                                      country={session.country}
                                      countryCode={session.countryCode}
                                      order="country-first"
                                    />
                                  </span>
                                ) : null}
                              </div>

                              <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
                                <span>
                                  <span className="text-[10px] tracking-wide uppercase">
                                    Duration
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {formatProfileDuration(
                                      session.durationSeconds
                                    )}
                                  </span>
                                </span>
                                <span>
                                  <span className="text-[10px] tracking-wide uppercase">
                                    Pageviews
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {session.pageviewsCount}
                                  </span>
                                </span>
                                <span>
                                  <span className="text-[10px] tracking-wide uppercase">
                                    Events
                                  </span>{" "}
                                  <span className="font-medium text-foreground">
                                    {session.eventsCount}
                                  </span>
                                </span>
                              </div>

                              <div className="flex flex-wrap items-center gap-3 text-[11px] text-muted-foreground">
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

                            <div className="inline-flex shrink-0 items-center gap-1 rounded-full border border-border bg-muted/20 px-2.5 py-1 text-[11px] font-medium text-muted-foreground">
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
                              {sessionLoadingId === session.visitId &&
                              !sessionPayload ? (
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
                ) : (
                  <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                    No sessions for this visitor.
                  </div>
                )}
              </div>
            </section>

            <aside className="overflow-y-auto border-t border-border px-4 py-5 lg:border-t-0 lg:border-l">
              <div className="space-y-4">
                <section className="space-y-1.5">
                  <h3 className="flex items-center gap-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
                    <Activity className="size-3" />
                    Activity
                  </h3>
                  <ActivityHeatmap sessionEvents={activityDataset} />
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
