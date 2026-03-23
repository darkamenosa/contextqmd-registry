import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import { Link } from "@inertiajs/react"
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  MoreHorizontal,
  Search,
} from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"

// ============================================================================
// Types
// ============================================================================

export type IndexTableSelectionScope = "none" | "page" | "all"

type SortDirection = "asc" | "desc"

export type IndexTableColumn = {
  id: string
  label: ReactNode
  align?: "start" | "center" | "end"
  sortable?: boolean
  headerClassName?: string
  cellClassName?: string
  widthClassName?: string
}

export type IndexTableSort = {
  columnId: string
  direction: SortDirection
  onChange: (columnId: string, direction: SortDirection) => void
}

export type IndexTablePagination = {
  label: string
  hasPrevious?: boolean
  hasNext?: boolean
  onPrevious?: () => void
  onNext?: () => void
}

export type IndexTableActionItem = {
  key: string
  label: string
  destructive?: boolean
  onAction?: (
    selectedIds: Array<string | number>,
    scope: IndexTableSelectionScope
  ) => void
}

export type IndexTableBulkAction = {
  key: string
  label: string
  destructive?: boolean
  onAction?: (
    selectedIds: Array<string | number>,
    scope: IndexTableSelectionScope
  ) => void
  menu?: IndexTableActionItem[]
}

export type IndexFiltersMode = "default" | "filtering"

export type IndexFiltersTab = {
  id: string
  label: string
  href?: string
}

export type IndexFiltersSortOption = {
  label: string
  value: string
  directionLabel?: string
}

export type IndexFiltersProps = {
  tabs: IndexFiltersTab[]
  selected: number
  onSelect: (index: number) => void
  queryValue: string
  queryPlaceholder?: string
  onQueryChange: (value: string) => void
  onQueryClear?: () => void
  sortOptions?: IndexFiltersSortOption[]
  sortSelected?: string[]
  onSort?: (value: string[]) => void
  filters?: ReactNode
  mode: IndexFiltersMode
  setMode: (mode: IndexFiltersMode) => void
  onCancel?: () => void
  disabled?: boolean
}

export type IndexTableProps<T> = {
  items: T[]
  itemId: (item: T) => string | number
  columns: IndexTableColumn[]
  renderRow: (item: T) => ReactNode[]
  renderMobileCard?: (item: T) => ReactNode
  selectable?: boolean
  totalCount?: number
  bulkActions?: IndexTableBulkAction[]
  emptyState?: ReactNode
  sort?: IndexTableSort
  pagination?: IndexTablePagination
  onSelectionChange?: (
    selectedIds: Array<string | number>,
    scope: IndexTableSelectionScope
  ) => void
  showAllSelectedToggle?: boolean
}

// ============================================================================
// IndexFilters
// ============================================================================

export function IndexFilters({
  tabs,
  selected,
  onSelect,
  queryValue,
  queryPlaceholder = "Search",
  onQueryChange,
  onQueryClear,
  sortOptions,
  sortSelected,
  onSort,
  filters,
  mode,
  setMode,
  onCancel,
  disabled = false,
}: IndexFiltersProps) {
  const searchInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (mode === "filtering" && searchInputRef.current) {
      searchInputRef.current.focus()
    }
  }, [mode])

  const handleCancel = useCallback(() => {
    onCancel?.()
    onQueryClear?.()
    setMode("default")
  }, [onCancel, onQueryClear, setMode])

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      const tag = document.activeElement?.tagName
      if (tag && ["INPUT", "SELECT", "TEXTAREA"].includes(tag)) return
      if (event.key === "f" && mode === "default") {
        event.preventDefault()
        setMode("filtering")
      }
      if (event.key === "Escape" && mode === "filtering") {
        handleCancel()
      }
    }
    document.addEventListener("keydown", handleKeyDown)
    return () => document.removeEventListener("keydown", handleKeyDown)
  }, [mode, setMode, handleCancel])

  const sortButton = sortOptions &&
    sortOptions.length > 0 &&
    sortSelected &&
    onSort && (
      <SortDropdown
        options={sortOptions}
        selected={sortSelected}
        onChange={onSort}
        disabled={disabled}
      />
    )

  if (mode === "default") {
    return (
      <div className="flex items-center border-b border-border">
        <div className="flex min-w-0 flex-1 items-center overflow-x-auto px-1">
          <div className="flex items-center">
            {tabs.map((tab, index) => {
              const isActive = index === selected
              const tabClasses = cn(
                "px-3 py-2 text-xs font-medium whitespace-nowrap transition-colors",
                isActive
                  ? "border-b-2 border-foreground text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              )
              if (tab.href) {
                return (
                  <Link key={tab.id} href={tab.href} className={tabClasses}>
                    {tab.label}
                  </Link>
                )
              }
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => onSelect(index)}
                  disabled={disabled}
                  className={tabClasses}
                >
                  {tab.label}
                </button>
              )
            })}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-0.5 border-l border-border bg-card px-2">
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            onClick={() => setMode("filtering")}
            disabled={disabled}
          >
            <Search className="size-4" />
            <span className="sr-only">Search</span>
          </Button>
          {sortButton}
        </div>
      </div>
    )
  }

  // Filtering mode
  return (
    <div className="border-b border-border">
      <div className="flex items-center gap-2 px-3 py-2">
        <div className="relative flex-1">
          <Search className="absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            ref={searchInputRef}
            value={queryValue ?? ""}
            onChange={(e) => onQueryChange(e.target.value)}
            placeholder={queryPlaceholder}
            disabled={disabled}
            className="h-8 pl-8"
          />
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleCancel}
          disabled={disabled}
        >
          Cancel
        </Button>
        {sortButton}
      </div>
      {filters && (
        <div className="flex flex-wrap items-center gap-1 px-3 pb-2">
          {filters}
        </div>
      )}
    </div>
  )
}

