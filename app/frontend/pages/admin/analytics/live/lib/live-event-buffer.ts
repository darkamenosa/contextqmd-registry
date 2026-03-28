function eventTime(value: string) {
  const time = new Date(value).getTime()
  return Number.isFinite(time) ? time : Number.POSITIVE_INFINITY
}

export function sortEventsAsc<T extends { occurredAt: string }>(events: T[]) {
  return [...events].sort(
    (a, b) => eventTime(a.occurredAt) - eventTime(b.occurredAt)
  )
}
