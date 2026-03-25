import { useEffect, useState } from "react"

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

import { fetchSourceDebug } from "../api"
import { useQueryContext } from "../query-context"
import type { CountBreakdownRow, SourceDebugPayload } from "../types"

type SourceDebugDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  source: string | null
}

export default function SourceDebugDialog({
  open,
  onOpenChange,
  source,
}: SourceDebugDialogProps) {
  const { query } = useQueryContext()
  const [data, setData] = useState<SourceDebugPayload | null>(null)

  useEffect(() => {
    if (!open || !source) return

    const controller = new AbortController()
    fetchSourceDebug(query, { source }, controller.signal)
      .then(setData)
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })

    return () => controller.abort()
  }, [open, query, source])

  const payload = data?.source.requestedValue === source ? data : null

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle>Source Debug</DialogTitle>
          <DialogDescription>
            Inspect how this source was normalized, matched, and grouped.
          </DialogDescription>
        </DialogHeader>

        {!payload ? (
          <div className="space-y-3 text-sm text-muted-foreground">
            <div>Loading source debug data...</div>
          </div>
        ) : (
          <div className="space-y-6 text-sm">
            <section className="grid gap-3 sm:grid-cols-3">
              <DebugStat
                label="Requested"
                value={payload.source.requestedValue || "(blank)"}
              />
              <DebugStat
                label="Normalized"
                value={payload.source.normalizedValue || "(blank)"}
              />
              <DebugStat label="Kind" value={payload.source.kind} />
              <DebugStat
                label="Favicon Domain"
                value={payload.source.faviconDomain || "(none)"}
              />
              <DebugStat
                label="Visitors"
                value={String(payload.source.visitors)}
              />
              <DebugStat label="Visits" value={String(payload.source.visits)} />
            </section>

            <section className="grid gap-4 sm:grid-cols-2">
              <DebugList title="Matched Rules" rows={payload.matchedRules} />
              <DebugList
                title="Match Strategies"
                rows={payload.matchStrategies}
                footer={`Fallback visits: ${payload.source.fallbackCount}`}
              />
              <DebugList
                title="Raw Referring Domains"
                rows={payload.rawReferringDomains}
              />
              <DebugList title="Raw UTM Sources" rows={payload.rawUtmSources} />
              <DebugList title="Channels" rows={payload.channels} />
              <DebugList title="Raw Referrers" rows={payload.rawReferrers} />
            </section>

            <section className="space-y-2">
              <h3 className="text-sm font-semibold">Latest Samples</h3>
              <div className="overflow-x-auto rounded-md border">
                <table className="min-w-full text-xs">
                  <thead className="bg-muted/50 text-muted-foreground">
                    <tr>
                      <th className="px-3 py-2 text-left font-medium">
                        Started
                      </th>
                      <th className="px-3 py-2 text-left font-medium">
                        Domain
                      </th>
                      <th className="px-3 py-2 text-left font-medium">
                        UTM Source
                      </th>
                      <th className="px-3 py-2 text-left font-medium">
                        UTM Medium
                      </th>
                      <th className="px-3 py-2 text-left font-medium">Rule</th>
                      <th className="px-3 py-2 text-left font-medium">
                        Strategy
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {payload.latestSamples.map((sample, index) => (
                      <tr
                        key={`${sample.startedAt}-${index}`}
                        className="border-t"
                      >
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.startedAt || "-"}
                        </td>
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.referringDomain || "-"}
                        </td>
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.utmSource || "-"}
                        </td>
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.utmMedium || "-"}
                        </td>
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.ruleId || "-"}
                        </td>
                        <td className="px-3 py-2 font-mono text-[11px]">
                          {sample.matchStrategy || "-"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

function DebugStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border bg-muted/20 p-3">
      <div className="text-xs tracking-wide text-muted-foreground uppercase">
        {label}
      </div>
      <div className="mt-1 font-mono text-xs break-all text-foreground">
        {value}
      </div>
    </div>
  )
}

function DebugList({
  title,
  rows,
  footer,
}: {
  title: string
  rows: CountBreakdownRow[]
  footer?: string
}) {
  return (
    <div className="space-y-2 rounded-md border p-3">
      <div className="text-sm font-semibold">{title}</div>
      {rows.length === 0 ? (
        <div className="text-xs text-muted-foreground">(none)</div>
      ) : (
        <div className="space-y-2">
          {rows.map((row) => (
            <div
              key={`${title}-${row.value}`}
              className="flex items-start justify-between gap-3"
            >
              <div className="font-mono text-xs break-all">{row.value}</div>
              <div className="shrink-0 text-xs text-muted-foreground">
                {row.count}
              </div>
            </div>
          ))}
        </div>
      )}
      {footer ? (
        <div className="border-t pt-2 text-xs text-muted-foreground">
          {footer}
        </div>
      ) : null}
    </div>
  )
}
