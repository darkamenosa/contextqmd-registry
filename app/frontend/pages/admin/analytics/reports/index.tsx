import { Head, usePage } from "@inertiajs/react"

import AdminLayout from "@/layouts/admin-layout"

import { LastLoadProvider } from "../last-load-context"
import { QueryProvider } from "../query-context"
import { SiteProvider } from "../site-context"
import type { AnalyticsPageProps } from "../types"
import AnalyticsDashboard from "../ui/analytics-dashboard"
import { UserProvider } from "../user-context"

export default function AdminAnalyticsReports(props: AnalyticsPageProps) {
  const { site, user, query, defaultQuery, boot } = props
  const { url } = usePage()

  return (
    <AdminLayout>
      <Head title="Analytics Reports" />

      <div key={url} className="flex flex-col gap-4">
        <SiteProvider value={site}>
          <UserProvider value={user}>
            <QueryProvider initialQuery={query} defaultQuery={defaultQuery}>
              <LastLoadProvider>
                <AnalyticsDashboard initialBoot={boot} />
                {site.flags.dbip ? (
                  <div className="mt-6 border-t border-border pt-4 text-xs text-muted-foreground">
                    This product includes GeoLite2 data created by MaxMind,
                    available from maxmind.com.
                  </div>
                ) : null}
              </LastLoadProvider>
            </QueryProvider>
          </UserProvider>
        </SiteProvider>
      </div>
    </AdminLayout>
  )
}
