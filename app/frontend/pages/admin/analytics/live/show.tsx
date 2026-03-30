import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Head } from "@inertiajs/react"
import { latLngToCell } from "h3-js"
import {
  Eye,
  EyeOff,
  Loader2,
  Maximize2,
  Minimize2,
  Minus,
  Plus,
  Search,
  X,
} from "lucide-react"

import { useClientComponent } from "@/hooks/use-client-component"
import { useHydrated } from "@/hooks/use-hydrated"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import type { HexHighlightSelection } from "@/components/analytics/hex-highlights"
import { MetricCard } from "@/components/analytics/metric-card"
import { SessionsByLocation } from "@/components/analytics/sessions-by-location"
import type {
  VisitorGlobeHandle,
  VisitorGlobeZoomState,
} from "@/components/analytics/visitor-globe"
import AdminLayout from "@/layouts/admin-layout"

import { useLiveLocationSearch } from "./hooks/use-live-location-search"
import { useLiveStats } from "./hooks/use-live-stats"
import { buildLiveGlobeDots, resolveLiveGlobeLabel } from "./lib/globe-dots"
import { getSessionCardAnchorStyle } from "./lib/live-utils"
import type { LiveEvent, LiveSession, LiveStats } from "./types"
import { EMPTY_STATS } from "./types"
import LiveEventsPanel from "./ui/live-events-panel"
import LiveSessionCard from "./ui/live-session-card"

const loadVisitorGlobeComponent = () =>
  import("@/components/analytics/visitor-globe").then(
    ({ VisitorGlobe: component }) => component
  )

const VISITOR_GLOBE_MIN_DISTANCE = 1.8
const VISITOR_GLOBE_MAX_DISTANCE = 3.2

const DESKTOP_CARD_WIDTH = 520
const DESKTOP_GAP = 24
const DESKTOP_PADDING = 24
const DESKTOP_HEADER_SPACING = 40
const DESKTOP_BOTTOM_PADDING = 16
const DESKTOP_ACTIVITY_PANEL_RESERVED = 120
const SEARCH_RESULTS_PANEL_CLASSNAME =
  "absolute z-20 mt-2 overflow-hidden rounded-lg border border-border/70 bg-card/95 text-sm shadow-lg backdrop-blur-md"
const FLOATING_CONTROL_CLASSNAME =
  "border border-border/70 bg-card/80 text-foreground shadow-xs backdrop-blur-xs"

