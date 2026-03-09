import { useState } from "react"

import type { IndexFiltersMode } from "@/components/admin/ui/index-table"

export function useSetIndexFiltersMode(
  initialMode: IndexFiltersMode = "default"
) {
  const [mode, setMode] = useState<IndexFiltersMode>(initialMode)
  return { mode, setMode }
}
