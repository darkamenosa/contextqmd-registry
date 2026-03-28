import { useEffect, useMemo, useRef, useState } from "react"

import { useSiteContext } from "../site-context"
import { useTopStatsContext } from "../top-stats-context"
import FilterBadges from "./top-bar/filter-badges"
import FilterMenu from "./top-bar/filter-menu"
import QueryPeriodsPicker from "./top-bar/query-periods-picker"
import SegmentMenu from "./top-bar/segment-menu"

type TopBarProps = {
  showCurrentVisitors: boolean
}

export default function TopBar({ showCurrentVisitors }: TopBarProps) {
  const site = useSiteContext()
  const showSegments = Array.isArray(site.segments) && site.segments.length > 1
  const [pinned, setPinned] = useState(false)
  const sentinelRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    const sentinel = sentinelRef.current
    if (!sentinel) return

    const observer = new IntersectionObserver(
      ([entry]) => {
        setPinned(!entry.isIntersecting)
      },
      { rootMargin: "-80px 0px 0px 0px" }
    )
    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [])

  return (
    <div className="relative">
      <div
        ref={sentinelRef}
        aria-hidden="true"
        className="absolute -top-16 h-16 w-full"
      />
      <div
        className={[
          "relative z-10 flex flex-col gap-3 border-b border-transparent transition-colors",
          pinned
            ? "sticky top-0 border-border bg-background/95 backdrop-blur-xs"
            : "",
        ].join(" ")}
      >
        <div className="flex flex-col gap-2 px-2 pb-1 sm:px-0">
          <div className="flex items-center justify-between gap-2">
            <div className="flex flex-wrap items-center gap-2.5">
              {showCurrentVisitors ? <CurrentVisitors /> : null}
              <div className="hidden sm:contents">
                <FilterBadges />
              </div>
            </div>

            <div className="flex shrink-0 items-center gap-2">
              <FilterMenu />
              {showSegments ? <SegmentMenu /> : null}
              <QueryPeriodsPicker />
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2.5 sm:hidden">
            <FilterBadges />
          </div>
        </div>
      </div>
    </div>
  )
}

function CurrentVisitors() {
  const { payload } = useTopStatsContext()
  const current = useMemo(() => {
    const live = payload.topStats.find(
      (stat) => stat.graphMetric === "currentVisitors"
    )
    if (live) return Math.round(live.value)
    const fallback = payload.topStats[0]
    return fallback ? Math.round(fallback.value) : 0
  }, [payload.topStats])

  return (
    <a
      href="/admin/analytics/live"
      className="flex items-center gap-2 rounded-full bg-muted px-3 py-1.5 text-sm font-semibold transition hover:bg-muted/80"
    >
      <span
        className={`inline-flex size-2 rounded-full ${current > 0 ? "animate-pulse bg-emerald-500" : "bg-muted-foreground/50"}`}
        aria-hidden="true"
      />
      <span>{current} live visitors</span>
    </a>
  )
}
