type VisitorDot = {
  lat: number
  lng: number
  type: "visitor"
  ts?: number
  city?: string | null
}

type LiveSession = {
  lat?: number | null
  lng?: number | null
  city?: string | null
  lastSeenAt?: string | null
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
        city: session.city ?? undefined,
        ts: Number.isFinite(timestamp) ? timestamp : undefined,
      }
    })

  return sessionDots.length > 0 ? sessionDots : visitorDots
}
