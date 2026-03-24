import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react"

import type { TopStatsPayload } from "./types"

export type TopStatsContextValue = {
  payload: TopStatsPayload
  update: (payload: TopStatsPayload) => void
}

const TopStatsContext = createContext<TopStatsContextValue | null>(null)

export function TopStatsProvider({
  initial,
  children,
}: {
  initial: TopStatsPayload
  children: ReactNode
}) {
  const [payload, setPayload] = useState<TopStatsPayload>(initial)

  const value = useMemo(
    () => ({
      payload,
      update: setPayload,
    }),
    [payload]
  )

  return (
    <TopStatsContext.Provider value={value}>
      {children}
    </TopStatsContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useTopStatsContext() {
  const context = useContext(TopStatsContext)
  if (!context) {
    throw new Error("useTopStatsContext must be used within a TopStatsProvider")
  }
  return context
}
