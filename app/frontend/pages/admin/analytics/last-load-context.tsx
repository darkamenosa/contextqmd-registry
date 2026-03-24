import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react"

export type LastLoadContextValue = {
  lastLoadedAt: number
  touch: () => void
}

const LastLoadContext = createContext<LastLoadContextValue | null>(null)

export function LastLoadProvider({ children }: { children: ReactNode }) {
  const [lastLoadedAt, setLastLoadedAt] = useState(() => Date.now())

  const touch = useCallback(() => setLastLoadedAt(Date.now()), [])

  const value = useMemo<LastLoadContextValue>(
    () => ({ lastLoadedAt, touch }),
    [lastLoadedAt, touch]
  )

  return (
    <LastLoadContext.Provider value={value}>
      {children}
    </LastLoadContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useLastLoadContext() {
  const context = useContext(LastLoadContext)
  if (!context) {
    throw new Error("useLastLoadContext must be used within a LastLoadProvider")
  }
  return context
}
