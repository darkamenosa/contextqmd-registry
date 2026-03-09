import { useCallback, useState, type ReactNode } from "react"
import { Link } from "@inertiajs/react"

import {
  SaveBarContext,
  useSaveBar,
  type SaveBarState,
} from "@/hooks/admin/use-save-bar"
import { Button } from "@/components/ui/button"

const defaultState: SaveBarState = {
  isDirty: false,
  isProcessing: false,
}

export function SaveBarProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SaveBarState>(defaultState)

  const setSaveBar = useCallback(
    (updates: Partial<SaveBarState>) =>
      setState((prev) => ({ ...prev, ...updates })),
    []
  )

  const resetSaveBar = useCallback(() => setState(defaultState), [])

  return (
    <SaveBarContext.Provider value={{ ...state, setSaveBar, resetSaveBar }}>
      {children}
    </SaveBarContext.Provider>
  )
}

export function HeaderSaveBar() {
  const {
    isDirty,
    isProcessing,
    resourceName,
    onSave,
    onDiscard,
    discardHref,
    saveLabel = "Save",
    processingLabel = "Saving...",
  } = useSaveBar()

  if (!isDirty) return null

  return (
    <div className="flex items-center gap-2">
      <span className="text-sm text-muted-foreground">
        Unsaved {resourceName ?? "changes"}
      </span>
      {discardHref ? (
        <Button
          variant="ghost"
          size="sm"
          nativeButton={false}
          render={<Link href={discardHref} />}
        >
          Discard
        </Button>
      ) : (
        <Button variant="ghost" size="sm" onClick={onDiscard}>
          Discard
        </Button>
      )}
      <Button size="sm" onClick={onSave} disabled={!isDirty || isProcessing}>
        {isProcessing ? processingLabel : saveLabel}
      </Button>
    </div>
  )
}

export function BottomSaveBar() {
  const {
    isDirty,
    isProcessing,
    onSave,
    onDiscard,
    discardHref,
    saveLabel = "Save",
    processingLabel = "Saving...",
  } = useSaveBar()

  if (!isDirty) return null

  return (
    <div className="flex items-center justify-end gap-2 border-t pt-4">
      {discardHref ? (
        <Button
          variant="outline"
          nativeButton={false}
          render={<Link href={discardHref} />}
        >
          Discard
        </Button>
      ) : (
        <Button variant="outline" onClick={onDiscard}>
          Discard
        </Button>
      )}
      <Button onClick={onSave} disabled={!isDirty || isProcessing}>
        {isProcessing ? processingLabel : saveLabel}
      </Button>
    </div>
  )
}
