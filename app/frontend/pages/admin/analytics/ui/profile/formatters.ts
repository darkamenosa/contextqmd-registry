type LocationOrder = "city-first" | "country-first"

type LocationFields = {
  city?: string | null
  region?: string | null
  country?: string | null
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
  if (seconds <= 0) return "0m"

  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  const secs = seconds % 60

  if (hrs > 0) return `${hrs}h ${mins}m`
  if (mins > 0) return `${mins}m ${secs}s`
  return `${secs}s`
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
