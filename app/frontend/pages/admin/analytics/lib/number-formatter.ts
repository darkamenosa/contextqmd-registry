// Number formatting utilities following Plausible's exact implementation
// Source: plausible/assets/js/dashboard/util/number-formatter.ts

const THOUSAND = 1000
const HUNDRED_THOUSAND = 100000
const MILLION = 1000000
const HUNDRED_MILLION = 100000000
const BILLION = 1000000000
const HUNDRED_BILLION = 100000000000
const TRILLION = 1000000000000

const numberFormat = Intl.NumberFormat("en-US")

/**
 * Formats numbers in short form with k/M/B suffixes.
 * Examples: 1234 → "1.2k", 1234567 → "1.2M"
 */
export function numberShortFormatter(num: number): string {
  if (num >= THOUSAND && num < MILLION) {
    const thousands = num / THOUSAND
    if (thousands === Math.floor(thousands) || num >= HUNDRED_THOUSAND) {
      return Math.floor(thousands) + "k"
    } else {
      return Math.floor(thousands * 10) / 10 + "k"
    }
  } else if (num >= MILLION && num < BILLION) {
    const millions = num / MILLION
    if (millions === Math.floor(millions) || num >= HUNDRED_MILLION) {
      return Math.floor(millions) + "M"
    } else {
      return Math.floor(millions * 10) / 10 + "M"
    }
  } else if (num >= BILLION && num < TRILLION) {
    const billions = num / BILLION
    if (billions === Math.floor(billions) || num >= HUNDRED_BILLION) {
      return Math.floor(billions) + "B"
    } else {
      return Math.floor(billions * 10) / 10 + "B"
    }
  } else {
    return num.toString()
  }
}

/**
 * Formats numbers with thousand separators.
 * Examples: 1234 → "1,234", 1234567 → "1,234,567"
 */
export function numberLongFormatter(num: number): string {
  return numberFormat.format(num)
}

/**
 * Wraps a formatter to handle null and undefined values.
 * Returns "-" for null or undefined, otherwise applies the formatter.
 */
export function nullable<T>(
  formatter: (num: T) => string
): (num: T | null | undefined) => string {
  return (num: T | null | undefined): string => {
    if (num == null) {
      return "-"
    }
    return formatter(num)
  }
}

function pad(num: number, size: number): string {
  return ("000" + num).slice(size * -1)
}

/**
 * Formats duration in seconds to human-readable format.
 * Examples: 65 → "1m 05s", 3665 → "1h 1m 5s"
 */
export function durationFormatter(duration: number): string {
  const hours = Math.floor(duration / 60 / 60)
  const minutes = Math.floor(duration / 60) % 60
  const seconds = Math.floor(duration - minutes * 60 - hours * 60 * 60)
  if (hours > 0) {
    return `${hours}h ${minutes}m ${seconds}s`
  } else if (minutes > 0) {
    return `${minutes}m ${pad(seconds, 2)}s`
  } else {
    return `${seconds}s`
  }
}

/**
 * Formats percentage values.
 * Backend returns decimals (0.45), we convert to whole numbers (45%)
 * Example: 0.45 → "45%", 0.123 → "12.3%"
 */
export function percentageFormatter(value: number | null): string {
  if (value == null || Number.isNaN(value as number)) return "-"
  const num = Number(value)
  // Accept both decimal fractions (0.0645) and percent values (6.45)
  const pct = num <= 1 ? Math.round(num * 1000) / 10 : Math.round(num * 10) / 10
  return `${pct}%`
}
