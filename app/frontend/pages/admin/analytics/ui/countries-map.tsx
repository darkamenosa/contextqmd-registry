import { useMemo, useState } from "react"
import worldTopology from "@/data/countries-110m.json"
import { geoMercator, geoPath } from "d3-geo"
import { feature } from "topojson-client"

import { flagFromIso2 } from "../lib/country-flag"
import { numberShortFormatter } from "../lib/number-formatter"
import type { MapPayload } from "../types"

const MAP_WIDTH = 720
const MAP_HEIGHT = 576
const MAP_MARGIN_X = 12
const MAP_MARGIN_Y = 0
const MAP_COLOR_STOPS = [
  "#d6eef8",
  "#a0d8ef",
  "#6ec2e6",
  "#45a5d4",
  "#2b7da8",
] as const
const MAP_IDLE_FILL =
  "color-mix(in oklch, var(--muted) 82%, var(--background) 18%)"
const MAP_IDLE_STROKE =
  "color-mix(in oklch, var(--border) 82%, var(--foreground) 18%)"
const MAP_ACTIVE_STROKE = "#6ec2e6"

type CountriesMapProps = {
  data: MapPayload
  onSelectCountry: (isoCode: string, label?: string) => void
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GeoFeature = any

export default function CountriesMap({
  data,
  onSelectCountry,
}: CountriesMapProps) {
  const [tooltip, setTooltip] = useState<{
    x: number
    y: number
    name: string
    flag?: string | null
    visitors: number
    width: number
    height: number
  } | null>(null)

  const features = useMemo(() => {
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const topology = worldTopology as any
      const collection = feature(
        topology,
        topology.objects.countries
      ) as unknown as { features: GeoFeature[] }
      return collection.features.filter((featureItem) => {
        const id = String(featureItem.id)
        const name = String(
          featureItem.properties?.name ||
            featureItem.properties?.NAME ||
            featureItem.properties?.ADMIN ||
            ""
        )
        if (id === "010") return false
        if (/antarctica/i.test(name)) return false
        return true
      })
    } catch (error) {
      console.error("Failed to prepare map features", error)
      return []
    }
  }, [])

  const lookup = useMemo(() => {
    const map = new Map<
      string,
      { visitors: number; code?: string; name: string }
    >()
    data.map.results.forEach((entry) => {
      const record = {
        visitors: entry.visitors,
        code: entry.code?.toUpperCase(),
        name: entry.name,
      }

      if (entry.numeric) {
        map.set(entry.numeric, record)
      }

      const alpha3 = entry.alpha3?.toUpperCase()
      if (alpha3) {
        map.set(alpha3, record)
      }

      const alpha2 = entry.alpha2?.toUpperCase()
      if (alpha2) {
        map.set(alpha2, record)
      }
    })
    return map
  }, [data])

  const projection = useMemo(() => {
    const projectionValue = geoMercator()
    if (features.length > 0) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const featureCollection = { type: "FeatureCollection", features } as any
      return projectionValue.fitExtent(
        [
          [MAP_MARGIN_X, MAP_MARGIN_Y],
          [MAP_WIDTH - MAP_MARGIN_X, MAP_HEIGHT - MAP_MARGIN_Y],
        ],
        featureCollection
      )
    }

    return projectionValue
      .scale((MAP_WIDTH - 2 * MAP_MARGIN_X) / (2 * Math.PI))
      .translate([MAP_WIDTH / 2, MAP_HEIGHT / 2])
  }, [features])

  const pathGenerator = useMemo(() => geoPath(projection), [projection])
  const max = Math.max(
    ...Array.from(lookup.values()).map((value) => value.visitors),
    1
  )

  return (
    <div className="relative overflow-hidden rounded-xs border border-border/70 bg-card">
      <svg
        role="img"
        aria-label="World map highlighting visitor distribution"
        viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`}
        className="h-auto w-full"
        preserveAspectRatio="xMidYMid meet"
      >
        <g>
          {features.map((featureItem) => {
            const numericId = String(featureItem.id)
            const alpha3Candidate = featureItem.properties?.ISO_A3
            const iso2Candidate = featureItem.properties?.ISO_A2

            const record =
              lookup.get(numericId) ||
              (typeof alpha3Candidate === "string" &&
                lookup.get(alpha3Candidate.toUpperCase())) ||
              (typeof iso2Candidate === "string" &&
                lookup.get(iso2Candidate.toUpperCase()))

            const intensity = record ? record.visitors / max : 0
            const fill = record ? colorForIntensity(intensity) : MAP_IDLE_FILL
            const stroke = record ? MAP_ACTIVE_STROKE : MAP_IDLE_STROKE
            const path = pathGenerator(featureItem)
            if (!path) return null

            return (
              <path
                key={
                  (typeof alpha3Candidate === "string"
                    ? alpha3Candidate
                    : iso2Candidate) ?? path
                }
                d={path}
                fill={fill}
                stroke={stroke}
                strokeWidth={record ? 0.95 : 0.65}
                className="cursor-pointer transition-all duration-150 hover:brightness-[1.06]"
                onClick={() => {
                  if (record) {
                    onSelectCountry(
                      record.code ?? String(alpha3Candidate ?? iso2Candidate),
                      record.name
                    )
                  }
                }}
                onMouseMove={(event) => {
                  if (!record) {
                    setTooltip(null)
                    return
                  }

                  const bounds =
                    event.currentTarget.ownerSVGElement?.getBoundingClientRect()
                  if (!bounds) return

                  const flag =
                    flagFromIso2(record.code ?? String(iso2Candidate ?? "")) ||
                    null
                  setTooltip({
                    name: prettifyCountryName(record.name),
                    flag,
                    visitors: record.visitors,
                    x: event.clientX - bounds.left,
                    y: event.clientY - bounds.top,
                    width: bounds.width,
                    height: bounds.height,
                  })
                }}
                onMouseLeave={() => setTooltip(null)}
              />
            )
          })}
        </g>
      </svg>
      <div className="flex items-center justify-between border-t border-border/60 px-3 py-2.5">
        <div className="text-[11px] tracking-[0.16em] text-muted-foreground uppercase">
          Visitor intensity
        </div>
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
          <span>Sparse</span>
          <div
            aria-hidden="true"
            className="h-2 w-30 rounded-full ring-1 ring-border/60"
            style={{
              background: `linear-gradient(90deg, ${MAP_COLOR_STOPS.join(", ")})`,
            }}
          />
          <span>Dense</span>
        </div>
      </div>
      {tooltip ? (
        <div
          className="pointer-events-none absolute z-50 rounded-xl border border-border/70 bg-popover/96 p-3 text-popover-foreground shadow-xl backdrop-blur-xs"
          style={{
            left: Math.min(tooltip.x + 12, tooltip.width - 200),
            top: Math.min(tooltip.y + 12, tooltip.height - 72),
            minWidth: "160px",
          }}
        >
          <div className="mb-1 flex items-center gap-1.5">
            {tooltip.flag ? (
              <span aria-hidden className="shrink-0 text-sm/4.5">
                {tooltip.flag}
              </span>
            ) : null}
            <p className="truncate text-sm font-medium text-foreground">
              {tooltip.name}
            </p>
          </div>
          <div className="flex items-baseline gap-1.5">
            <span className="text-lg font-medium text-foreground">
              {numberShortFormatter(tooltip.visitors)}
            </span>
            <span className="text-xs text-muted-foreground">Visitors</span>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function colorForIntensity(value: number) {
  const clamped = Math.min(Math.max(value, 0), 1)
  const scaled = clamped * (MAP_COLOR_STOPS.length - 1)
  const index = Math.min(Math.floor(scaled), MAP_COLOR_STOPS.length - 2)
  const mix = scaled - index
  const from = MAP_COLOR_STOPS[index]
  const to = MAP_COLOR_STOPS[index + 1]
  const fromWeight = Math.round((1 - mix) * 100)
  const toWeight = 100 - fromWeight

  return `color-mix(in oklch, ${from} ${fromWeight}%, ${to} ${toWeight}%)`
}

function prettifyCountryName(name: string): string {
  const str = String(name || "")
  const direct: Record<string, string> = {
    "United States of America (the)": "United States",
    "United States of America": "United States",
    "Viet Nam": "Vietnam",
  }
  if (direct[str]) return direct[str]
  return str.replace(/\s*\(the\)\s*$/i, "").trim()
}
