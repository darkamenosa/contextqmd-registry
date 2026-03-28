import { useEffect, useRef, useState } from "react"
import { Calendar, Shuffle } from "lucide-react"

import { useClientComponent } from "@/hooks/use-client-component"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

import { useQueryContext } from "../../query-context"
import type { AnalyticsQuery } from "../../types"
import MenuRow from "./menu-row"
import {
  applyPeriodSelection,
  getComparisonLabel,
  getPeriodDisplay,
  isActiveDay,
  isActiveMonth,
  isActiveYear,
} from "./period-utils"

const loadDateRangePickerComponent = () =>
  import("../date-range-dialog").then(({ default: component }) => component)

export default function QueryPeriodsPicker() {
  const { query, updateQuery } = useQueryContext()
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const customCalendarButtonRef = useRef<HTMLButtonElement>(null)
  const compareCalendarButtonRef = useRef<HTMLButtonElement>(null)
  const [customOpen, setCustomOpen] = useState(false)
  const [compareOpen, setCompareOpen] = useState(false)
  const { Component: DateRangePickerComponent, load: loadDateRangePicker } =
    useClientComponent(loadDateRangePickerComponent)

  useEffect(() => {
    function onKeydown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null
      const tag = (target?.tagName || "").toLowerCase()
      const isTyping =
        tag === "input" ||
        tag === "textarea" ||
        (target?.isContentEditable ?? false)
      if (isTyping || event.metaKey || event.ctrlKey || event.altKey) return

      const key = (event.key || "").toUpperCase()
      const map: Record<
        string,
        | { value: AnalyticsQuery["period"]; setDate?: "current" | "last" }
        | "toggle-compare"
        | "custom"
      > = {
        D: { value: "day", setDate: "current" },
        E: { value: "day", setDate: "last" },
        R: { value: "realtime" },
        W: { value: "7d" },
        F: { value: "28d" },
        N: { value: "91d" },
        M: { value: "month", setDate: "current" },
        P: { value: "month", setDate: "last" },
        Y: { value: "year", setDate: "current" },
        L: { value: "12mo" },
        A: { value: "all" },
        C: "custom",
        X: "toggle-compare",
      }
      const action = map[key]
      if (!action) return

      event.preventDefault()
      if (action === "custom") {
        void loadDateRangePicker()
          .then(() => setCustomOpen(true))
          .catch((error) => {
            console.error("Failed to load date range picker", error)
          })
        return
      }
      if (action === "toggle-compare") {
        updateQuery((current) => ({
          ...current,
          comparison:
            current.comparison === "previous_period" ? null : "previous_period",
        }))
        return
      }
      updateQuery((current) => applyPeriodSelection(current, action))
    }

    window.addEventListener("keydown", onKeydown)
    return () => window.removeEventListener("keydown", onKeydown)
  }, [loadDateRangePicker, updateQuery])

  const compareEnabled = Boolean(query.comparison)
  const compareLabel = getComparisonLabel(query)

  return (
    <div className="flex flex-wrap items-center gap-2">
      <DropdownMenu open={dropdownOpen} onOpenChange={setDropdownOpen}>
        <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
          <Calendar className="size-4 shrink-0" />
          <span className="truncate" suppressHydrationWarning>
            {getPeriodDisplay(query)}
          </span>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuItem
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, {
                  value: "day",
                  setDate: "current",
                })
              )
            }
          >
            <MenuRow
              label="Today"
              hint="D"
              active={isActiveDay(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "day", setDate: "last" })
              )
            }
          >
            <MenuRow
              label="Yesterday"
              hint="E"
              active={isActiveDay(query, "last")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "realtime" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Realtime"
              hint="R"
              active={query.period === "realtime"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "7d" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 7 Days"
              hint="W"
              active={query.period === "7d"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "28d" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 28 Days"
              hint="F"
              active={query.period === "28d"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "91d" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 91 Days"
              hint="N"
              active={query.period === "91d"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, {
                  value: "month",
                  setDate: "current",
                })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Month to Date"
              hint="M"
              active={isActiveMonth(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, {
                  value: "month",
                  setDate: "last",
                })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last Month"
              hint="P"
              active={isActiveMonth(query, "last")}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, {
                  value: "year",
                  setDate: "current",
                })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Year to Date"
              hint="Y"
              active={isActiveYear(query, "current")}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "12mo" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Last 12 Months"
              hint="L"
              active={query.period === "12mo"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() =>
              updateQuery((current) =>
                applyPeriodSelection(current, { value: "all" })
              )
            }
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="All time"
              hint="A"
              active={query.period === "all"}
            />
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => {
              setDropdownOpen(false)
              void loadDateRangePicker()
                .then(() => {
                  setTimeout(() => setCustomOpen(true), 0)
                })
                .catch((error) => {
                  console.error("Failed to load date range picker", error)
                })
            }}
            className="hover:bg-accent data-[selected=true]:bg-primary/10"
          >
            <MenuRow
              label="Custom Range"
              hint="C"
              active={query.period === "custom"}
            />
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {query.comparison ? (
            <DropdownMenuItem
              onClick={() =>
                updateQuery((current) => ({
                  ...current,
                  comparison: null,
                  compareFrom: null,
                  compareTo: null,
                }))
              }
              className="hover:bg-accent"
            >
              <MenuRow label="Disable comparison" hint="X" />
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem
              onClick={() =>
                updateQuery((current) => ({
                  ...current,
                  comparison: "previous_period",
                }))
              }
              className="hover:bg-accent"
            >
              <MenuRow
                label="Compare"
                hint="X"
                leftIcon={<Shuffle className="mr-2 size-4" />}
              />
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {compareEnabled ? (
        <>
          <span className="shrink-0 text-sm text-muted-foreground">vs.</span>
          <DropdownMenu>
            <DropdownMenuTrigger className="inline-flex h-7 items-center gap-2 rounded-lg border border-border bg-background px-2.5 text-sm font-medium hover:bg-muted">
              <span className="truncate">{compareLabel}</span>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((current) => ({
                    ...current,
                    comparison: null,
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent"
              >
                <MenuRow label="Disable comparison" />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((current) => ({
                    ...current,
                    comparison: "previous_period",
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Previous period"
                  active={query.comparison === "previous_period"}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((current) => ({
                    ...current,
                    comparison: "year_over_year",
                    compareFrom: null,
                    compareTo: null,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Year over year"
                  active={query.comparison === "year_over_year"}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() => {
                  setDropdownOpen(false)
                  void loadDateRangePicker()
                    .then(() => {
                      setTimeout(() => setCompareOpen(true), 0)
                    })
                    .catch((error) => {
                      console.error("Failed to load date range picker", error)
                    })
                }}
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Custom period…"
                  active={query.comparison === "custom"}
                />
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((current) => ({
                    ...current,
                    matchDayOfWeek: true,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Match day of week"
                  active={Boolean(query.matchDayOfWeek)}
                />
              </DropdownMenuItem>
              <DropdownMenuItem
                onClick={() =>
                  updateQuery((current) => ({
                    ...current,
                    matchDayOfWeek: false,
                  }))
                }
                className="hover:bg-accent data-[selected=true]:bg-primary/10"
              >
                <MenuRow
                  label="Match exact date"
                  active={Boolean(query.matchDayOfWeek) === false}
                />
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </>
      ) : null}

      {DateRangePickerComponent ? (
        <DateRangePickerComponent
          buttonRef={customCalendarButtonRef}
          open={customOpen}
          onOpenChange={setCustomOpen}
          initialFrom={query.period === "custom" ? query.from : undefined}
          initialTo={query.period === "custom" ? query.to : undefined}
          onApply={(fromISO, toISO) => {
            setCustomOpen(false)
            updateQuery((current) => ({
              ...current,
              period: "custom",
              from: fromISO,
              to: toISO,
            }))
          }}
        />
      ) : null}

      {DateRangePickerComponent ? (
        <DateRangePickerComponent
          buttonRef={compareCalendarButtonRef}
          open={compareOpen}
          onOpenChange={setCompareOpen}
          initialFrom={
            query.comparison === "custom" ? query.compareFrom : undefined
          }
          initialTo={
            query.comparison === "custom" ? query.compareTo : undefined
          }
          onApply={(fromISO, toISO) => {
            setCompareOpen(false)
            updateQuery(
              (current) =>
                ({
                  ...current,
                  comparison: "custom",
                  compareFrom: fromISO,
                  compareTo: toISO,
                }) as AnalyticsQuery
            )
          }}
        />
      ) : null}
    </div>
  )
}
