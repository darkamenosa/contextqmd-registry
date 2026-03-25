import {
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import { createPortal } from "react-dom"
import { X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

import {
  fetchBehaviorPropertyKeys,
  fetchBehaviorPropertyValues,
  fetchListPage,
} from "../api"
import { lockBodyScroll } from "../lib/body-scroll-lock"
import { useQueryContext } from "../query-context"
import type { AnalyticsQuery, ListPayload } from "../types"

type DialogType =
  | "page"
  | "location"
  | "source"
  | "utm"
  | "browser"
  | "browser_version"
  | "os"
  | "os_version"
  | "size"
  | "goal"
  | "property"
type FilterDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  type: DialogType
}

export default function FilterDialog({
  open,
  onOpenChange,
  type,
}: FilterDialogProps) {
  const [mounted] = useState(() => typeof document !== "undefined")
  const dialogRef = useRef<HTMLDivElement | null>(null)
  const [canApply, setCanApply] = useState(false)
  const applyRef = useRef<null | (() => void)>(null)
  useEffect(() => {
    if (!open) return
    return lockBodyScroll()
  }, [open])

  // ESC to close, focus management (match remote-details-dialog)
  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onOpenChange(false)
      }
    }
    window.addEventListener("keydown", onKey)
    setTimeout(() => dialogRef.current?.focus(), 0)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onOpenChange])

  if (!mounted || !open) return null
  return createPortal(
    <div
      className="fixed inset-0 z-[60] flex items-start justify-center bg-background/80 p-4 pt-10 backdrop-blur-xs md:pt-12 lg:pt-16"
      onClick={() => onOpenChange(false)}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
        className="relative mx-auto flex h-[84vh] max-h-[84vh] w-full max-w-6xl flex-col rounded-xl border border-border bg-card shadow-xl outline-hidden"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (
            e.key === "Enter" &&
            (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) === false
          ) {
            // Submit when a field is focused and Apply is enabled
            if (canApply && applyRef.current) {
              e.preventDefault()
              applyRef.current()
            }
          }
        }}
      >
        <header className="flex flex-col gap-2 border-b border-border px-6 py-4 sm:flex-row sm:items-center sm:justify-between md:px-8 md:py-4">
          <h2 className="text-xl font-semibold text-foreground">
            {titleFor(type)}
          </h2>
          <div className="flex items-center gap-3">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => onOpenChange(false)}
              aria-label="Close filter dialog"
            >
              <X className="size-5" />
            </Button>
          </div>
        </header>

        <div className="flex-1 overflow-hidden">
          <div className="h-full overflow-y-auto p-6 md:p-8">
            {type === "page" ? (
              <PageFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "location" ? (
              <LocationFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "source" ? (
              <SourceFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "utm" ? (
              <UtmFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "browser" ? (
              <DeviceFilterForm
                dim="browser"
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "os" ? (
              <DeviceFilterForm
                dim="os"
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "browser_version" ? (
              <DeviceVersionFilterForm
                dim="browser_version"
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "os_version" ? (
              <DeviceVersionFilterForm
                dim="os_version"
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "size" ? (
              <ScreenSizeFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "goal" ? (
              <GoalFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
            {type === "property" ? (
              <PropertyFilterForm
                onDone={() => onOpenChange(false)}
                onProvideControls={(apply, enabled) => {
                  applyRef.current = apply
                  setCanApply(enabled)
                }}
              />
            ) : null}
          </div>
        </div>

        <footer className="flex shrink-0 items-center justify-end gap-3 border-t border-border px-6 py-3 md:px-8 md:py-4">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={!canApply}
            onClick={() => applyRef.current && applyRef.current()}
          >
            Apply filter
          </Button>
        </footer>
      </div>
    </div>,
    document.body
  )
}

function titleFor(type: DialogType) {
  switch (type) {
    case "page":
      return "Filter by Page"
    case "location":
      return "Filter by Location"
    case "source":
      return "Filter by Source"
    case "utm":
      return "Filter by UTM tags"
    case "browser":
      return "Filter by Browser"
    case "browser_version":
      return "Filter by Browser Version"
    case "os":
      return "Filter by Operating System"
    case "os_version":
      return "Filter by OS Version"
    case "size":
      return "Filter by Screen Size"
    case "goal":
      return "Filter by Goal"
    case "property":
      return "Filter by Property"
    default:
      return "Filter"
  }
}

type Operator = "is" | "is_not" | "contains"

function PageFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [pageOp, setPageOp] = useState<Operator>("is")
  const [entryOp, setEntryOp] = useState<Operator>("is")
  const [exitOp, setExitOp] = useState<Operator>("is")
  const [pageVal, setPageVal] = useState("")
  const [entryVal, setEntryVal] = useState("")
  const [exitVal, setExitVal] = useState("")

  const disabled = useMemo(() => {
    return [pageVal, entryVal, exitVal].every((v) => v.trim() === "")
  }, [pageVal, entryVal, exitVal])

  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const nextFilters = { ...next.filters }
      const nextAdvanced = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []

      function put(
        dim: "page" | "entry_page" | "exit_page",
        op: Operator,
        value: string
      ) {
        const v = value.trim()
        if (!v) return
        // Remove existing entries for this dim first
        delete nextFilters[dim]
        for (let i = nextAdvanced.length - 1; i >= 0; i--) {
          if (nextAdvanced[i][1] === dim) nextAdvanced.splice(i, 1)
        }
        if (op === "is") {
          nextFilters[dim] = v
        } else {
          nextAdvanced.push([op, dim, v])
        }
      }
      put("page", pageOp, pageVal)
      put("entry_page", entryOp, entryVal)
      put("exit_page", exitOp, exitVal)
      return { ...next, filters: nextFilters, advancedFilters: nextAdvanced }
    })
    onDone()
  }, [updateQuery, pageOp, entryOp, exitOp, pageVal, entryVal, exitVal, onDone])

  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])

  return (
    <form
      className="flex flex-col gap-3 md:gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="Page"
        operator={pageOp}
        onOperatorChange={setPageOp}
        value={pageVal}
        onValueChange={setPageVal}
        fetcher={usePageFetcher("default")}
        placeholder="Select a Page"
      />
      <FilterRow
        label="Entry Page"
        operator={entryOp}
        onOperatorChange={setEntryOp}
        value={entryVal}
        onValueChange={setEntryVal}
        fetcher={usePageFetcher("entry")}
        placeholder="Select an Entry Page"
      />
      <FilterRow
        label="Exit Page"
        operator={exitOp}
        onOperatorChange={setExitOp}
        value={exitVal}
        onValueChange={setExitVal}
        fetcher={usePageFetcher("exit")}
        placeholder="Select an Exit Page"
      />
    </form>
  )
}

function LocationFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [countryOp, setCountryOp] = useState<Operator>("is")
  const [regionOp, setRegionOp] = useState<Operator>("is")
  const [cityOp, setCityOp] = useState<Operator>("is")
  const [countryVal, setCountryVal] = useState("")
  const [regionVal, setRegionVal] = useState("")
  const [cityVal, setCityVal] = useState("")
  const disabled = [countryVal, regionVal, cityVal].every(
    (v) => v.trim() === ""
  )
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      function put(
        dim: "country" | "region" | "city",
        op: Operator,
        val: string
      ) {
        const v = val.trim()
        if (!v) return
        delete eq[dim]
        for (let i = adv.length - 1; i >= 0; i--) {
          if (adv[i][1] === dim) adv.splice(i, 1)
        }
        if (op === "is") {
          eq[dim] = v
        } else {
          adv.push([op, dim, v])
        }
      }
      put("country", countryOp, countryVal)
      put("region", regionOp, regionVal)
      put("city", cityOp, cityVal)
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [
    updateQuery,
    countryOp,
    regionOp,
    cityOp,
    countryVal,
    regionVal,
    cityVal,
    onDone,
  ])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="Country"
        operator={countryOp}
        onOperatorChange={setCountryOp}
        value={countryVal}
        onValueChange={setCountryVal}
        fetcher={useLocationFetcher("countries")}
        placeholder="Select a Country"
      />
      <FilterRow
        label="Region"
        operator={regionOp}
        onOperatorChange={setRegionOp}
        value={regionVal}
        onValueChange={setRegionVal}
        fetcher={useLocationFetcher("regions")}
        placeholder="Select a Region"
      />
      <FilterRow
        label="City"
        operator={cityOp}
        onOperatorChange={setCityOp}
        value={cityVal}
        onValueChange={setCityVal}
        fetcher={useLocationFetcher("cities")}
        placeholder="Select a City"
      />
    </form>
  )
}

