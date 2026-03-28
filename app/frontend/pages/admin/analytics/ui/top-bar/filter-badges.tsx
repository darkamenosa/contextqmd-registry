import { X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"

import { useQueryContext } from "../../query-context"
import { filterLabel, getOrderedFilters } from "./filter-utils"

export default function FilterBadges() {
  const { query, updateQuery } = useQueryContext()
  const { equalityFilters, advancedFilters } = getOrderedFilters(query)

  if (equalityFilters.length === 0 && advancedFilters.length === 0) {
    return null
  }

  return (
    <>
      {equalityFilters.map(([key, value]) => (
        <Badge
          key={`eq:${key}`}
          variant="secondary"
          className="flex items-center gap-1 bg-accent hover:bg-primary/10"
        >
          <span className="capitalize">{filterLabel(key)}:</span>
          <span>{(query.labels && query.labels[key]) || value}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-5 p-0"
            onClick={() => {
              updateQuery((current) => {
                const nextFilters: Record<string, string> = {
                  ...current.filters,
                }
                delete nextFilters[key]
                const nextLabels = { ...(current.labels || {}) } as Record<
                  string,
                  string
                >
                delete nextLabels[key]
                const cleaned =
                  Object.keys(nextFilters).length === 0 ? undefined : nextLabels
                return { ...current, filters: nextFilters, labels: cleaned }
              })
            }}
          >
            <X className="size-3" />
            <span className="sr-only">Remove filter {key}</span>
          </Button>
        </Badge>
      ))}
      {advancedFilters.map(([operator, dimension, clause], index) => (
        <Badge
          key={`adv:${index}:${operator}:${dimension}:${clause}`}
          variant="secondary"
          className="flex items-center gap-1 bg-accent hover:bg-primary/10"
        >
          <span className="capitalize">{filterLabel(dimension)}:</span>
          <span className="lowercase">
            {String(operator).replace("_", " ")}
          </span>
          <span className="font-medium">{clause}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-5 p-0"
            onClick={() => {
              updateQuery((current) => {
                const currentAdvanced = Array.isArray(current.advancedFilters)
                  ? current.advancedFilters
                  : []
                const nextAdvanced = currentAdvanced.filter(
                  (tuple) =>
                    !(
                      tuple[0] === operator &&
                      tuple[1] === dimension &&
                      tuple[2] === clause
                    )
                )
                return { ...current, advancedFilters: nextAdvanced }
              })
            }}
          >
            <X className="size-3" />
            <span className="sr-only">
              Remove filter {dimension} {operator} {clause}
            </span>
          </Button>
        </Badge>
      ))}
      {equalityFilters.length + advancedFilters.length >= 2 ? (
        <Button
          variant="ghost"
          size="sm"
          className="h-6 px-2 text-xs"
          onClick={() =>
            updateQuery((current) => ({
              ...current,
              filters: {},
              labels: undefined,
              advancedFilters: [],
            }))
          }
        >
          Clear all
        </Button>
      ) : null}
    </>
  )
}
