type LocationOrder = "city-first" | "country-first"
type CompactLocationOptions = {
  flagShown?: boolean
  appendCountryCode?: boolean
}

type LocationFields = {
  city?: string | null
  region?: string | null
  country?: string | null
  countryCode?: string | null
}

const REGION_ABBREVIATIONS: Record<string, Record<string, string>> = {
  US: {
    Alabama: "AL",
    Alaska: "AK",
    Arizona: "AZ",
    Arkansas: "AR",
    California: "CA",
    Colorado: "CO",
    Connecticut: "CT",
    Delaware: "DE",
    Florida: "FL",
    Georgia: "GA",
    Hawaii: "HI",
    Idaho: "ID",
    Illinois: "IL",
    Indiana: "IN",
    Iowa: "IA",
    Kansas: "KS",
    Kentucky: "KY",
    Louisiana: "LA",
    Maine: "ME",
    Maryland: "MD",
    Massachusetts: "MA",
    Michigan: "MI",
    Minnesota: "MN",
    Mississippi: "MS",
    Missouri: "MO",
    Montana: "MT",
    Nebraska: "NE",
    Nevada: "NV",
    "New Hampshire": "NH",
    "New Jersey": "NJ",
    "New Mexico": "NM",
    "New York": "NY",
    "North Carolina": "NC",
    "North Dakota": "ND",
    Ohio: "OH",
    Oklahoma: "OK",
    Oregon: "OR",
    Pennsylvania: "PA",
    "Rhode Island": "RI",
    "South Carolina": "SC",
    "South Dakota": "SD",
    Tennessee: "TN",
    Texas: "TX",
    Utah: "UT",
    Vermont: "VT",
    Virginia: "VA",
    Washington: "WA",
    "West Virginia": "WV",
    Wisconsin: "WI",
    Wyoming: "WY",
    "District of Columbia": "DC",
  },
  CA: {
    Alberta: "AB",
    "British Columbia": "BC",
    Manitoba: "MB",
    "New Brunswick": "NB",
    "Newfoundland and Labrador": "NL",
    "Nova Scotia": "NS",
    Ontario: "ON",
    "Prince Edward Island": "PE",
    Quebec: "QC",
    Saskatchewan: "SK",
  },
  AU: {
    "New South Wales": "NSW",
    Queensland: "QLD",
    "South Australia": "SA",
    Tasmania: "TAS",
    Victoria: "VIC",
    "Western Australia": "WA",
    "Australian Capital Territory": "ACT",
    "Northern Territory": "NT",
  },
}

function abbreviateRegion(region?: string | null, countryCode?: string | null) {
  const normalizedRegion = region?.trim()
  if (!normalizedRegion) return null

  const code = countryCode?.trim().toUpperCase()
  const abbreviations = code ? REGION_ABBREVIATIONS[code] : null
  return abbreviations?.[normalizedRegion] || null
}

export function maskEmail(email: string): string {
  const [local, domain] = email.split("@")
  if (!domain) return "******@*****.com"
  const maskedLocal = local[0] + "*".repeat(Math.max(local.length - 1, 4))
  const parts = domain.split(".")
  const maskedDomain =
    parts[0][0] + "*".repeat(Math.max(parts[0].length - 1, 4))
  return `${maskedLocal}@${maskedDomain}.${parts.slice(1).join(".")}`
}

export function formatProfileDuration(seconds: number): string {
  if (seconds <= 0) return "0s"

  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  const secs = seconds % 60

  if (hrs > 0) return `${hrs}h ${mins}m`
  if (mins > 0) return `${mins}m ${secs}s`
  return `${secs}s`
}

export function formatProfileSessionDuration(seconds?: number | null): string {
  const duration = Math.max(seconds ?? 0, 0)
  if (duration > 0) return formatProfileDuration(duration)

  return "Single hit"
}

export function formatProfileEngagedTime(
  engagedMsTotal?: number | null
): string | null {
  const engagedMs = Math.max(engagedMsTotal ?? 0, 0)
  if (engagedMs > 0 && engagedMs < 1000) return "<1s"
  if (engagedMs >= 1000) {
    return formatProfileDuration(Math.floor(engagedMs / 1000))
  }

  return null
}

const compactNumberFormatter = new Intl.NumberFormat("en-US", {
  notation: "compact",
})

export function formatCompactNumber(value: number | undefined | null) {
  return compactNumberFormatter.format(value ?? 0)
}

export function formatProfileLocation(
  fields: LocationFields,
  order: LocationOrder = "city-first"
) {
  const city = fields.city?.trim()
  const region = fields.region?.trim()
  const country = fields.country?.trim()
  const parts =
    order === "country-first"
      ? [country, region, city]
      : [city, region, country]

  const uniqueParts: string[] = []

  for (const part of parts) {
    if (!part) continue
    if (
      uniqueParts.some(
        (existing) => existing.toLocaleLowerCase() === part.toLocaleLowerCase()
      )
    ) {
      continue
    }
    uniqueParts.push(part)
  }

  return uniqueParts.join(", ")
}

export function formatCompactLocation(
  fields: LocationFields,
  options: CompactLocationOptions = {}
) {
  const city = fields.city?.trim()
  const region = fields.region?.trim()
  const country = fields.country?.trim()
  const countryCode = fields.countryCode?.trim().toUpperCase()
  const flagShown = options.flagShown === true
  const appendCountryCode = options.appendCountryCode === true

  const shortCountry = countryCode || country || null
  const shortRegion = abbreviateRegion(region, countryCode)
  const distinctRegion =
    region && (!city || region.toLocaleLowerCase() !== city.toLocaleLowerCase())
      ? region
      : null

  if (city) {
    const suffix =
      shortRegion ||
      (distinctRegion && distinctRegion.length <= 16 ? distinctRegion : null) ||
      (!flagShown ? shortCountry : null)

    const parts = [city, suffix].filter(Boolean)
    if (appendCountryCode && countryCode && suffix !== countryCode) {
      parts.push(countryCode)
    }

    return parts.join(", ")
  }

  if (distinctRegion) {
    const suffix = !flagShown ? shortCountry : null
    const parts = [distinctRegion, suffix].filter(Boolean)
    if (appendCountryCode && countryCode && suffix !== countryCode) {
      parts.push(countryCode)
    }

    return parts.join(", ")
  }

  return countryCode || shortCountry || ""
}