function useLocationFetcher(mode: "countries" | "regions" | "cities") {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          "/admin/analytics/locations",
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return payload.results.map((it) => ({
          label: String(it.name),
          value: String(it.code ?? it.name),
        }))
      } catch {
        return []
      }
    },
    [query, mode]
  )
}

function SourceFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [val, setVal] = useState("")
  const disabled = val.trim() === ""
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      delete eq["source"]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === "source") adv.splice(i, 1)
      }
      if (op === "is") {
        eq["source"] = val.trim()
      } else {
        adv.push([op, "source", val.trim()])
      }
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [updateQuery, op, val, onDone])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="Source"
        operator={op}
        onOperatorChange={setOp}
        value={val}
        onValueChange={setVal}
        fetcher={useSourcesFetcher("all")}
        placeholder="Select a Source"
      />
    </form>
  )
}

function useSourcesFetcher(
  mode:
    | "all"
    | "utm-source"
    | "utm-medium"
    | "utm-campaign"
    | "utm-content"
    | "utm-term"
) {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          "/admin/analytics/sources",
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return payload.results.map((it) => ({
          label: String(it.name),
          value: String(it.name),
        }))
      } catch {
        return []
      }
    },
    [query, mode]
  )
}

function UtmFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [sourceOp, setSourceOp] = useState<Operator>("is")
  const [sourceVal, setSourceVal] = useState("")
  const [mediumOp, setMediumOp] = useState<Operator>("is")
  const [mediumVal, setMediumVal] = useState("")
  const [campaignOp, setCampaignOp] = useState<Operator>("is")
  const [campaignVal, setCampaignVal] = useState("")
  const [contentOp, setContentOp] = useState<Operator>("is")
  const [contentVal, setContentVal] = useState("")
  const [termOp, setTermOp] = useState<Operator>("is")
  const [termVal, setTermVal] = useState("")
  const disabled = [
    sourceVal,
    mediumVal,
    campaignVal,
    contentVal,
    termVal,
  ].every((v) => v.trim() === "")
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      function put(
        dim:
          | "utm_source"
          | "utm_medium"
          | "utm_campaign"
          | "utm_content"
          | "utm_term",
        op: Operator,
        v: string
      ) {
        const val = v.trim()
        if (!val) return
        delete eq[dim]
        for (let i = adv.length - 1; i >= 0; i--) {
          if (adv[i][1] === dim) adv.splice(i, 1)
        }
        if (op === "is") {
          eq[dim] = val
        } else {
          adv.push([op, dim, val])
        }
      }
      put("utm_source", sourceOp, sourceVal)
      put("utm_medium", mediumOp, mediumVal)
      put("utm_campaign", campaignOp, campaignVal)
      put("utm_content", contentOp, contentVal)
      put("utm_term", termOp, termVal)
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [
    updateQuery,
    sourceOp,
    sourceVal,
    mediumOp,
    mediumVal,
    campaignOp,
    campaignVal,
    contentOp,
    contentVal,
    termOp,
    termVal,
    onDone,
  ])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="UTM Source"
        operator={sourceOp}
        onOperatorChange={setSourceOp}
        value={sourceVal}
        onValueChange={setSourceVal}
        fetcher={useSourcesFetcher("utm-source")}
        placeholder="Select a UTM Source"
      />
      <FilterRow
        label="UTM Medium"
        operator={mediumOp}
        onOperatorChange={setMediumOp}
        value={mediumVal}
        onValueChange={setMediumVal}
        fetcher={useSourcesFetcher("utm-medium")}
        placeholder="Select a UTM Medium"
      />
      <FilterRow
        label="UTM Campaign"
        operator={campaignOp}
        onOperatorChange={setCampaignOp}
        value={campaignVal}
        onValueChange={setCampaignVal}
        fetcher={useSourcesFetcher("utm-campaign")}
        placeholder="Select a UTM Campaign"
      />
      <FilterRow
        label="UTM Content"
        operator={contentOp}
        onOperatorChange={setContentOp}
        value={contentVal}
        onValueChange={setContentVal}
        fetcher={useSourcesFetcher("utm-content")}
        placeholder="Select a UTM Content"
      />
      <FilterRow
        label="UTM Term"
        operator={termOp}
        onOperatorChange={setTermOp}
        value={termVal}
        onValueChange={setTermVal}
        fetcher={useSourcesFetcher("utm-term")}
        placeholder="Select a UTM Term"
      />
    </form>
  )
}

