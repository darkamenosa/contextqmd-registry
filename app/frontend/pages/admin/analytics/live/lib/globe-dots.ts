import {
  formatCompactLocation,
  formatProfileLocation,
} from "../../ui/profile/formatters"

type VisitorDot = {
  lat: number
  lng: number
  type: "visitor"
  ts?: number
  label?: string | null
  city?: string | null
  region?: string | null
  country?: string | null
  countryCode?: string | null
}

type LiveSession = {
  lat?: number | null
  lng?: number | null
  name?: string | null
  locationLabel?: string | null
  city?: string | null
  region?: string | null
  country?: string | null
  countryCode?: string | null
  lastSeenAt?: string | null
}

export function resolveLiveGlobeLabel({
  label,
  locationLabel,
  city,
  region,
  country,
  countryCode,
  name,
}: {
  label?: string | null
  locationLabel?: string | null
  city?: string | null
  region?: string | null
  country?: string | null
  countryCode?: string | null
  name?: string | null
}) {
  const formattedLocation = formatProfileLocation({ city, region, country })
  const compactLocation = formatCompactLocation({
    city,
    region,
    country,
    countryCode,
  })

  return (
    compactLocation ||
    locationLabel?.trim() ||
    label?.trim() ||
    formattedLocation ||
    name?.trim() ||
    undefined
  )
}

export function buildLiveGlobeDots(
  liveSessions: LiveSession[],
  visitorDots: VisitorDot[]
): VisitorDot[] {
  const sessionDots = liveSessions
    .filter(
      (session) =>
        typeof session.lat === "number" &&
        Number.isFinite(session.lat) &&
        typeof session.lng === "number" &&
        Number.isFinite(session.lng)
    )
    .map((session) => {
      const timestamp = session.lastSeenAt
        ? Date.parse(session.lastSeenAt)
        : NaN

      return {
        lat: session.lat as number,
        lng: session.lng as number,
        type: "visitor" as const,
        label: resolveLiveGlobeLabel(session),
        city: session.city ?? undefined,
        region: session.region ?? undefined,
        country: session.country ?? undefined,
        countryCode: session.countryCode ?? undefined,
        ts: Number.isFinite(timestamp) ? timestamp : undefined,
      }
    })

  if (sessionDots.length > 0) return sessionDots

  return visitorDots.map((dot) => ({
    ...dot,
    label: resolveLiveGlobeLabel(dot),
  }))
}
