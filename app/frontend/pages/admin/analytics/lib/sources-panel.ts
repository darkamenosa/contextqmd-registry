import type { AnalyticsQuery, ListPayload } from "../types"
import {
  modeForSegment,
  type ParsedDialog,
  type SourcesMode,
} from "./dialog-path"
import { SOURCES_MODES } from "./panel-mode"

export type SourcesTakeover = "none" | "referrers" | "search-terms"

export const SOURCES_CAMPAIGN_OPTIONS: Array<{
  value: SourcesMode
  label: string
}> = [
  { value: "utm-medium", label: "UTM Mediums" },
  { value: "utm-source", label: "UTM Sources" },
  { value: "utm-campaign", label: "UTM Campaigns" },
  { value: "utm-content", label: "UTM Contents" },
  { value: "utm-term", label: "UTM Terms" },
]

const TITLE_FOR_MODE: Record<SourcesMode, string> = {
  channels: "Top Channels",
  all: "Top Sources",
  "utm-medium": "UTM Mediums",
  "utm-source": "UTM Sources",
  "utm-campaign": "UTM Campaigns",
  "utm-content": "UTM Contents",
  "utm-term": "UTM Terms",
}

export function normalizeSourcesMode(
  mode: string | null | undefined
): SourcesMode {
  return SOURCES_MODES.includes(mode as SourcesMode)
    ? (mode as SourcesMode)
    : "all"
}

export function isGoogleSource(source: string | null | undefined) {
  return Boolean(source && /google/i.test(source))
}

export function getSourcesTakeover(
  source: string | null | undefined
): SourcesTakeover {
  if (!source) return "none"
  return isGoogleSource(source) ? "search-terms" : "referrers"
}

export function resolveSourcesViewState(
  parsedDialog: ParsedDialog,
  filters: AnalyticsQuery["filters"],
  preferredMode: SourcesMode,
  derivedMode: SourcesMode | null
) {
  const dialogMode: SourcesMode | null =
    parsedDialog.type === "referrers"
      ? "all"
      : parsedDialog.type === "segment"
        ? modeForSegment(parsedDialog.segment)
        : null

  const activeSource =
    parsedDialog.type === "referrers" ? parsedDialog.source : filters?.source
  const takeover = getSourcesTakeover(activeSource)

  return {
    mode: dialogMode ?? derivedMode ?? preferredMode,
    activeSource,
    takeover,
    isGoogleActive: takeover === "search-terms",
    detailsOpen:
      parsedDialog.type === "segment" ||
      (parsedDialog.type === "referrers" && takeover === "search-terms"),
    refDetailsOpen:
      parsedDialog.type === "referrers" && takeover === "referrers",
  }
}

export function isSourcesCampaignMode(mode: SourcesMode) {
  return SOURCES_CAMPAIGN_OPTIONS.some((option) => option.value === mode)
}

export function getSourcesCampaignLabel(mode: SourcesMode) {
  if (!isSourcesCampaignMode(mode)) return "Campaigns"
  return (
    SOURCES_CAMPAIGN_OPTIONS.find((option) => option.value === mode)?.label ??
    "Campaigns"
  )
}

export function getSourcesCardTitle(
  mode: SourcesMode,
  takeover: SourcesTakeover
) {
  if (takeover === "search-terms") return "Search Terms"
  if (takeover === "referrers") return "Top Referrers"
  return TITLE_FOR_MODE[mode] ?? "Top Sources"
}

export function getSourcesDialogTitle(mode: SourcesMode) {
  if (mode === "channels") return "Top Acquisition Channels"
  return TITLE_FOR_MODE[mode] ?? "Top Sources"
}

export function getSourcesFirstColumnLabel(mode: SourcesMode) {
  if (mode === "channels") return "Channel"
  if (mode.startsWith("utm-")) {
    return getSourcesCampaignLabel(mode).replace(/s$/, "")
  }
  return "Source"
}

export function getSourcesFilterKey(mode: SourcesMode) {
  switch (mode) {
    case "channels":
      return "channel"
    case "utm-medium":
      return "utm_medium"
    case "utm-source":
      return "utm_source"
    case "utm-campaign":
      return "utm_campaign"
    case "utm-content":
      return "utm_content"
    case "utm-term":
      return "utm_term"
    case "all":
    default:
      return "source"
  }
}

export function shouldShowSourceIcon(mode: SourcesMode) {
  return mode === "all" || mode === "utm-source"
}

export function hasUsableUtmData(mode: SourcesMode, data: ListPayload) {
  if (!mode.startsWith("utm-")) return true

  const rows = data.results
  const total = rows.reduce((sum, row) => sum + Number(row.visitors ?? 0), 0)
  const nonNone = rows.filter((row) => {
    const name = String(row.name ?? "").trim()
    return (
      name !== "" && name !== "(none)" && name.toLowerCase() !== "(not set)"
    )
  })
  const nonNoneTotal = nonNone.reduce(
    (sum, row) => sum + Number(row.visitors ?? 0),
    0
  )

  if (nonNone.length === 0) return false
  return nonNoneTotal / Math.max(total, 1) >= 0.1
}