function DeviceFilterForm({
  dim,
  onDone,
  onProvideControls,
}: {
  dim: "browser" | "os"
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [val, setVal] = useState("")
  const disabled = val.trim() === ""
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      delete eq[dim]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === dim) adv.splice(i, 1)
      }
      if (op === "is") {
        eq[dim] = val.trim()
      } else {
        adv.push([op, dim, val.trim()])
      }
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [updateQuery, op, val, dim, onDone])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  const mode = dim === "browser" ? "browsers" : "operating-systems"
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label={dim === "browser" ? "Browser" : "Operating System"}
        operator={op}
        onOperatorChange={setOp}
        value={val}
        onValueChange={setVal}
        fetcher={useDeviceFetcher(mode)}
        placeholder={`Select a ${dim === "browser" ? "Browser" : "OS"}`}
      />
    </form>
  )
}

function useDeviceFetcher(
  mode:
    | "browsers"
    | "browser-versions"
    | "operating-systems"
    | "operating-system-versions"
    | "screen-sizes"
) {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          "/admin/analytics/devices",
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return payload.results.map((it) => ({
          label: String(it.name),
          value: String(it.name),
        }))
      } catch {
        return []
      }
    },
    [query, mode]
  )
}

function DeviceVersionFilterForm({
  dim,
  onDone,
  onProvideControls,
}: {
  dim: "browser_version" | "os_version"
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [val, setVal] = useState("")
  const disabled = val.trim() === ""
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      delete eq[dim]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === dim) adv.splice(i, 1)
      }
      if (op === "is") {
        eq[dim] = val.trim()
      } else {
        adv.push([op, dim, val.trim()])
      }
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [updateQuery, op, val, dim, onDone])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  const mode =
    dim === "browser_version" ? "browser-versions" : "operating-system-versions"
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label={dim === "browser_version" ? "Browser Version" : "OS Version"}
        operator={op}
        onOperatorChange={setOp}
        value={val}
        onValueChange={setVal}
        fetcher={useDeviceFetcher(mode)}
        placeholder={`Select a ${dim === "browser_version" ? "Browser" : "OS"} Version`}
      />
    </form>
  )
}

function ScreenSizeFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [val, setVal] = useState("")
  const disabled = val.trim() === ""
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      delete eq["size"]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === "size") adv.splice(i, 1)
      }
      if (op === "is") {
        eq["size"] = val.trim()
      } else {
        adv.push([op, "size", val.trim()])
      }
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [updateQuery, op, val, onDone])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="Screen Size"
        operator={op}
        onOperatorChange={setOp}
        value={val}
        onValueChange={setVal}
        fetcher={useDeviceFetcher("screen-sizes")}
        placeholder="Select a Screen Size"
      />
    </form>
  )
}

function GoalFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [val, setVal] = useState("")
  const disabled = val.trim() === ""
  const apply = useCallback(() => {
    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []
      delete eq["goal"]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === "goal") adv.splice(i, 1)
      }
      if (op === "is") {
        eq["goal"] = val.trim()
      } else {
        adv.push([op, "goal", val.trim()])
      }
      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [updateQuery, op, val, onDone])
  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <FilterRow
        label="Goal"
        operator={op}
        onOperatorChange={setOp}
        value={val}
        onValueChange={setVal}
        fetcher={useBehaviorFetcher("conversions")}
        placeholder="Select a Goal"
      />
    </form>
  )
}

function PropertyFilterForm({
  onDone,
  onProvideControls,
}: {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}) {
  const { updateQuery } = useQueryContext()
  const [op, setOp] = useState<Operator>("is")
  const [propertyKey, setPropertyKey] = useState("")
  const [propertyValue, setPropertyValue] = useState("")
  const disabled = propertyKey.trim() === "" || propertyValue.trim() === ""
  const propertyFilterKey = propertyKey.trim()
    ? `prop:${propertyKey.trim()}`
    : null

  const apply = useCallback(() => {
    if (!propertyFilterKey) return

    updateQuery((current) => {
      const next: AnalyticsQuery = { ...current }
      const eq = { ...next.filters }
      const adv = Array.isArray(next.advancedFilters)
        ? [...next.advancedFilters]
        : []

      delete eq[propertyFilterKey]
      for (let i = adv.length - 1; i >= 0; i--) {
        if (adv[i][1] === propertyFilterKey) adv.splice(i, 1)
      }

      if (op === "is") {
        eq[propertyFilterKey] = propertyValue.trim()
      } else {
        adv.push([op, propertyFilterKey, propertyValue.trim()])
      }

      return { ...next, filters: eq, advancedFilters: adv }
    })
    onDone()
  }, [onDone, op, propertyFilterKey, propertyValue, updateQuery])

  useEffect(() => {
    onProvideControls(apply, !disabled)
  }, [apply, disabled, onProvideControls])

  const propertyKeyFetcher = useBehaviorPropertyKeyFetcher()
  const propertyValueFetcher = useBehaviorPropertyValueFetcher(propertyKey)

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault()
      }}
    >
      <div className="grid grid-cols-1 gap-1.5 md:grid-cols-[max-content_minmax(0,1fr)] md:items-center">
        <Label className="text-sm text-muted-foreground md:self-center">
          Property
        </Label>
        <SuggestInput
          value={propertyKey}
          onChange={(value) => {
            setPropertyKey(value)
            setPropertyValue("")
          }}
          fetcher={propertyKeyFetcher}
          placeholder="Select a Property"
        />
      </div>
      <FilterRow
        label="Value"
        operator={op}
        onOperatorChange={setOp}
        value={propertyValue}
        onValueChange={setPropertyValue}
        fetcher={propertyValueFetcher}
        placeholder="Select a Value"
      />
    </form>
  )
}

