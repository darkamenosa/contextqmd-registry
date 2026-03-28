import { useAnalyticsDashboardContext } from "./dashboard-context"
import type { SiteContextValue } from "./types"

export function useSiteContext() {
  return useAnalyticsDashboardContext().site as SiteContextValue
}
