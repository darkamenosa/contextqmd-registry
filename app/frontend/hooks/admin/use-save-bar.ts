import { createContext, useContext } from "react"

export interface SaveBarState {
  isDirty: boolean
  isProcessing: boolean
  resourceName?: string
  onSave?: () => void
  onDiscard?: () => void
  discardHref?: string
  saveLabel?: string
  processingLabel?: string
}

export interface SaveBarContextType extends SaveBarState {
  setSaveBar: (state: Partial<SaveBarState>) => void
  resetSaveBar: () => void
}

export const SaveBarContext = createContext<SaveBarContextType | null>(null)

export function useSaveBar() {
  const context = useContext(SaveBarContext)
  if (!context) {
    throw new Error("useSaveBar must be used within a SaveBarProvider")
  }
  return context
}
