import { createContext, useContext, type ReactNode } from "react"

import type { SiteContextValue } from "./types"

const SiteContext = createContext<SiteContextValue | null>(null)

export function SiteProvider({
  value,
  children,
}: {
  value: SiteContextValue
  children: ReactNode
}) {
  return <SiteContext.Provider value={value}>{children}</SiteContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useSiteContext() {
  const context = useContext(SiteContext)
  if (!context) {
    throw new Error("useSiteContext must be used within a SiteProvider")
  }
  return context
}
