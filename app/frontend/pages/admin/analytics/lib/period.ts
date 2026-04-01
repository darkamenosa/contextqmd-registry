import type { AnalyticsPeriod } from "../types"

export type AnalyticsGraphInterval =
  | "minute"
  | "hour"
  | "day"
  | "week"
  | "month"

export type AnalyticsPeriodSelection = {
  value: AnalyticsPeriod
  setDate?: "current" | "last"
}

export type AnalyticsPeriodPickerOption = AnalyticsPeriodSelection & {
  id: string
  menuLabel: string
  hint: string
}

type AnalyticsPeriodDefinition = {
  id: string
  value: AnalyticsPeriod
  intervals: readonly AnalyticsGraphInterval[]
  buttonLabel?: string
  menuLabel?: string
  hint?: string
  setDate?: "current" | "last"
  pickerGroup?: number
  visibleInPicker?: boolean
}

const PERIOD_DEFINITIONS: readonly AnalyticsPeriodDefinition[] = [
  {
    id: "today",
    value: "day",
    intervals: ["minute", "hour"],
    menuLabel: "Today",
    hint: "D",
    setDate: "current",
    pickerGroup: 0,
  },
  {
    id: "yesterday",
    value: "day",
    intervals: ["minute", "hour"],
    menuLabel: "Yesterday",
    hint: "E",
    setDate: "last",
    pickerGroup: 0,
  },
  {
    id: "realtime",
    value: "realtime",
    buttonLabel: "Realtime (30m)",
    intervals: ["minute"],
    menuLabel: "Realtime",
    hint: "R",
    pickerGroup: 0,
  },
  {
    id: "last-24-hours",
    value: "24h",
    buttonLabel: "Last 24 Hours",
    intervals: ["minute", "hour"],
    menuLabel: "Last 24 Hours",
    hint: "H",
    pickerGroup: 1,
  },
  {
    id: "last-7-days",
    value: "7d",
    buttonLabel: "Last 7 days",
    intervals: ["hour", "day"],
    menuLabel: "Last 7 Days",
    hint: "W",
    pickerGroup: 1,
  },
  {
    id: "last-28-days",
    value: "28d",
    buttonLabel: "Last 28 days",
    intervals: ["day", "week"],
    menuLabel: "Last 28 Days",
    hint: "F",
    pickerGroup: 1,
  },
  {
    id: "last-91-days",
    value: "91d",
    buttonLabel: "Last 91 days",
    intervals: ["day", "week", "month"],
    menuLabel: "Last 91 Days",
    hint: "N",
    pickerGroup: 1,
  },
  {
    id: "month-to-date",
    value: "month",
    intervals: ["day", "week"],
    menuLabel: "Month to Date",
    hint: "M",
    setDate: "current",
    pickerGroup: 2,
  },
  {
    id: "last-month",
    value: "month",
    intervals: ["day", "week"],
    menuLabel: "Last Month",
    hint: "P",
    setDate: "last",
    pickerGroup: 2,
  },
  {
    id: "year-to-date",
    value: "year",
    intervals: ["day", "week", "month"],
    menuLabel: "Year to Date",
    hint: "Y",
    setDate: "current",
    pickerGroup: 3,
  },
  {
    id: "last-6-months",
    value: "6mo",
    buttonLabel: "Last 6 Months",
    intervals: ["day", "week", "month"],
    menuLabel: "Last 6 Months",
    hint: "S",
    pickerGroup: 3,
    visibleInPicker: false,
  },
  {
    id: "last-12-months",
    value: "12mo",
    buttonLabel: "Last 12 Months",
    intervals: ["day", "week", "month"],
    menuLabel: "Last 12 Months",
    hint: "L",
    pickerGroup: 3,
  },
  {
    id: "all-time",
    value: "all",
    buttonLabel: "All time",
    intervals: ["day", "week", "month"],
    menuLabel: "All time",
    hint: "A",
    pickerGroup: 4,
  },
  {
    id: "custom",
    value: "custom",
    intervals: ["day", "week", "month"],
    visibleInPicker: false,
  },
]

const CANONICAL_PERIODS = new Set<AnalyticsPeriod>(
  PERIOD_DEFINITIONS.map((definition) => definition.value)
)

const PERIOD_METADATA = PERIOD_DEFINITIONS.reduce<
  Partial<
    Record<
      AnalyticsPeriod,
      {
        buttonLabel?: string
        intervals: readonly AnalyticsGraphInterval[]
      }
    >
  >
>((definitionsByPeriod, definition) => {
  if (definitionsByPeriod[definition.value]) return definitionsByPeriod
  definitionsByPeriod[definition.value] = {
    buttonLabel: definition.buttonLabel,
    intervals: definition.intervals,
  }
  return definitionsByPeriod
}, {}) as Record<
  AnalyticsPeriod,
  {
    buttonLabel?: string
    intervals: readonly AnalyticsGraphInterval[]
  }
>

export const ANALYTICS_PERIOD_SHORTCUTS = PERIOD_DEFINITIONS.reduce<
  Record<string, AnalyticsPeriodSelection>
>((shortcutMap, definition) => {
  if (!definition.hint) return shortcutMap
  shortcutMap[definition.hint] = {
    value: definition.value,
    ...(definition.setDate ? { setDate: definition.setDate } : {}),
  }
  return shortcutMap
}, {})

export function getAnalyticsPeriodPickerGroups(
  activePeriod?: string | null
): readonly AnalyticsPeriodPickerOption[][] {
  const normalizedActivePeriod = canonicalAnalyticsPeriod(activePeriod)
  const groups = new Map<number, AnalyticsPeriodPickerOption[]>()

  for (const definition of PERIOD_DEFINITIONS) {
    if (
      typeof definition.pickerGroup !== "number" ||
      !definition.menuLabel ||
      !definition.hint
    ) {
      continue
    }
    const visible =
      definition.visibleInPicker !== false ||
      definition.value === normalizedActivePeriod
    if (!visible) continue

    const group = groups.get(definition.pickerGroup) ?? []
    group.push({
      id: definition.id,
      value: definition.value,
      setDate: definition.setDate,
      menuLabel: definition.menuLabel,
      hint: definition.hint,
    })
    groups.set(definition.pickerGroup, group)
  }

  return [...groups.entries()]
    .sort(([leftGroup], [rightGroup]) => leftGroup - rightGroup)
    .map(([, group]) => group)
}

export function canonicalAnalyticsPeriod(
  period: string | null | undefined
): AnalyticsPeriod | null {
  if (!period) return null

  if (!CANONICAL_PERIODS.has(period as AnalyticsPeriod)) return null

  return period as AnalyticsPeriod
}

export function normalizeAnalyticsPeriod(
  period: string | null | undefined,
  fallback: AnalyticsPeriod = "day"
): AnalyticsPeriod {
  return canonicalAnalyticsPeriod(period) ?? fallback
}

export function getAnalyticsPeriodButtonLabel(
  period: string | null | undefined
): string | null {
  const normalized = canonicalAnalyticsPeriod(period)
  if (!normalized) return null
  return PERIOD_METADATA[normalized].buttonLabel ?? null
}

export function getAnalyticsPeriodIntervals(
  period: string | null | undefined
): readonly AnalyticsGraphInterval[] {
  return PERIOD_METADATA[normalizeAnalyticsPeriod(period)].intervals
}
