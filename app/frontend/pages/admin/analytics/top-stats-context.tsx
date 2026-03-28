import { useAnalyticsDashboardContext } from "./dashboard-context"
import type { TopStatsPayload } from "./types"

export type TopStatsContextValue = {
  payload: TopStatsPayload
  update: (payload: TopStatsPayload) => void
}

export function useTopStatsContext() {
  const context = useAnalyticsDashboardContext()
  return {
    payload: context.topStats,
    update: context.updateTopStats,
  }
}
