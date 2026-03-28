import { useAnalyticsDashboardContext } from "./dashboard-context"

export type LastLoadContextValue = {
  lastLoadedAt: number
  touch: () => void
}

export function useLastLoadContext() {
  const context = useAnalyticsDashboardContext()
  return {
    lastLoadedAt: context.lastLoadedAt,
    touch: context.touchLastLoaded,
  } as LastLoadContextValue
}
