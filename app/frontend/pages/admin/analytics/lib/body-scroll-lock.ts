const LOCK_COUNT_KEY = "analyticsScrollLockCount"
const LOCK_PREVIOUS_OVERFLOW_KEY = "analyticsPreviousOverflow"

function readLockCount(body: HTMLElement) {
  const rawCount = body.dataset[LOCK_COUNT_KEY]
  const count = rawCount ? Number(rawCount) : 0
  return Number.isFinite(count) ? count : 0
}

export function lockBodyScroll() {
  if (typeof document === "undefined") {
    return () => {}
  }

  const body = document.body
  const currentCount = readLockCount(body)

  if (currentCount === 0) {
    const currentOverflow = body.style.overflow
    body.dataset[LOCK_PREVIOUS_OVERFLOW_KEY] =
      currentOverflow === "hidden" ? "" : currentOverflow
  }

  body.dataset[LOCK_COUNT_KEY] = String(currentCount + 1)
  body.style.overflow = "hidden"

  let released = false

  return () => {
    if (released) return
    released = true

    const nextCount = Math.max(0, readLockCount(body) - 1)

    if (nextCount === 0) {
      body.style.overflow = body.dataset[LOCK_PREVIOUS_OVERFLOW_KEY] ?? ""
      delete body.dataset[LOCK_COUNT_KEY]
      delete body.dataset[LOCK_PREVIOUS_OVERFLOW_KEY]
      return
    }

    body.dataset[LOCK_COUNT_KEY] = String(nextCount)
  }
}