function useBehaviorFetcher(mode: "conversions") {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          "/admin/analytics/behaviors",
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return payload.results.map((it) => ({
          label: String(it.name),
          value: String(it.name),
        }))
      } catch {
        return []
      }
    },
    [query, mode]
  )
}

function useBehaviorPropertyKeyFetcher() {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const keys = await fetchBehaviorPropertyKeys(query as AnalyticsQuery)
        const needle = input.trim().toLowerCase()
        return keys
          .filter((key) => (needle ? key.toLowerCase().includes(needle) : true))
          .map((key) => ({ label: key, value: key }))
      } catch {
        return []
      }
    },
    [query]
  )
}

function useBehaviorPropertyValueFetcher(property: string) {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      const propertyName = property.trim()
      if (!propertyName) return []

      try {
        return await fetchBehaviorPropertyValues(
          query as AnalyticsQuery,
          propertyName,
          input
        )
      } catch {
        return []
      }
    },
    [property, query]
  )
}

function FilterRow({
  label,
  operator,
  onOperatorChange,
  value,
  onValueChange,
  fetcher,
  placeholder,
}: {
  label: string
  operator: Operator
  onOperatorChange: (op: Operator) => void
  value: string
  onValueChange: (v: string) => void
  fetcher: (q: string) => Promise<Array<{ label: string; value: string }>>
  placeholder: string
}) {
  return (
    <div className="grid grid-cols-1 gap-1.5 md:grid-cols-[max-content_minmax(0,1fr)] md:items-center">
      <Label className="text-sm text-muted-foreground md:self-center">
        {label}
      </Label>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <Select
          value={operator}
          onValueChange={(v) => {
            if (v) onOperatorChange(v as Operator)
          }}
        >
          <SelectTrigger className="h-9 w-24 shrink-0 rounded-md md:w-28">
            <SelectValue />
          </SelectTrigger>
          <SelectContent className="z-[70]">
            <SelectItem value="is">is</SelectItem>
            <SelectItem value="is_not">is not</SelectItem>
            <SelectItem value="contains">contains</SelectItem>
          </SelectContent>
        </Select>
        <div className="min-w-0 flex-1">
          <SuggestInput
            value={value}
            onChange={onValueChange}
            fetcher={fetcher}
            placeholder={placeholder}
          />
        </div>
      </div>
    </div>
  )
}

