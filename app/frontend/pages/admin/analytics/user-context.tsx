import { createContext, useContext, type ReactNode } from "react"

import type { UserContextValue } from "./types"

const UserContext = createContext<UserContextValue | null>(null)

export function UserProvider({
  value,
  children,
}: {
  value: UserContextValue
  children: ReactNode
}) {
  return <UserContext.Provider value={value}>{children}</UserContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useUserContext() {
  const context = useContext(UserContext)
  if (!context) {
    throw new Error("useUserContext must be used within a UserProvider")
  }
  return context
}
