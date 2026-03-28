import { useMemo, type ComponentType, type ReactNode } from "react"
import HeatMap from "@uiw/react-heat-map"
import { FileText, Link2, MapPin, Search } from "lucide-react"

import { formatDateTime } from "@/lib/format-date"

import { flagFromIso2 } from "../../lib/country-flag"
import type { ProfileListItem, ProfileSessionPayload } from "../../types"
import { ProfileSourceInline } from "./primitives"

type SectionChipsProps = {
  title: string
  icon: ComponentType<{ className?: string }>
  items: Array<{ label: string; count: number }>
  empty: string
  renderItemIcon?: (label: string) => ReactNode
}

export function SectionChips({
  title,
  icon: Icon,
  items,
  empty,
  renderItemIcon,
}: SectionChipsProps) {
  return (
    <section className="space-y-1.5">
      <h3 className="flex items-center gap-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
        <Icon className="size-3" />
        {title}
      </h3>
      {items.length > 0 ? (
        <div className="flex flex-wrap gap-1.5">
          {items.slice(0, 8).map((item) => (
            <span
              key={`${title}-${item.label}`}
              className="inline-flex items-center gap-1 rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] text-foreground"
            >
              {renderItemIcon ? renderItemIcon(item.label) : null}
              <span>{item.label}</span>
              <span className="text-muted-foreground">{item.count}</span>
            </span>
          ))}
        </div>
      ) : (
        <p className="text-[11px] text-muted-foreground">{empty}</p>
      )}
    </section>
  )
}

