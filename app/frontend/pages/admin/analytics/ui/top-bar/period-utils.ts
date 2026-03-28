import type { AnalyticsQuery } from "../../types"

export function getPeriodDisplay(query: AnalyticsQuery) {
  const pad = (value: number) => String(value).padStart(2, "0")
  const ymd = (date: Date) =>
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  const monthLabel = (dateString?: string | null) => {
    if (!dateString) return "Month to Date"
    const [year, month] = String(dateString).split("-")
    const monthNames = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ]
    const now = new Date()
    if (
      Number(year) === now.getFullYear() &&
      Number(month) === now.getMonth() + 1
    ) {
      return "Month to Date"
    }
    return `${monthNames[Math.max(0, Math.min(11, Number(month) - 1))]} ${year}`
  }
  const yearLabel = (dateString?: string | null) => {
    if (!dateString) return "Year to Date"
    const year = String(dateString).slice(0, 4)
    const now = new Date()
    if (Number(year) === now.getFullYear()) return "Year to Date"
    return year
  }

  switch (query.period) {
    case "realtime":
      return "Realtime (30m)"
    case "day": {
      const now = new Date()
      if (!query.date) return "Today"
      const yesterday = new Date(now)
      yesterday.setDate(now.getDate() - 1)
      if (query.date === ymd(now)) return "Today"
      if (query.date === ymd(yesterday)) return "Yesterday"
      return query.date
    }
    case "7d":
      return "Last 7 days"
    case "28d":
      return "Last 28 days"
    case "30d":
      return "Last 30 days"
    case "91d":
      return "Last 91 days"
    case "month":
      return monthLabel(query.date)
    case "year":
      return yearLabel(query.date)
    case "12mo":
      return "Last 12 Months"
    case "all":
      return "All time"
    case "custom": {
      const from = query.from as string | undefined
      const to = query.to as string | undefined
      if (!from || !to) return "Custom range"

      const fromDate = new Date(String(from).slice(0, 10))
      const toDate = new Date(String(to).slice(0, 10))
      const monthNames = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ]
      const fromMonth = monthNames[fromDate.getMonth()]
      const toMonth = monthNames[toDate.getMonth()]
      const fromDay = fromDate.getDate()
      const toDay = toDate.getDate()
      const fromYear = fromDate.getFullYear()
      const toYear = toDate.getFullYear()

      if (fromYear === toYear) {
        if (fromMonth === toMonth) {
          return `${fromMonth} ${fromDay}–${toDay}, ${fromYear}`
        }
        return `${fromMonth} ${fromDay}–${toMonth} ${toDay}, ${fromYear}`
      }
      return `${fromMonth} ${fromDay}, ${fromYear}–${toMonth} ${toDay}, ${toYear}`
    }
    default:
      return "Period"
  }
}

export function getComparisonLabel(query: AnalyticsQuery) {
  if (!query.comparison) return "Compare"
  if (query.comparison === "previous_period") return "Previous period"
  if (query.comparison === "year_over_year") return "Year over year"
  if (query.comparison === "custom" && query.compareFrom && query.compareTo) {
    const from = String(query.compareFrom).slice(0, 10)
    const to = String(query.compareTo).slice(0, 10)
    const fromDate = new Date(from)
    const toDate = new Date(to)
    const monthNames = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ]
    const fromMonth = monthNames[fromDate.getMonth()]
    const toMonth = monthNames[toDate.getMonth()]
    const fromDay = fromDate.getDate()
    const toDay = toDate.getDate()
    const fromYear = fromDate.getFullYear()
    const toYear = toDate.getFullYear()

    if (fromYear === toYear) {
      if (fromMonth === toMonth) {
        return `${fromMonth} ${fromDay}–${toDay}, ${fromYear}`
      }
      return `${fromMonth} ${fromDay}–${toMonth} ${toDay}, ${fromYear}`
    }
    return `${fromMonth} ${fromDay}, ${fromYear}–${toMonth} ${toDay}, ${toYear}`
  }
  return "Compare"
}

export function isActiveDay(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "day") return false
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, "0")
  const ymd = (date: Date) =>
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  if (mode === "current") {
    return !query.date || query.date === ymd(now)
  }
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  return query.date === ymd(yesterday)
}

export function isActiveMonth(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "month") return false
  const now = new Date()
  const target = new Date(now)
  if (mode === "last") target.setMonth(target.getMonth() - 1)
  const year = target.getFullYear()
  const month = target.getMonth() + 1
  if (!query.date) return mode === "current"
  const [queryYear, queryMonth] = String(query.date)
    .split("-")
    .map((value) => Number(value))
  return queryYear === year && queryMonth === month
}

export function isActiveYear(query: AnalyticsQuery, mode: "current" | "last") {
  if (query.period !== "year") return false
  const now = new Date()
  const year = mode === "last" ? now.getFullYear() - 1 : now.getFullYear()
  if (!query.date) return mode === "current"
  return Number(String(query.date).slice(0, 4)) === year
}

export function applyPeriodSelection(
  current: AnalyticsQuery,
  option: { value: AnalyticsQuery["period"]; setDate?: "current" | "last" }
) {
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, "0")
  const ymd = (date: Date) =>
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  const setMonthDate = (mode: "current" | "last") => {
    const date = new Date(now)
    if (mode === "last") {
      date.setMonth(date.getMonth() - 1)
    }
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-01`
  }
  const setYearDate = (mode: "current" | "last") => {
    const year = mode === "last" ? now.getFullYear() - 1 : now.getFullYear()
    return `${year}-01-01`
  }

  const next: AnalyticsQuery = {
    ...current,
    period: option.value,
    from: null,
    to: null,
  }
  if (option.value === "day" && option.setDate === "last") {
    const yesterday = new Date(now)
    yesterday.setDate(now.getDate() - 1)
    next.date = ymd(yesterday)
    return next
  }
  if (option.value === "month") {
    next.date = setMonthDate(option.setDate ?? "current")
    return next
  }
  if (option.value === "year") {
    next.date = setYearDate(option.setDate ?? "current")
    return next
  }
  next.date = null
  return next
}
