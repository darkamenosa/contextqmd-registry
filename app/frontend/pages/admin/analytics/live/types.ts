export type VisitorDot = {
  lat: number
  lng: number
  type: "visitor"
  ts?: number
  city?: string | null
}

export type LocationSession = {
  country: string
  city: string
  region?: string
  countryCode: string
  visitors: number
}

export type SparklinePair = { today: number[]; yesterday: number[] }

export type LiveSessionSnapshot = {
  sessionId: string
  visitId: number
  profileId: string | null
  name: string
  email?: string | null
  status: string
  identified: boolean
  country?: string | null
  countryCode?: string | null
  city?: string | null
  region?: string | null
  deviceType?: string | null
  os?: string | null
  browser?: string | null
  source?: string | null
  currentPage?: string | null
  startedAt?: string | null
  lastSeenAt?: string | null
  totalVisits: number
  scopedVisits: number
  lat?: number | null
  lng?: number | null
  active: boolean
}

export type LiveEvent = LiveSessionSnapshot & {
  id: number
  eventName: string
  label: string
  occurredAt: string
  page?: string | null
}

export type LiveSession = LiveSessionSnapshot & {
  profileId: string | null
  id: string
  recentEvents: LiveEvent[]
}

export type LiveStats = {
  currentVisitors: number
  todaySessions: {
    count: number
    change: number
    sparkline: SparklinePair
  }
  sessionsByLocation: LocationSession[]
  visitorDots: VisitorDot[]
  liveSessions: LiveSession[]
  recentEvents: LiveEvent[]
}

export const EMPTY_STATS: LiveStats = {
  currentVisitors: 0,
  todaySessions: {
    count: 0,
    change: 0,
    sparkline: { today: [], yesterday: [] },
  },
  sessionsByLocation: [],
  visitorDots: [],
  liveSessions: [],
  recentEvents: [],
}
