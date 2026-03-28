import { useMemo } from "react"

import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type { AnalyticsDashboardBoot } from "../types"
import BehaviorsPanel from "./behaviors-panel"
import DevicesPanel from "./devices-panel"
import LocationsPanel from "./locations-panel"
import PagesPanel from "./pages-panel"
import SourcesPanel from "./sources-panel"
import TopBar from "./top-bar"
import VisitorGraph from "./visitor-graph"

export default function AnalyticsDashboard({
  initialBoot,
}: {
  initialBoot: AnalyticsDashboardBoot
}) {
  const { query } = useQueryContext()
  const site = useSiteContext()
  const isRealtime = useMemo(() => query.period === "realtime", [query.period])
  const hasBehaviors =
    site.hasGoals ||
    site.funnelsAvailable ||
    site.propsAvailable ||
    site.profilesAvailable

  return (
    <div className="flex flex-col gap-4">
      <TopBar showCurrentVisitors={!isRealtime} />

      <VisitorGraph initialGraph={initialBoot.mainGraph} />

      <section className="grid gap-4 lg:grid-cols-2">
        <SourcesPanel
          initialData={initialBoot.sources}
          initialMode={initialBoot.ui.sourcesMode}
        />
        <PagesPanel
          initialData={initialBoot.pages}
          initialMode={initialBoot.ui.pagesMode}
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <LocationsPanel
          initialData={initialBoot.locations}
          initialMode={initialBoot.ui.locationsMode}
        />
        <DevicesPanel
          initialData={initialBoot.devices}
          initialBaseMode={initialBoot.ui.devicesBaseMode}
          initialMode={initialBoot.ui.devicesMode}
        />
      </section>

      {hasBehaviors && initialBoot.behaviors ? (
        <BehaviorsPanel
          initialData={initialBoot.behaviors}
          initialMode={initialBoot.ui.behaviorsMode}
          initialFunnel={initialBoot.ui.behaviorsFunnel}
          initialProperty={initialBoot.ui.behaviorsProperty}
        />
      ) : null}
    </div>
  )
}
