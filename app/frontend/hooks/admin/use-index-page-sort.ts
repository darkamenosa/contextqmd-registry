import { useMemo, useState } from "react"

type SortDirection = "asc" | "desc"

interface UseIndexPageSortOptions<T> {
  items: T[]
  defaultColumn?: string
  defaultDirection?: SortDirection
  getSortValue: (item: T, columnId: string) => string | number
}

interface UseIndexPageSortReturn<T> {
  sortedItems: T[]
  sortColumn: string
  sortDirection: SortDirection
  sortSelected: string[]
  handleSortChange: (selected: string[]) => void
  handleColumnSort: (columnId: string, direction: SortDirection) => void
}

export function useIndexPageSort<T>({
  items,
  defaultColumn = "",
  defaultDirection = "asc",
  getSortValue,
}: UseIndexPageSortOptions<T>): UseIndexPageSortReturn<T> {
  const [sortColumn, setSortColumn] = useState(defaultColumn)
  const [sortDirection, setSortDirection] =
    useState<SortDirection>(defaultDirection)

  const sortSelected = sortColumn ? [`${sortColumn}-${sortDirection}`] : []

  const handleSortChange = (selected: string[]) => {
    if (selected.length === 0) {
      setSortColumn("")
      setSortDirection("asc")
      return
    }
    const value = selected[0]
    const lastDash = value.lastIndexOf("-")
    setSortColumn(value.slice(0, lastDash))
    setSortDirection(value.slice(lastDash + 1) as SortDirection)
  }

  const handleColumnSort = (columnId: string, direction: SortDirection) => {
    setSortColumn(columnId)
    setSortDirection(direction)
  }

  const sortedItems = useMemo(() => {
    if (!sortColumn) return items
    return [...items].sort((a, b) => {
      const aVal = getSortValue(a, sortColumn)
      const bVal = getSortValue(b, sortColumn)
      const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0
      return sortDirection === "asc" ? cmp : -cmp
    })
  }, [items, sortColumn, sortDirection, getSortValue])

  return {
    sortedItems,
    sortColumn,
    sortDirection,
    sortSelected,
    handleSortChange,
    handleColumnSort,
  }
}
