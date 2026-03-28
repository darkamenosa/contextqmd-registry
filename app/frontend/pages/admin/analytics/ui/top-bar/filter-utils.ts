import type { AnalyticsQuery } from "../../types"

export const FILTER_PICKER_COLUMNS = [
  {
    title: "URL",
    items: [{ label: "Page", key: "page", value: "/dashboard" }],
  },
  {
    title: "Acquisition",
    items: [
      { label: "Source", key: "source", value: "" },
      { label: "UTM tags", key: "utm", value: "" },
    ],
  },
  {
    title: "Device",
    items: [
      { label: "Location", key: "location", value: "" },
      { label: "Screen size", key: "size", value: "" },
      { label: "Browser", key: "browser", value: "" },
      { label: "Browser version", key: "browser_version", value: "" },
      { label: "Operating System", key: "os", value: "" },
      { label: "OS version", key: "os_version", value: "" },
    ],
  },
  {
    title: "Behavior",
    items: [
      { label: "Goal", key: "goal", value: "" },
      { label: "Property", key: "property", value: "" },
    ],
  },
] as const

const FILTER_ORDER = [
  "page",
  "entry_page",
  "exit_page",
  "source",
  "channel",
  "referrer",
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "country",
  "region",
  "city",
  "browser",
  "browser_version",
  "os",
  "os_version",
  "goal",
  "prop",
  "segment",
]

export function filterLabel(key: string) {
  if (key.startsWith("prop:")) {
    return `Property ${key.slice("prop:".length)}`
  }

  switch (key) {
    case "hostname":
      return "Hostname"
    case "source":
      return "Source"
    case "channel":
      return "Channel"
    case "size":
      return "Screen Size"
    case "country":
      return "Country"
    case "region":
      return "Region"
    case "city":
      return "City"
    case "goal":
      return "Goal"
    case "segment":
      return "Segment"
    case "page":
      return "Page"
    case "browser":
      return "Browser"
    case "browser_version":
      return "Browser Version"
    case "os":
      return "Operating System"
    case "os_version":
      return "OS Version"
    case "utm_source":
      return "UTM Source"
    case "utm_medium":
      return "UTM Medium"
    case "utm_campaign":
      return "UTM Campaign"
    case "utm_content":
      return "UTM Content"
    case "utm_term":
      return "UTM Term"
    case "referrer":
      return "Referrer URL"
    case "entry_page":
      return "Entry Page"
    case "exit_page":
      return "Exit Page"
    case "prop":
      return "Property"
    default:
      return key
  }
}

export function filterOrderKey(key: string) {
  return key.startsWith("prop:") ? "prop" : key
}

export function getOrderedFilters(query: AnalyticsQuery) {
  const equalityFilters = Object.entries(query.filters)
    .slice()
    .sort(
      ([left], [right]) =>
        FILTER_ORDER.indexOf(filterOrderKey(left)) -
        FILTER_ORDER.indexOf(filterOrderKey(right))
    )
  const advancedFilters = (
    Array.isArray(query.advancedFilters) ? query.advancedFilters : []
  )
    .slice()
    .sort(
      (left, right) =>
        FILTER_ORDER.indexOf(filterOrderKey(left[1])) -
        FILTER_ORDER.indexOf(filterOrderKey(right[1]))
    )

  return { equalityFilters, advancedFilters }
}
