export function analyticsPreferenceKey(prefix: string, domain: string) {
  return `${prefix}.${domain}`
}

export function writeAnalyticsPreference(key: string, value: string) {
  if (typeof window === "undefined") return
  localStorage.setItem(key, value)
}