export default function LiveAnalytics({
  initialStats,
  liveSubscriptionToken,
}: {
  initialStats?: LiveStats
  liveSubscriptionToken?: string | null
}) {
  const hydrated = useHydrated()
  const resolvedInitialStats = initialStats ?? EMPTY_STATS
  const { stats, connectionStatus } = useLiveStats(
    resolvedInitialStats,
    liveSubscriptionToken
  )
  const { Component: VisitorGlobeComponent } = useClientComponent(
    loadVisitorGlobeComponent,
    { preload: true }
  )
  const mobileGlobeRef = useRef<VisitorGlobeHandle>(null)
  const desktopGlobeRef = useRef<VisitorGlobeHandle>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [globeZoomState, setGlobeZoomState] = useState<VisitorGlobeZoomState>({
    distance: VISITOR_GLOBE_MAX_DISTANCE,
    minDistance: VISITOR_GLOBE_MIN_DISTANCE,
    maxDistance: VISITOR_GLOBE_MAX_DISTANCE,
  })
  const [areCardsVisible, setAreCardsVisible] = useState(true)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const {
    query,
    setQuery,
    setSuggestions,
    desktopFocused,
    setDesktopFocused,
    activeIndex,
    setActiveIndex,
    setView,
    isSearchVisible,
    setIsSearchVisible,
    showSearchHint,
    visibleSuggestions,
    isSearchPending,
  } = useLiveLocationSearch(VISITOR_GLOBE_MAX_DISTANCE)
  const [selectedCellId, setSelectedCellId] = useState<string | null>(null)
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(
    null
  )
  const [mobileSessionAnchor, setMobileSessionAnchor] =
    useState<HexHighlightSelection | null>(null)
  const [desktopSessionAnchor, setDesktopSessionAnchor] =
    useState<HexHighlightSelection | null>(null)
  const selectionRequestRef = useRef(0)

  const liveClusters = useMemo(
    () =>
      stats.liveSessions.reduce<
        Array<{ cellId: string; sessions: LiveSession[] }>
      >((clusters, session) => {
        if (session.lat == null || session.lng == null) return clusters

        try {
          const cellId = latLngToCell(session.lat, session.lng, 3)
          const existing = clusters.find((cluster) => cluster.cellId === cellId)
          if (existing) {
            existing.sessions.push(session)
          } else {
            clusters.push({ cellId, sessions: [session] })
          }
        } catch {
          // Ignore invalid coordinates in the live selector map.
        }

        return clusters
      }, []),
    [stats.liveSessions]
  )

  const selectedCluster = useMemo(
    () =>
      liveClusters.find((cluster) => cluster.cellId === selectedCellId) ?? null,
    [liveClusters, selectedCellId]
  )
  const selectedActiveSession = useMemo(
    () =>
      stats.liveSessions.find((session) => session.id === selectedSessionId) ??
      selectedCluster?.sessions[0] ??
      null,
    [selectedCluster, selectedSessionId, stats.liveSessions]
  )
  const selectedEventSession = useMemo(
    () =>
      !selectedActiveSession && selectedSessionId
        ? (stats.recentEvents.find(
            (event) => event.sessionId === selectedSessionId
          ) ?? null)
        : null,
    [selectedActiveSession, selectedSessionId, stats.recentEvents]
  )
  const selectedSession = useMemo(
    () =>
      selectedActiveSession ??
      (selectedEventSession
        ? {
            ...selectedEventSession,
            id: selectedEventSession.sessionId,
            recentEvents: stats.recentEvents.filter(
              (event) => event.sessionId === selectedEventSession.sessionId
            ),
          }
        : null),
    [selectedActiveSession, selectedEventSession, stats.recentEvents]
  )
  const hasLiveVisitors = stats.currentVisitors > 0
  const visibleEvents = selectedSessionId
    ? stats.recentEvents.filter(
        (event) => event.sessionId === selectedSessionId
      )
    : stats.recentEvents
  const activityPanelTitle = selectedSession
    ? `${selectedSession.name}`
    : "Recent live activity"
  const activityEmptyMessage = selectedSession
    ? "No recent activity for this session"
    : hasLiveVisitors
      ? "Waiting for activity..."
      : "No recent activity yet"
  const globeDots = buildLiveGlobeDots(stats.liveSessions, stats.visitorDots)
  const showMobileAnchoredSessionCard =
    !!selectedSession &&
    !!selectedCellId &&
    mobileSessionAnchor?.cellId === selectedCellId
  const showDesktopAnchoredSessionCard =
    !!selectedSession &&
    !!selectedCellId &&
    desktopSessionAnchor?.cellId === selectedCellId
  const prefersAnchoredSessionCard =
    !!selectedSession &&
    !!selectedCellId &&
    selectedSession.lat != null &&
    selectedSession.lng != null

  const clearSessionAnchors = useCallback(() => {
    setMobileSessionAnchor(null)
    setDesktopSessionAnchor(null)
  }, [])

  const handleViewChange = useCallback(
    (nextView: { lat: number; lng: number; distance: number }) => {
      setView(nextView)
      clearSessionAnchors()
    },
    [clearSessionAnchors, setView]
  )

  const selectSession = useCallback((sessionId: string | null) => {
    setSelectedSessionId(sessionId)
  }, [])

  const closeSelectedSession = useCallback(() => {
    selectionRequestRef.current += 1
    setSelectedCellId(null)
    setSelectedSessionId(null)
    clearSessionAnchors()
  }, [clearSessionAnchors])

  const focusSessionFromActivity = useCallback(
    async ({
      sessionId,
      lat,
      lng,
      label,
      globeRef,
      setAnchor,
    }: {
      sessionId: string
      lat?: number | null
      lng?: number | null
      label?: string | null
      globeRef: { current: VisitorGlobeHandle | null }
      setAnchor: (anchor: HexHighlightSelection | null) => void
    }) => {
      selectionRequestRef.current += 1
      const requestId = selectionRequestRef.current

      setSelectedSessionId(sessionId)
      clearSessionAnchors()

      if (lat == null || lng == null) {
        setSelectedCellId(null)
        return
      }

      let cellId: string
      try {
        cellId = latLngToCell(lat, lng, 3)
      } catch {
        setSelectedCellId(null)
        return
      }

      setSelectedCellId(cellId)

      const globe = globeRef.current
      if (!globe) return

      await globe.flyTo(lat, lng)

      if (selectionRequestRef.current !== requestId) return

      const anchor = globe.getSelectionAnchor(lat, lng, label ?? "Unknown")
      if (anchor) {
        setAnchor(anchor)
      } else {
        setSelectedCellId(null)
      }
    },
    [clearSessionAnchors]
  )

  const handleMobileActivitySelection = useCallback(
    (event: LiveEvent) =>
      void focusSessionFromActivity({
        sessionId: event.sessionId,
        lat: event.lat,
        lng: event.lng,
        label: resolveLiveGlobeLabel(event),
        globeRef: mobileGlobeRef,
        setAnchor: setMobileSessionAnchor,
      }),
    [focusSessionFromActivity]
  )

  const handleDesktopActivitySelection = useCallback(
    (event: LiveEvent) =>
      void focusSessionFromActivity({
        sessionId: event.sessionId,
        lat: event.lat,
        lng: event.lng,
        label: resolveLiveGlobeLabel(event),
        globeRef: desktopGlobeRef,
        setAnchor: setDesktopSessionAnchor,
      }),
    [focusSessionFromActivity]
  )

  const handleCellSelection = useCallback(
    (
      selection: HexHighlightSelection | null,
      setAnchor: (anchor: HexHighlightSelection | null) => void
    ) => {
      if (!selection) {
        setSelectedCellId(null)
        setSelectedSessionId(null)
        setAnchor(null)
        return
      }

      setAnchor(selection)
      setSelectedCellId(selection.cellId)
      const cluster = liveClusters.find(
        (item) => item.cellId === selection.cellId
      )
      setSelectedSessionId(cluster?.sessions[0]?.id ?? null)
    },
    [liveClusters]
  )

  const handleMobileCellSelection = useCallback(
    (selection: HexHighlightSelection | null) =>
      handleCellSelection(selection, setMobileSessionAnchor),
    [handleCellSelection]
  )

  const handleDesktopCellSelection = useCallback(
    (selection: HexHighlightSelection | null) =>
      handleCellSelection(selection, setDesktopSessionAnchor),
    [handleCellSelection]
  )

  const focusMobileGlobe = (lat: number, lng: number) => {
    mobileGlobeRef.current?.flyTo(lat, lng)
  }

  const focusDesktopGlobe = (lat: number, lng: number) => {
    desktopGlobeRef.current?.flyTo(lat, lng)
  }

  const zoomAtClosest =
    globeZoomState.distance <= globeZoomState.minDistance + 0.05
  const zoomAtFarthest =
    globeZoomState.distance >= globeZoomState.maxDistance - 0.05

  const handleZoomIn = () => {
    if (zoomAtClosest) return
    desktopGlobeRef.current?.zoomIn()
  }

  const handleZoomOut = () => {
    if (zoomAtFarthest) return
    desktopGlobeRef.current?.zoomOut()
  }
  const toggleCardsVisibility = () => {
    setAreCardsVisible((visible) => !visible)
  }
  const toggleSearchVisibility = () => {
    setIsSearchVisible((visible) => !visible)
    setSuggestions([])
  }
  const toggleFullscreen = async () => {
    if (!containerRef.current) return

    if (!document.fullscreenElement) {
      try {
        await containerRef.current.requestFullscreen()
      } catch (err) {
        console.error("Failed to enter fullscreen:", err)
      }
    } else {
      try {
        await document.exitFullscreen()
      } catch (err) {
        console.error("Failed to exit fullscreen:", err)
      }
    }
  }

  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement)
    }

    document.addEventListener("fullscreenchange", handleFullscreenChange)
    return () => {
      document.removeEventListener("fullscreenchange", handleFullscreenChange)
    }
  }, [])

  useEffect(() => {
    if (!selectedSession && !selectedCellId) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return
      closeSelectedSession()
    }

    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [closeSelectedSession, selectedCellId, selectedSession])
  const cardsTranslateX = areCardsVisible
    ? 0
    : -(DESKTOP_CARD_WIDTH + DESKTOP_GAP)
  const globeTranslateX = areCardsVisible
    ? (DESKTOP_CARD_WIDTH + DESKTOP_GAP) / 2
    : 0
  const formattedTimestamp = hydrated
    ? new Date().toLocaleString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        timeZoneName: "short",
      })
    : ""

  return (
    <AdminLayout>
      <Head title="Live View - Analytics" />

      <div className="-m-4 flex h-[calc(100%+2rem)] flex-1 flex-col overflow-hidden md:-m-6 md:h-[calc(100%+3rem)]">
        <div className="flex flex-1 flex-col overflow-hidden lg:overflow-visible">
          {/* Mobile Layout */}
          <div className="flex-1 overflow-auto px-4 pt-2 pb-4 lg:hidden">
            <div className="flex flex-col gap-4">
              {/* Legend and Search */}
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4 text-sm">
                    <div className="flex items-center gap-2">
                      <div className="size-3 rounded-full bg-blue-600 shadow-[0_0_8px_oklch(0.546_0.245_262/0.55)] dark:bg-blue-500" />
                      <span className="text-sm/5 text-foreground">
                        Visitors right now
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-10"
                      onClick={toggleSearchVisibility}
                      aria-pressed={isSearchVisible}
                    >
                      <Search className="size-4" />
                      <span className="sr-only">
                        {isSearchVisible ? "Hide search" : "Show search"}
                      </span>
                    </Button>
                  </div>
                </div>
                {isSearchVisible && (
                  <div className="relative">
                    <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                    <Input
                      placeholder="Search location"
                      className="pl-9"
                      autoFocus
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                    />
                    {(showSearchHint ||
                      isSearchPending ||
                      visibleSuggestions.length > 0) && (
                      <div
                        className={`${SEARCH_RESULTS_PANEL_CLASSNAME} w-full`}
                      >
                        {showSearchHint ? (
                          <div className="px-3 py-2 text-sm/5 text-muted-foreground">
                            Type one more character…
                          </div>
                        ) : isSearchPending &&
                          visibleSuggestions.length === 0 ? (
                          <div className="flex items-center gap-2 px-3 py-2 text-sm/5 text-muted-foreground">
                            <Loader2 className="size-4 animate-spin" />{" "}
                            Searching…
                          </div>
                        ) : (
                          visibleSuggestions.map((s, i) => (
                            <button
                              key={`${s.name}-${i}`}
                              className="w-full truncate px-3 py-2 text-left text-sm/5 transition hover:bg-accent/70"
                              onClick={() => {
                                setSuggestions([])
                                setIsSearchVisible(false)
                                focusMobileGlobe(s.lat, s.lng)
                              }}
                            >
                              {s.name}
                            </button>
                          ))
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>

              {/* Globe */}
              <div className="relative aspect-square w-full">
                {VisitorGlobeComponent ? (
                  <VisitorGlobeComponent
                    ref={mobileGlobeRef}
                    visitors={globeDots}
                    onViewChange={handleViewChange}
                    onSelectCell={handleMobileCellSelection}
                  />
                ) : (
                  <VisitorGlobeFallback />
                )}

                {selectedSession &&
                showMobileAnchoredSessionCard &&
                mobileSessionAnchor ? (
                  <div
                    className="pointer-events-none absolute z-20"
                    style={getSessionCardAnchorStyle(mobileSessionAnchor)}
                  >
                    <div className="pointer-events-auto">
                      <LiveSessionCard
                        key={selectedSession.id}
                        session={selectedSession}
                        onClose={closeSelectedSession}
                        onSelectSession={selectSession}
                        sessionsAtCell={
                          selectedCluster?.sessions ?? [selectedSession]
                        }
                      />
                    </div>
                  </div>
                ) : null}
              </div>

              {selectedSession &&
              !showMobileAnchoredSessionCard &&
              !prefersAnchoredSessionCard ? (
                <LiveSessionCard
                  key={selectedSession.id}
                  session={selectedSession}
                  onClose={closeSelectedSession}
                  onSelectSession={selectSession}
                  sessionsAtCell={
                    selectedCluster?.sessions ?? [selectedSession]
                  }
                />
              ) : null}

              <LiveEventsPanel
                title={activityPanelTitle}
                events={visibleEvents}
                active={hasLiveVisitors}
                emptyMessage={activityEmptyMessage}
                hydrated={hydrated}
                onSelectEvent={handleMobileActivitySelection}
                variant="card"
              />

              {/* Metrics Grid */}
              <div className="grid grid-cols-2 gap-4">
                <MetricCard
                  title="Visitors right now"
                  value={stats.currentVisitors}
                  variant="large"
                  showChange={false}
                />
                <MetricCard
                  title="Sessions"
                  value={stats.todaySessions.count}
                  change={stats.todaySessions.change}
                  sparklineData={stats.todaySessions.sparkline}
                />
              </div>

              <div>
                <SessionsByLocation sessions={stats.sessionsByLocation} />
              </div>
            </div>
          </div>

          {/* Desktop Layout */}
          <div
            ref={containerRef}
            className="relative hidden min-h-0 flex-1 overflow-hidden rounded-lg bg-muted lg:block"
          >
            <div className="absolute inset-0 overflow-hidden">
              <div
                className="h-full w-full transition-transform duration-500 ease-out"
                style={{ transform: `translateX(${globeTranslateX}px)` }}
              >
                {VisitorGlobeComponent ? (
                  <VisitorGlobeComponent
                    ref={desktopGlobeRef}
                    visitors={globeDots}
                    onZoomChange={setGlobeZoomState}
                    onViewChange={handleViewChange}
                    onSelectCell={handleDesktopCellSelection}
                  />
                ) : (
                  <VisitorGlobeFallback />
                )}

                {selectedSession &&
                showDesktopAnchoredSessionCard &&
                desktopSessionAnchor ? (
                  <div
                    className="pointer-events-none absolute z-30"
                    style={getSessionCardAnchorStyle(desktopSessionAnchor)}
                  >
                    <div className="pointer-events-auto">
                      <LiveSessionCard
                        key={selectedSession.id}
                        session={selectedSession}
                        onClose={closeSelectedSession}
                        onSelectSession={selectSession}
                        sessionsAtCell={
                          selectedCluster?.sessions ?? [selectedSession]
                        }
                      />
                    </div>
                  </div>
                ) : null}
              </div>
            </div>

            <div
              className="absolute z-30 flex items-center gap-3"
              style={{ top: DESKTOP_PADDING, left: DESKTOP_PADDING }}
            >
              <div
                className={`size-2 rounded-full ${
                  connectionStatus === "connected"
                    ? stats.currentVisitors > 0
                      ? "animate-pulse bg-emerald-500"
                      : "bg-muted-foreground/50"
                    : connectionStatus === "connecting"
                      ? "animate-pulse bg-yellow-500 dark:bg-yellow-400"
                      : "bg-red-500 dark:bg-red-400"
                }`}
                title={
                  connectionStatus === "connected"
                    ? "Connected"
                    : connectionStatus === "connecting"
                      ? "Connecting..."
                      : "Disconnected"
                }
              />
              <h1 className="text-lg/7 font-semibold">Live View</h1>
              <span className="text-xs/4 text-muted-foreground">
                {formattedTimestamp}
              </span>
              {connectionStatus === "disconnected" && (
                <span className="text-xs/4 text-destructive">
                  Reconnecting...
                </span>
              )}
              {!areCardsVisible && (
                <Button
                  variant="ghost"
                  size="icon"
                  className={`size-8 ${FLOATING_CONTROL_CLASSNAME}`}
                  onClick={toggleCardsVisibility}
                >
                  <EyeOff className="size-4" />
                  <span className="sr-only">Show analytics cards</span>
                </Button>
              )}
            </div>

            <div
              className="absolute z-30 flex items-center gap-2"
              style={{ top: DESKTOP_PADDING, right: DESKTOP_PADDING }}
            >
              <div className="relative">
                <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  placeholder="Search location"
                  className={`w-[22rem] pr-8 pl-9 text-foreground ${FLOATING_CONTROL_CLASSNAME}`}
                  value={query}
                  onFocus={() => setDesktopFocused(true)}
                  onBlur={() => {
                    // Close suggestions shortly after blur unless moving to dropdown
                    setTimeout(() => setDesktopFocused(false), 120)
                  }}
                  onChange={(e) => setQuery(e.target.value)}
                  onKeyDown={(e) => {
                    if (!visibleSuggestions.length) return
                    if (e.key === "ArrowDown") {
                      e.preventDefault()
                      setActiveIndex((i) =>
                        Math.min(i + 1, visibleSuggestions.length - 1)
                      )
                    } else if (e.key === "ArrowUp") {
                      e.preventDefault()
                      setActiveIndex((i) => Math.max(i - 1, 0))
                    } else if (e.key === "Enter") {
                      e.preventDefault()
                      const s =
                        visibleSuggestions[activeIndex >= 0 ? activeIndex : 0]
                      if (s) {
                        setSuggestions([])
                        focusDesktopGlobe(s.lat, s.lng)
                      }
                    } else if (e.key === "Escape") {
                      setSuggestions([])
                      setQuery("")
                    }
                  }}
                />
                {query && (
                  <button
                    type="button"
                    className="absolute top-1/2 right-2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => {
                      setQuery("")
                      setSuggestions([])
                    }}
                    aria-label="Clear search"
                  >
                    <X className="size-4" />
                  </button>
                )}
                {desktopFocused &&
                  (isSearchPending ||
                    visibleSuggestions.length > 0 ||
                    showSearchHint) && (
                    <div
                      className={`${SEARCH_RESULTS_PANEL_CLASSNAME} w-[22rem]`}
                    >
                      {showSearchHint ? (
                        <div className="px-3 py-2 text-sm/5 text-muted-foreground">
                          Type one more character…
                        </div>
                      ) : isSearchPending && visibleSuggestions.length === 0 ? (
                        <div className="flex items-center gap-2 px-3 py-2 text-sm/5 text-muted-foreground">
                          <Loader2 className="size-4 animate-spin" /> Searching…
                        </div>
                      ) : (
                        visibleSuggestions.map((s, i) => (
                          <button
                            key={`${s.name}-${i}`}
                            className={`w-full truncate px-3 py-2 text-left text-sm/5 transition hover:bg-accent/70 ${i === activeIndex ? "bg-accent/70" : ""}`}
                            onMouseDown={(e) => e.preventDefault()}
                            onClick={() => {
                              setSuggestions([])
                              focusDesktopGlobe(s.lat, s.lng)
                            }}
                          >
                            {s.name}
                          </button>
                        ))
                      )}
                    </div>
                  )}
              </div>
              <Button
                variant="ghost"
                size="icon"
                className={FLOATING_CONTROL_CLASSNAME}
                onClick={toggleCardsVisibility}
                aria-pressed={areCardsVisible}
              >
                {areCardsVisible ? (
                  <Eye className="size-4" />
                ) : (
                  <EyeOff className="size-4" />
                )}
                <span className="sr-only">
                  {areCardsVisible
                    ? "Hide analytics cards"
                    : "Show analytics cards"}
                </span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className={FLOATING_CONTROL_CLASSNAME}
                onClick={toggleFullscreen}
              >
                {isFullscreen ? (
                  <Minimize2 className="size-4" />
                ) : (
                  <Maximize2 className="size-4" />
                )}
                <span className="sr-only">
                  {isFullscreen ? "Exit fullscreen" : "Enter fullscreen"}
                </span>
              </Button>
            </div>

            <aside
              className="absolute z-30 flex w-[520px] flex-col"
              style={{
                top: DESKTOP_PADDING + DESKTOP_HEADER_SPACING,
                left: DESKTOP_PADDING,
                bottom:
                  DESKTOP_BOTTOM_PADDING + DESKTOP_ACTIVITY_PANEL_RESERVED,
                transform: `translateX(${cardsTranslateX}px)`,
                transition: "transform 420ms cubic-bezier(0.22, 0.61, 0.36, 1)",
                willChange: "transform",
                pointerEvents: areCardsVisible ? "auto" : "none",
                opacity: areCardsVisible ? 1 : 0,
              }}
            >
              <div className="flex h-full flex-col gap-3 pr-4">
                <div className="grid grid-cols-2 gap-2">
                  <MetricCard
                    title="Visitors right now"
                    value={stats.currentVisitors}
                    showChange={false}
                  />
                  <MetricCard
                    title="Sessions"
                    value={stats.todaySessions.count}
                    change={stats.todaySessions.change}
                    sparklineData={stats.todaySessions.sparkline}
                  />
                </div>

                <div className="min-h-0 flex-1 overflow-y-auto pr-1">
                  <SessionsByLocation sessions={stats.sessionsByLocation} />
                </div>
              </div>
            </aside>

            {selectedSession &&
            !showDesktopAnchoredSessionCard &&
            !prefersAnchoredSessionCard ? (
              <div className="absolute top-16 right-6 z-30 w-[20rem]">
                <LiveSessionCard
                  session={selectedSession}
                  onClose={closeSelectedSession}
                  onSelectSession={selectSession}
                  sessionsAtCell={
                    selectedCluster?.sessions ?? [selectedSession]
                  }
                />
              </div>
            ) : null}

            <div className="absolute bottom-4 left-6 z-30 w-[500px]">
              <LiveEventsPanel
                title={activityPanelTitle}
                events={visibleEvents}
                active={hasLiveVisitors}
                emptyMessage={activityEmptyMessage}
                hydrated={hydrated}
                onSelectEvent={handleDesktopActivitySelection}
              />
            </div>

            <div
              className="pointer-events-none absolute z-30 flex items-end gap-3"
              style={{ bottom: DESKTOP_BOTTOM_PADDING, right: DESKTOP_PADDING }}
            >
              <div className="pointer-events-auto flex items-center gap-2 rounded-full border border-border/70 bg-card/80 px-3 py-1.5 text-xs/4 text-muted-foreground shadow-xs backdrop-blur-xs">
                <div className="flex items-center gap-1.5">
                  <div className="size-2.5 rounded-full bg-blue-600 shadow-[0_0_6px_oklch(0.546_0.245_262/0.6)] ring-1 ring-blue-400/60 dark:bg-blue-500" />
                  <span className="text-xs/4 text-muted-foreground">
                    Visitors right now
                  </span>
                </div>
              </div>
              <div className="pointer-events-auto flex flex-col items-center gap-1.5">
                <Button
                  variant="ghost"
                  size="icon"
                  className={FLOATING_CONTROL_CLASSNAME}
                  onClick={handleZoomIn}
                  disabled={zoomAtClosest}
                >
                  <Plus className="size-4" />
                  <span className="sr-only">Zoom in</span>
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  className={FLOATING_CONTROL_CLASSNAME}
                  onClick={handleZoomOut}
                  disabled={zoomAtFarthest}
                >
                  <Minus className="size-4" />
                  <span className="sr-only">Zoom out</span>
                </Button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </AdminLayout>
  )
}

function VisitorGlobeFallback() {
  return <div className="h-full w-full rounded-lg bg-muted/10" />
}
