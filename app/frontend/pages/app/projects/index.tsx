import { Head } from "@inertiajs/react"

import AppLayout from "@/layouts/app-layout"

export default function AppProjects() {
  return (
    <AppLayout>
      <Head title="Projects" />
      <div className="grid auto-rows-min gap-4 md:grid-cols-3">
        <div className="aspect-video rounded-xl bg-muted/50" />
        <div className="aspect-video rounded-xl bg-muted/50" />
        <div className="aspect-video rounded-xl bg-muted/50" />
      </div>
      <div className="min-h-[100vh] flex-1 rounded-xl bg-muted/50 md:min-h-min" />
    </AppLayout>
  )
}
