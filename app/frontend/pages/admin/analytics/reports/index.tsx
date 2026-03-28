import { Head, usePage } from "@inertiajs/react"

import AdminLayout from "@/layouts/admin-layout"

import { AnalyticsDashboardProvider } from "../dashboard-context"
import { QueryProvider } from "../query-context"
import type { AnalyticsPageProps } from "../types"
import AnalyticsDashboard from "../ui/analytics-dashboard"

export default function AdminAnalyticsReports(props: AnalyticsPageProps) {
  const { site, query, defaultQuery, boot } = props
  const { url } = usePage()

  return (
    <AdminLayout>
      <Head title="Analytics Reports" />

      <div key={url} className="flex flex-col gap-4">
        <AnalyticsDashboardProvider site={site} initialTopStats={boot.topStats}>
          <QueryProvider
            initialQuery={query}
            defaultQuery={defaultQuery}
            initialUrl={url}
          >
            <AnalyticsDashboard initialBoot={boot} />
            {site.flags.dbip ? (
              <div className="mt-6 border-t border-border pt-4 text-xs text-muted-foreground">
                This product includes GeoLite2 data created by MaxMind,
                available from maxmind.com.
              </div>
            ) : null}
          </QueryProvider>
        </AnalyticsDashboardProvider>
      </div>
    </AdminLayout>
  )
}
