export const ANALYTICS_SETTINGS_TABS = [
  "tracking",
  "goals",
  "integrations",
  "exclusions",
  "funnels",
] as const

export type AnalyticsSettingsTab = (typeof ANALYTICS_SETTINGS_TABS)[number]

export const DEFAULT_ANALYTICS_SETTINGS_TAB: AnalyticsSettingsTab = "tracking"

export function normalizeAnalyticsSettingsTab(
  value: string | null | undefined
): AnalyticsSettingsTab {
  if (
    value &&
    ANALYTICS_SETTINGS_TABS.includes(value as AnalyticsSettingsTab)
  ) {
    return value as AnalyticsSettingsTab
  }

  return DEFAULT_ANALYTICS_SETTINGS_TAB
}

export function getAnalyticsSettingsTabFromUrl(url: string) {
  const parsed = new URL(url, "http://analytics.test")
  return normalizeAnalyticsSettingsTab(parsed.searchParams.get("tab"))
}

export function buildAnalyticsSettingsTabUrl(
  url: string,
  tab: AnalyticsSettingsTab
) {
  const parsed = new URL(url, "http://analytics.test")

  if (tab === DEFAULT_ANALYTICS_SETTINGS_TAB) {
    parsed.searchParams.delete("tab")
  } else {
    parsed.searchParams.set("tab", tab)
  }

  const search = parsed.searchParams.toString()
  return `${parsed.pathname}${search ? `?${search}` : ""}${parsed.hash}`
}
