import {
  setBehaviorsFunnelSearchParam,
  setBehaviorsPropertySearchParam,
} from "./dashboard-url-state"
import { setPanelModeSearchParam } from "./panel-mode"
import { canonicalReportSearch } from "./report-url"

export function buildBehaviorsRouteSearch(
  search: string,
  {
    mode,
    funnel,
    property,
  }: {
    mode: string
    funnel?: string | null
    property?: string | null
  }
) {
  const searchParams = new URLSearchParams(search)
  searchParams.delete("dialog")
  setPanelModeSearchParam(searchParams, "behaviors", mode)
  setBehaviorsFunnelSearchParam(searchParams, funnel)
  setBehaviorsPropertySearchParam(searchParams, property)
  return canonicalReportSearch(searchParams)
}
