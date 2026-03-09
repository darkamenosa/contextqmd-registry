import { Head } from "@inertiajs/react"

import AdminLayout from "@/layouts/admin-layout"

export default function AdminAnalyticsLive() {
  return (
    <AdminLayout>
      <Head title="Live Analytics" />
      <div className="grid auto-rows-min gap-4 md:grid-cols-3">
        <div className="aspect-video rounded-xl bg-muted/50" />
        <div className="aspect-video rounded-xl bg-muted/50" />
        <div className="aspect-video rounded-xl bg-muted/50" />
      </div>
      <div className="min-h-[100vh] flex-1 rounded-xl bg-muted/50 md:min-h-min" />
    </AdminLayout>
  )
}
