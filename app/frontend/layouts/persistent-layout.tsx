import { type ReactNode } from "react"
import { Toaster } from "sonner"

import { useFlash } from "@/hooks/use-flash"
import { TooltipProvider } from "@/components/ui/tooltip"

interface PersistentLayoutProps {
  children: ReactNode
}

export default function PersistentLayout({ children }: PersistentLayoutProps) {
  useFlash()

  return (
    <TooltipProvider>
      {children}
      <Toaster
        position="bottom-center"
        toastOptions={{
          style: {
            background: "#1a1a1a",
            color: "#ffffff",
            border: "none",
            borderRadius: "8px",
            fontSize: "14px",
            padding: "12px 16px",
            boxShadow: "0 4px 12px rgba(0, 0, 0, 0.15)",
          },
        }}
      />
    </TooltipProvider>
  )
}