// ============================================================================
// SortDropdown
// ============================================================================

function SortDropdown({
  options,
  selected,
  onChange,
  disabled = false,
}: {
  options: IndexFiltersSortOption[]
  selected: string[]
  onChange: (value: string[]) => void
  disabled?: boolean
}) {
  const selectedValue = selected[0] || ""

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            disabled={disabled}
          />
        }
      >
        <ArrowUpDown className="size-4" />
        <span className="sr-only">Sort</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="text-xs">Sort by</DropdownMenuLabel>
          {options.map((option) => (
            <DropdownMenuItem
              key={option.value}
              onClick={() => onChange([option.value])}
              className="flex items-center justify-between"
            >
              <span>{option.label}</span>
              <span className="flex items-center gap-1 text-muted-foreground">
                {option.directionLabel && (
                  <span className="text-xs">{option.directionLabel}</span>
                )}
                {selectedValue === option.value && (
                  <Check className="size-3.5" />
                )}
              </span>
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

// ============================================================================
// IndexTable
// ============================================================================

export function IndexTable<T>({
  items,
  itemId,
  columns,
  renderRow,
  renderMobileCard,
  selectable = true,
  totalCount,
  bulkActions = [],
  emptyState,
  sort,
  pagination,
  onSelectionChange,
  showAllSelectedToggle = true,
}: IndexTableProps<T>) {
  const [selectedIds, setSelectedIds] = useState<Set<string | number>>(
    new Set()
  )
  const [selectionScope, setSelectionScope] =
    useState<IndexTableSelectionScope>("none")
  const [showAllSelected, setShowAllSelected] = useState(false)

  useEffect(() => {
    onSelectionChange?.(Array.from(selectedIds), selectionScope)
  }, [selectedIds, selectionScope, onSelectionChange])

  const allSelected =
    items.length > 0 && items.every((item) => selectedIds.has(itemId(item)))
  const someSelected = items.some((item) => selectedIds.has(itemId(item)))
  const hasSelection = selectionScope === "all" || someSelected
  const selectedCount =
    selectionScope === "all" ? (totalCount ?? items.length) : selectedIds.size

  const toggleSelectAll = () => {
    if (allSelected) {
      setSelectedIds(new Set())
      setSelectionScope("none")
    } else {
      const next = new Set<string | number>()
      for (const item of items) next.add(itemId(item))
      setSelectedIds(next)
      setSelectionScope("page")
    }
  }

  const toggleRow = (id: string | number) => {
    setSelectionScope("page")
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      if (next.size === 0) setSelectionScope("none")
      return next
    })
  }

  const selectAll = () => {
    setSelectionScope("all")
    const next = new Set<string | number>()
    for (const item of items) next.add(itemId(item))
    setSelectedIds(next)
  }

  const deselectAll = () => {
    setSelectedIds(new Set())
    setSelectionScope("none")
  }

  const handleSortClick = (columnId: string) => {
    if (!sort) return
    const dir: SortDirection =
      sort.columnId === columnId && sort.direction === "asc" ? "desc" : "asc"
    sort.onChange(columnId, dir)
  }

  const renderSortIcon = (columnId: string) => {
    if (!sort) return null
    if (sort.columnId !== columnId) {
      return (
        <ArrowUpDown className="size-3 opacity-0 transition-opacity group-hover:opacity-50" />
      )
    }
    return sort.direction === "asc" ? (
      <ArrowUp className="size-3" />
    ) : (
      <ArrowDown className="size-3" />
    )
  }

  const selectionLabel =
    selectionScope === "all"
      ? `All ${totalCount ?? items.length} selected`
      : `${selectedCount} selected`

  const total = totalCount ?? items.length
  const visibleItems = items.filter((item) => {
    if (!showAllSelected) return true
    const id = itemId(item)
    return selectionScope === "all" || selectedIds.has(id)
  })

  // Separate "more-actions" from regular bulk actions
  const regularActions = bulkActions.filter(
    (a) => a.key !== "more" && a.key !== "more-actions"
  )
  const moreActions = bulkActions.filter(
    (a) => a.key === "more" || a.key === "more-actions"
  )

  return (
    <div className="overflow-hidden">
      {items.length === 0 && emptyState ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          {emptyState}
        </div>
      ) : (
        <>
          {renderMobileCard && (
            <div className="divide-y sm:hidden">
              {visibleItems.map((item) => (
                <div key={itemId(item)}>{renderMobileCard(item)}</div>
              ))}
            </div>
          )}

          <div
            className={cn(
              "overflow-x-auto",
              renderMobileCard && "hidden sm:block"
            )}
          >
            <table className="w-full text-left">
              <thead className="relative">
                {/* Bulk action bar — absolute overlay on top of header */}
                {hasSelection && (
                  <tr
                    className="pointer-events-none absolute inset-x-0 top-0 z-10 flex border-b border-border bg-muted/30"
                    aria-hidden="true"
                  >
                    <th
                      colSpan={selectable ? columns.length + 1 : columns.length}
                      className="pointer-events-auto flex-1 px-3 py-2 whitespace-nowrap"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="flex h-[18px] flex-wrap items-center gap-2">
                          {selectable && (
                            <Checkbox
                              checked={allSelected}
                              indeterminate={someSelected && !allSelected}
                              onCheckedChange={toggleSelectAll}
                              aria-label="Select all"
                              className="size-3.5"
                            />
                          )}

                          {/* Selection count dropdown */}
                          <DropdownMenu>
                            <DropdownMenuTrigger
                              render={
                                <button
                                  type="button"
                                  className="flex h-[18px] items-center gap-1 rounded-sm bg-muted/60 px-2 text-xs leading-none font-medium text-foreground hover:bg-muted"
                                />
                              }
                            >
                              {selectionLabel}
                              <ChevronDown className="size-3 text-muted-foreground" />
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="start">
                              <DropdownMenuItem onClick={selectAll}>
                                Select all {total}
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={deselectAll}>
                                Deselect all
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>

                          {/* Bulk action buttons */}
                          {regularActions.map((action) =>
                            action.menu && action.menu.length > 0 ? (
                              <DropdownMenu key={action.key}>
                                <DropdownMenuTrigger
                                  render={
                                    <button
                                      type="button"
                                      className={cn(
                                        "flex h-[18px] items-center gap-1 rounded-sm bg-muted/60 px-2 text-xs leading-none font-medium hover:bg-muted",
                                        action.destructive
                                          ? "text-destructive"
                                          : "text-foreground"
                                      )}
                                    />
                                  }
                                >
                                  {action.label}
                                  <ChevronDown className="size-3" />
                                </DropdownMenuTrigger>
                                <DropdownMenuContent align="start">
                                  {action.menu.map((item) => (
                                    <DropdownMenuItem
                                      key={item.key}
                                      className={
                                        item.destructive
                                          ? "text-destructive"
                                          : undefined
                                      }
                                      onClick={() =>
                                        item.onAction?.(
                                          Array.from(selectedIds),
                                          selectionScope
                                        )
                                      }
                                    >
                                      {item.label}
                                    </DropdownMenuItem>
                                  ))}
                                </DropdownMenuContent>
                              </DropdownMenu>
                            ) : (
                              <button
                                key={action.key}
                                type="button"
                                onClick={() =>
                                  action.onAction?.(
                                    Array.from(selectedIds),
                                    selectionScope
                                  )
                                }
                                className={cn(
                                  "h-[18px] rounded-sm bg-muted/60 px-2 text-xs leading-none font-medium hover:bg-muted",
                                  action.destructive
                                    ? "text-destructive"
                                    : "text-foreground"
                                )}
                              >
                                {action.label}
                              </button>
                            )
                          )}

                          {/* More actions */}
                          {moreActions.map((action) => (
                            <DropdownMenu key={action.key}>
                              <DropdownMenuTrigger
                                render={
                                  <button
                                    type="button"
                                    className="flex h-[18px] items-center rounded-sm bg-muted/60 px-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                    aria-label="More actions"
                                  />
                                }
                              >
                                <MoreHorizontal className="size-3.5" />
                              </DropdownMenuTrigger>
                              <DropdownMenuContent align="end">
                                {action.menu?.map((item) => (
                                  <DropdownMenuItem
                                    key={item.key}
                                    className={
                                      item.destructive
                                        ? "text-destructive"
                                        : undefined
                                    }
                                    onClick={() =>
                                      item.onAction?.(
                                        Array.from(selectedIds),
                                        selectionScope
                                      )
                                    }
                                  >
                                    {item.label}
                                  </DropdownMenuItem>
                                ))}
                              </DropdownMenuContent>
                            </DropdownMenu>
                          ))}
                        </div>

                        {/* Show all selected toggle */}
                        {showAllSelectedToggle && (
                          <button
                            type="button"
                            onClick={() => setShowAllSelected((prev) => !prev)}
                            className="flex h-[18px] items-center gap-2 text-xs leading-none text-muted-foreground hover:text-foreground"
                          >
                            <span
                              className={cn(
                                "relative inline-flex h-4 w-8 items-center rounded-full transition-colors",
                                showAllSelected ? "bg-foreground" : "bg-muted"
                              )}
                            >
                              <span
                                className={cn(
                                  "absolute left-0.5 size-3 rounded-full bg-background shadow-xs transition-transform",
                                  showAllSelected
                                    ? "translate-x-4"
                                    : "translate-x-0"
                                )}
                              />
                            </span>
                            Show all selected
                          </button>
                        )}
                      </div>
                    </th>
                  </tr>
                )}

                {/* Normal header row — always rendered for column widths */}
                <tr className="border-b border-border bg-muted/30">
                  {selectable && (
                    <th className="w-10 px-3 py-2 whitespace-nowrap">
                      <div
                        className={cn(
                          "flex h-[18px] items-center",
                          hasSelection && "invisible"
                        )}
                      >
                        <Checkbox
                          checked={allSelected}
                          indeterminate={someSelected && !allSelected}
                          onCheckedChange={toggleSelectAll}
                          aria-label="Select all"
                          className="size-3.5"
                        />
                      </div>
                    </th>
                  )}
                  {columns.map((column) => (
                    <th
                      key={column.id}
                      className={cn(
                        "px-3 py-2 text-xs font-medium whitespace-nowrap text-muted-foreground",
                        column.align === "center"
                          ? "text-center"
                          : column.align === "end"
                            ? "text-right"
                            : "text-left",
                        column.headerClassName,
                        column.widthClassName
                      )}
                    >
                      <div
                        className={cn(
                          "flex h-[18px] items-center",
                          column.align === "center"
                            ? "justify-center"
                            : column.align === "end"
                              ? "justify-end"
                              : "justify-start",
                          hasSelection && "invisible"
                        )}
                      >
                        {column.sortable ? (
                          <button
                            type="button"
                            onClick={() => handleSortClick(column.id)}
                            className={cn(
                              "group inline-flex items-center gap-0.5 text-xs leading-none font-medium hover:text-foreground",
                              sort?.columnId === column.id
                                ? "text-foreground"
                                : "text-muted-foreground"
                            )}
                          >
                            {column.label}
                            {renderSortIcon(column.id)}
                          </button>
                        ) : (
                          <span className="leading-none">{column.label}</span>
                        )}
                      </div>
                    </th>
                  ))}
                </tr>
              </thead>

              <tbody className="divide-y divide-border">
                {visibleItems.map((item) => {
                  const id = itemId(item)
                  const isSelected =
                    selectionScope === "all" || selectedIds.has(id)
                  const cells = renderRow(item)

                  return (
                    <tr
                      key={id}
                      className={cn(
                        "hover:bg-muted/20",
                        isSelected && "bg-muted/10"
                      )}
                    >
                      {selectable && (
                        <td className="w-10 px-3 py-2 whitespace-nowrap">
                          <Checkbox
                            checked={isSelected}
                            onCheckedChange={() => toggleRow(id)}
                            aria-label="Select row"
                            className="size-3.5"
                          />
                        </td>
                      )}
                      {cells.map((cell, index) => {
                        const column = columns[index]
                        return (
                          <td
                            key={`${id}-${column?.id ?? index}`}
                            className={cn(
                              "px-3 py-2 text-sm whitespace-nowrap",
                              column?.align === "center"
                                ? "text-center"
                                : column?.align === "end"
                                  ? "text-right"
                                  : "text-left",
                              column?.cellClassName
                            )}
                          >
                            {cell}
                          </td>
                        )
                      })}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* Pagination */}
      {pagination && (
        <div className="flex items-center justify-center gap-2 border-t border-border px-3 py-2 text-sm text-muted-foreground">
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            onClick={pagination.onPrevious}
            disabled={!pagination.hasPrevious}
          >
            <ChevronLeft className="size-4" />
            <span className="sr-only">Previous page</span>
          </Button>
          <span className="text-xs">{pagination.label}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            onClick={pagination.onNext}
            disabled={!pagination.hasNext}
          >
            <ChevronRight className="size-4" />
            <span className="sr-only">Next page</span>
          </Button>
        </div>
      )}
    </div>
  )
}