export function LocationList({
  items,
}: {
  items: NonNullable<ProfileListItem["locationsUsed"]>
}) {
  return (
    <section className="space-y-1.5">
      <h3 className="flex items-center gap-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
        <MapPin className="size-3" />
        Locations used
      </h3>
      {items.length > 0 ? (
        <div className="space-y-1.5">
          {items.slice(0, 6).map((item) => (
            <div
              key={`${item.label}-${item.count}`}
              className="flex items-start justify-between gap-2 rounded-md border border-border/70 bg-muted/20 px-2.5 py-1.5"
            >
              <div className="min-w-0">
                <p className="text-xs font-medium text-foreground">
                  <ProfileLocationSummary item={item} />
                </p>
                {item.lastSeenAt ? (
                  <p className="text-[10px] text-muted-foreground">
                    Last seen {formatDateTime(item.lastSeenAt)}
                  </p>
                ) : null}
              </div>
              <span className="text-[11px] font-medium text-muted-foreground">
                {item.count}
              </span>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-[11px] text-muted-foreground">
          No location history available
        </p>
      )}
    </section>
  )
}

function ProfileLocationSummary({
  item,
}: {
  item: NonNullable<ProfileListItem["locationsUsed"]>[number]
}) {
  const flag = flagFromIso2(item.countryCode ?? undefined)
  const parts = [item.city, item.region, item.country]
    .filter(Boolean)
    .filter(
      (value, index, list) =>
        list.findIndex(
          (candidate) =>
            candidate?.toLocaleLowerCase() === value?.toLocaleLowerCase()
        ) === index
    )

  return (
    <>
      {flag ? <span className="mr-1">{flag}</span> : null}
      {parts.join(", ") || item.label}
    </>
  )
}

export function TopPagesList({
  items,
}: {
  items: NonNullable<ProfileListItem["topPages"]>
}) {
  return (
    <section className="space-y-1.5">
      <h3 className="flex items-center gap-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
        <FileText className="size-3" />
        Top pages
      </h3>
      {items.length > 0 ? (
        <div className="space-y-1.5">
          {items.slice(0, 6).map((item) => (
            <a
              key={`${item.label}-${item.count}`}
              href={item.label}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center justify-between gap-2 rounded-md border border-border/70 bg-muted/20 px-2.5 py-1.5 transition-colors hover:bg-muted/40"
            >
              <span className="truncate text-xs text-foreground underline decoration-muted-foreground/30 underline-offset-2">
                {item.label}
              </span>
              <span className="text-[11px] font-medium text-muted-foreground">
                {item.count}
              </span>
            </a>
          ))}
        </div>
      ) : (
        <p className="text-[11px] text-muted-foreground">No page history yet</p>
      )}
    </section>
  )
}

export function ActivityHeatmap({
  sessionEvents,
}: {
  sessionEvents: Array<{ startedAt?: string | null; count: number }>
}) {
  const { heatmapData, startDate } = useMemo(() => {
    const dayCounts = new Map<string, number>()
    for (const session of sessionEvents) {
      if (!session.startedAt) continue
      const key = session.startedAt.slice(0, 10)
      dayCounts.set(key, (dayCounts.get(key) ?? 0) + session.count)
    }

    const start = new Date()
    start.setMonth(start.getMonth() - 6)

    return {
      heatmapData: Array.from(dayCounts, ([date, count]) => ({
        date: date.replace(/-/g, "/"),
        count,
      })),
      startDate: start,
    }
  }, [sessionEvents])

  if (heatmapData.length === 0) {
    return (
      <p className="text-xs text-muted-foreground">No activity heatmap yet</p>
    )
  }

  return (
    <div className="overflow-hidden">
      <HeatMap
        value={heatmapData}
        startDate={startDate}
        endDate={new Date()}
        rectSize={8}
        space={2}
        legendCellSize={0}
        weekLabels={false}
        style={{ width: "100%", maxHeight: 100 }}
        panelColors={{
          0: "#ebebeb",
          1: "#d4d4d4",
          3: "#a3a3a3",
          6: "#636363",
          10: "#2b2b2b",
        }}
      />
    </div>
  )
}

export function SessionSourceSummary({
  sourceSummary,
}: {
  sourceSummary?: ProfileSessionPayload["sourceSummary"]
}) {
  if (!sourceSummary) return null

  const trackerItems = [
    sourceSummary.utmSource
      ? { key: "utm_source", value: sourceSummary.utmSource }
      : null,
    sourceSummary.utmMedium
      ? { key: "utm_medium", value: sourceSummary.utmMedium }
      : null,
    sourceSummary.utmCampaign
      ? { key: "utm_campaign", value: sourceSummary.utmCampaign }
      : null,
    ...(sourceSummary.trackerParams || []),
  ].filter(Boolean) as Array<{ key: string; value: string }>
  const searchTerms = sourceSummary.searchTerms || []
  const foundViaLabel =
    sourceSummary.sourceLabel === "Direct / None"
      ? "Found via"
      : "Found via referrer"

  return (
    <section className="rounded-lg border border-border/70 bg-muted/20 px-3 py-3">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
        <Search className="size-3.5 text-muted-foreground" />
        <span className="text-muted-foreground">{foundViaLabel}</span>
        <span className="rounded-md border border-border bg-background px-2 py-1 font-medium text-foreground">
          <ProfileSourceInline
            source={sourceSummary.sourceLabel}
            emptyLabel="Direct / None"
            iconClassName="size-3.5"
            textClassName="font-medium"
          />
        </span>
        {sourceSummary.landingPage ? (
          <span className="rounded-md border border-border bg-background px-2 py-1 text-muted-foreground">
            landed on {sourceSummary.landingPage}
          </span>
        ) : null}
      </div>

      {sourceSummary.referringDomain &&
      sourceSummary.referringDomain !== sourceSummary.sourceLabel &&
      sourceSummary.sourceLabel !== "Direct / None" ? (
        <p className="mt-2 text-[11px] text-muted-foreground">
          Referring domain: {sourceSummary.referringDomain}
        </p>
      ) : null}

      {trackerItems.length > 0 ? (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {trackerItems.map((item) => (
            <span
              key={`${item.key}-${item.value}`}
              className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2 py-1 text-[11px] text-muted-foreground"
            >
              <Link2 className="size-3" />
              <span>
                {item.key}={item.value}
              </span>
            </span>
          ))}
        </div>
      ) : null}

      {searchTerms.length > 0 ? (
        <div className="mt-3 grid gap-2 sm:grid-cols-[minmax(0,1fr)_140px] sm:items-start">
          <div>
            <p className="text-[10px] font-semibold tracking-wider text-muted-foreground uppercase">
              Search Terms Preview
            </p>
            <div className="mt-2 space-y-1.5">
              {searchTerms.map((term) => (
                <div
                  key={term.label}
                  className="flex items-center justify-between gap-3 text-[11px]"
                >
                  <span className="truncate font-medium text-foreground">
                    {term.label}
                  </span>
                  <span className="shrink-0 text-muted-foreground">
                    {term.probability}%
                  </span>
                </div>
              ))}
            </div>
          </div>
          <div className="space-y-1.5 pt-5 sm:pt-0">
            {searchTerms.map((term) => (
              <div key={`${term.label}-bar`} className="space-y-1">
                <div className="h-1.5 overflow-hidden rounded-full bg-border/70">
                  <div
                    className="h-full rounded-full bg-foreground/80"
                    style={{ width: `${term.probability}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      ) : null}
    </section>
  )
}
