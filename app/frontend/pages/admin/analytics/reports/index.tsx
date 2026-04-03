import { Head, usePage } from "@inertiajs/react"

import AdminLayout from "@/layouts/admin-layout"

import { AnalyticsDashboardProvider } from "../dashboard-context"
import { AnalyticsHostProvider } from "../host-context"
import { QueryProvider } from "../query-context"
import type { AnalyticsPageProps } from "../types"
import AnalyticsDashboard from "../ui/analytics-dashboard"

export default function AdminAnalyticsReports(props: AnalyticsPageProps) {
  const { site, query, defaultQuery, boot, liveSubscriptionToken } = props
  const { url } = usePage()

  return (
    <AdminLayout>
      <Head title="Analytics Reports" />

      <div key={url} className="flex flex-col gap-4">
        <AnalyticsHostProvider initialUrl={url}>
          <AnalyticsDashboardProvider
            site={site}
            initialTopStats={boot.topStats}
            liveSubscriptionToken={liveSubscriptionToken}
          >
            <QueryProvider initialQuery={query} defaultQuery={defaultQuery}>
              <AnalyticsDashboard initialBoot={boot} />
              {site.flags.dbip ? (
                <div className="mt-6 border-t border-border pt-4 text-xs text-muted-foreground">
                  This product includes GeoLite2 data created by MaxMind,
                  available from maxmind.com.
                </div>
              ) : null}
            </QueryProvider>
          </AnalyticsDashboardProvider>
        </AnalyticsHostProvider>
      </div>
    </AdminLayout>
  )
}
