import { useMemo } from "react"

import { createAnalyticsApi } from "../api"
import { useAnalyticsHost } from "../host-context"

export function useAnalyticsApi() {
  const { scopedPath } = useAnalyticsHost()
  return useMemo(() => createAnalyticsApi(scopedPath), [scopedPath])
}
