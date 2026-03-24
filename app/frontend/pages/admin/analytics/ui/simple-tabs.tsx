import { createContext, useContext, type ReactNode } from "react"

const TabsContext = createContext<{
  value: string
  onChange: (value: string) => void
} | null>(null)

type TabsProps = {
  value: string
  onValueChange: (value: string) => void
  children: ReactNode
}

export function Tabs({ value, onValueChange, children }: TabsProps) {
  return (
    <TabsContext.Provider value={{ value, onChange: onValueChange }}>
      {children}
    </TabsContext.Provider>
  )
}

type TabsListProps = {
  children: ReactNode
  className?: string
}

export function TabsList({ children, className }: TabsListProps) {
  return (
    <div
      className={[
        "inline-flex items-center rounded-full border bg-muted/60 p-1",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {children}
    </div>
  )
}

type TabsTriggerProps = {
  value: string
  children: ReactNode
  className?: string
}

export function TabsTrigger({ value, children, className }: TabsTriggerProps) {
  const context = useContext(TabsContext)
  if (!context) {
    throw new Error("TabsTrigger must be used within Tabs")
  }
  const isActive = context.value === value
  return (
    <button
      type="button"
      onClick={() => context.onChange(value)}
      className={[
        "rounded-full px-3 py-1 text-xs font-medium transition",
        isActive
          ? "bg-primary text-primary-foreground"
          : "text-muted-foreground hover:bg-background",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {children}
    </button>
  )
}
