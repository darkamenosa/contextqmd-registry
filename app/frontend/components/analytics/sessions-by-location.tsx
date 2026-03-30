import { formatCompactLocation } from "@/pages/admin/analytics/ui/profile/formatters"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

type LocationSession = {
  country: string
  city: string
  region?: string
  countryCode: string
  visitors: number
}

export function SessionsByLocation({
  sessions,
}: {
  sessions: LocationSession[]
}) {
  if (!sessions || sessions.length === 0) {
    return (
      <Card className="gap-0 rounded-lg border border-border bg-card py-0">
        <CardHeader className="px-4 pt-4 pb-2">
          <CardTitle className="text-sm/5 font-semibold text-muted-foreground">
            Sessions by location
          </CardTitle>
        </CardHeader>
        <CardContent className="px-4 pt-2 pb-4">
          <div className="py-4 text-center text-xs/4 text-muted-foreground">
            No active sessions
          </div>
        </CardContent>
      </Card>
    )
  }

  const maxVisitors = Math.max(...sessions.map((s) => s.visitors))

  return (
    <Card className="gap-0 rounded-lg border border-border bg-card py-0">
      <CardHeader className="px-4 pt-4 pb-2">
        <CardTitle className="text-sm/5 font-semibold text-muted-foreground">
          Sessions by location
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2.5 px-4 pt-2 pb-4">
        {sessions.map((session, i) => {
          const locationLabel = formatCompactLocation(
            {
              city: session.city,
              region: session.region,
              country:
                session.country && session.country !== "Unknown"
                  ? session.country
                  : null,
              countryCode: session.countryCode,
            },
            { appendCountryCode: true }
          )

          return (
            <div key={i} className="flex flex-col gap-2">
              <div className="flex items-center justify-between text-xs/4 text-muted-foreground">
                <span className="truncate font-medium text-foreground">
                  {locationLabel || "Unknown"}
                </span>
                <span className="ml-2 shrink-0 text-muted-foreground">
                  {session.visitors}
                </span>
              </div>
              <div className="h-[6px] overflow-hidden rounded-full bg-accent">
                <div
                  className="h-full rounded-full bg-primary transition-all duration-300"
                  style={{
                    width: `${(session.visitors / maxVisitors) * 100}%`,
                  }}
                />
              </div>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )
}
