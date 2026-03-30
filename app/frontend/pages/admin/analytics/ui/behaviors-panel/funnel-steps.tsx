import { ArrowDown } from "lucide-react"

import { percentageFormatter } from "../../lib/number-formatter"
import type { BehaviorsPayload } from "../../types"
import SelectionTabDropdown from "./selection-tab-dropdown"

type FunnelData = Extract<BehaviorsPayload, { funnels: string[] }>
type FunnelStep = FunnelData["active"]["steps"][number]

const compactNumberFormatter = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
})

export default function FunnelSteps({
  data,
  availableFunnels,
  selectedFunnel,
  onSelectFunnel,
}: {
  data: FunnelData
  availableFunnels: string[]
  selectedFunnel?: string
  onSelectFunnel: (name: string) => void
}) {
  const funnel = data.active
  if (!funnel) return null

  const steps = funnel.steps
  const enteringVisitors = funnel.enteringVisitors ?? steps[0]?.visitors ?? 0
  const neverEnteringVisitors = funnel.neverEnteringVisitors ?? 0
  const maxVisitors = Math.max(
    ...steps.map((step: FunnelStep) => step.visitors),
    1
  )
  const overallRate =
    funnel.conversionRate ?? steps[steps.length - 1]?.conversionRate ?? 0

  const enrichedSteps = steps.map((step: FunnelStep) => ({
    ...step,
    barPercent: maxVisitors > 0 ? (step.visitors / maxVisitors) * 100 : 0,
  }))

  return (
    <div className="space-y-8">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="space-y-1">
          <p className="text-lg font-semibold text-foreground">{funnel.name}</p>
          <p className="text-sm text-muted-foreground">
            {steps.length}-step funnel • {percentageFormatter(overallRate)}{" "}
            conversion rate
          </p>
        </div>
        {availableFunnels.length > 1 ? (
          <SelectionTabDropdown
            active
            label={selectedFunnel ?? funnel.name}
            options={availableFunnels}
            value={selectedFunnel ?? funnel.name}
            searchPlaceholder="Search funnels"
            onSelect={onSelectFunnel}
          />
        ) : null}
      </div>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1.6fr)_minmax(20rem,1fr)]">
        <div className="rounded-md border border-border/70 bg-muted/10 p-4 sm:p-6">
          <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
            {enrichedSteps.map(
              (step: FunnelStep & { barPercent: number }, index: number) => (
                <article
                  key={step.name}
                  className="flex min-h-72 flex-col rounded-md border border-border/70 bg-card p-4 shadow-xs"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-xs font-semibold tracking-[0.18em] text-muted-foreground uppercase">
                        Step {index + 1}
                      </p>
                      <h3 className="mt-2 text-base/5 font-semibold text-foreground">
                        {step.name}
                      </h3>
                    </div>
                    <div className="text-right">
                      <p className="text-xl font-semibold text-foreground">
                        {compactNumberFormatter.format(step.visitors)}
                      </p>
                      <p className="text-xs text-muted-foreground">visitors</p>
                    </div>
                  </div>

                  <div className="mt-6 flex flex-1 items-end justify-center">
                    <div className="flex h-52 w-full max-w-28 items-end">
                      <div
                        className="relative w-full overflow-hidden rounded-t-xl rounded-b-md bg-primary/10"
                        style={{
                          height:
                            step.visitors > 0
                              ? `${Math.max(step.barPercent, 18)}%`
                              : "0%",
                        }}
                      >
                        <div
                          className="absolute inset-x-0 bottom-0 bg-primary"
                          style={{ height: `${step.conversionRateStep}%` }}
                        />
                        {step.dropoff > 0 ? (
                          <div
                            className="absolute inset-x-0 top-0 border-b border-primary/20 bg-[repeating-linear-gradient(-45deg,rgba(15,23,42,0.06),rgba(15,23,42,0.06)_6px,transparent_6px,transparent_12px)]"
                            style={{
                              height: `${100 - step.conversionRateStep}%`,
                            }}
                          />
                        ) : null}
                      </div>
                    </div>
                  </div>

                  <div className="mt-5 space-y-2 border-t border-border/70 pt-4 text-sm">
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-muted-foreground">
                        {index === 0 ? "Entered funnel" : "Reached step"}
                      </span>
                      <span className="font-medium text-foreground">
                        {percentageFormatter(
                          index === 0
                            ? funnel.enteringVisitorsPercentage
                            : step.conversionRate
                        )}
                      </span>
                    </div>
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-muted-foreground">
                        {index === 0 ? "Never entered" : "Dropped off"}
                      </span>
                      <span className="font-medium text-foreground">
                        {compactNumberFormatter.format(step.dropoff)}
                      </span>
                    </div>
                  </div>
                </article>
              )
            )}
          </div>
        </div>

        <aside className="rounded-md border border-border/70 bg-card p-5 shadow-xs">
          <p className="text-xs font-semibold tracking-[0.18em] text-muted-foreground uppercase">
            Summary
          </p>

          <div className="mt-4 text-center">
            <p className="text-4xl font-bold text-foreground tabular-nums">
              {percentageFormatter(overallRate)}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              overall conversion
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {compactNumberFormatter.format(enteringVisitors)} entered
              {" · "}
              {compactNumberFormatter.format(
                steps[steps.length - 1]?.visitors ?? 0
              )}{" "}
              completed
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {compactNumberFormatter.format(neverEnteringVisitors)} never
              entered
            </p>
          </div>

          <div className="mt-6 border-t border-border/70 pt-4">
            {enrichedSteps.map(
              (step: FunnelStep & { barPercent: number }, index: number) => (
                <div key={`${step.name}-summary`}>
                  {index > 0 ? (
                    <div className="flex items-center gap-2 py-1.5 pl-1">
                      <ArrowDown className="size-3 shrink-0 text-muted-foreground/50" />
                      <span className="text-xs text-muted-foreground">
                        {step.dropoff > 0
                          ? `${compactNumberFormatter.format(step.dropoff)} dropped · ${percentageFormatter(step.conversionRateStep)} converted`
                          : "no drop-off"}
                      </span>
                    </div>
                  ) : null}
                  <div className="space-y-1.5">
                    <div className="flex items-center justify-between gap-3 text-sm">
                      <span className="truncate font-medium text-foreground">
                        {step.name}
                      </span>
                      <span className="shrink-0 text-muted-foreground tabular-nums">
                        {compactNumberFormatter.format(step.visitors)}
                      </span>
                    </div>
                    <div className="h-2.5 overflow-hidden rounded-sm bg-muted">
                      <div
                        className="h-full rounded-sm bg-primary"
                        style={{
                          width:
                            step.visitors > 0
                              ? `${Math.max(4, step.barPercent)}%`
                              : "0%",
                        }}
                      />
                    </div>
                  </div>
                </div>
              )
            )}
          </div>
        </aside>
      </div>
    </div>
  )
}