function usePageFetcher(mode: "default" | "entry" | "exit") {
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      const extras: Record<string, string> = {}
      if (mode === "entry") extras.mode = "entry"
      if (mode === "exit") extras.mode = "exit"
      try {
        const payload: ListPayload = await fetchListPage(
          "/admin/analytics/pages",
          query as AnalyticsQuery,
          extras,
          { limit: 20, page: 1, search: input }
        )
        return payload.results.map((it) => ({
          label: String(it.name),
          value: String(it.name),
        }))
      } catch {
        return []
      }
    },
    [query, mode]
  )
}

function SuggestInput({
  value,
  onChange,
  fetcher,
  placeholder,
  disabled,
}: {
  value: string
  onChange: (v: string) => void
  fetcher: (q: string) => Promise<Array<{ label: string; value: string }>>
  placeholder?: string
  disabled?: boolean
}) {
  const [open, setOpen] = useState(false)
  const [options, setOptions] = useState<
    Array<{ label: string; value: string }>
  >([])
  const [loading, setLoading] = useState(false)
  const rootRef = useRef<HTMLDivElement | null>(null)
  const deferredValue = useDeferredValue(value)

  useEffect(() => {
    if (!open || disabled) {
      setLoading(false)
      return
    }

    let ignore = false
    const timeoutId = window.setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetcher(deferredValue.trim())
        if (!ignore) {
          setOptions(res)
        }
      } finally {
        if (!ignore) {
          setLoading(false)
        }
      }
    }, 250)

    return () => {
      ignore = true
      window.clearTimeout(timeoutId)
    }
  }, [deferredValue, disabled, fetcher, open])

  return (
    <div
      ref={rootRef}
      className="relative"
      onBlurCapture={(event) => {
        const nextFocused = event.relatedTarget
        if (
          nextFocused instanceof Node &&
          rootRef.current?.contains(nextFocused)
        ) {
          return
        }
        setOpen(false)
      }}
      onFocusCapture={() => {
        if (!disabled) {
          setOpen(true)
        }
      }}
    >
      <Input
        value={value}
        onChange={(e) => {
          onChange(e.target.value)
        }}
        placeholder={placeholder}
        disabled={disabled}
        className="h-9"
      />
      {open && (
        <div className="absolute z-50 mt-1 w-full overflow-hidden rounded-md border border-border bg-background shadow-lg">
          <div className="max-h-60 overflow-auto text-sm">
            {loading ? (
              <div className="px-3 py-2 text-muted-foreground">Searching…</div>
            ) : options.length === 0 ? (
              <div className="px-3 py-2 text-muted-foreground">No matches</div>
            ) : (
              options.map((opt) => (
                <button
                  key={opt.value}
                  type="button"
                  className="block w-full cursor-pointer px-3 py-2 text-left hover:bg-muted/50 focus:bg-muted/50 focus:outline-hidden"
                  onClick={() => {
                    onChange(opt.value)
                    setOpen(false)
                  }}
                >
                  {opt.label}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  )
}
