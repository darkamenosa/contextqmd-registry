import { useCallback } from "react"

import { baseAnalyticsPath } from "../lib/dialog-path"
import { navigateAnalytics } from "../lib/location-store"

export function getReportsDialogSearch() {
  const params = new URLSearchParams(window.location.search)
  params.delete("dialog")
  return params.toString()
}

export function openReportsDialogRoute(pathBuilder: (qs: string) => string) {
  navigateAnalytics(pathBuilder(getReportsDialogSearch()))
}

export function syncReportsDialogRoute(
  open: boolean,
  pathBuilder: (qs: string) => string
) {
  const search = getReportsDialogSearch()
  navigateAnalytics(open ? pathBuilder(search) : baseAnalyticsPath(search))
}

export function closeReportsDialogRoute() {
  navigateAnalytics(baseAnalyticsPath(getReportsDialogSearch()))
}

export function useCloseReportsDialogRoute() {
  return useCallback(() => {
    try {
      closeReportsDialogRoute()
    } catch {
      // Ignore history errors; local dialog state remains authoritative.
    }
  }, [])
}
