import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react"

import { Label } from "@/components/ui/label"

import { useQueryContext } from "../../query-context"
import type { AnalyticsQuery } from "../../types"
import {
  useBehaviorFetcher,
  useBehaviorPropertyKeyFetcher,
  useBehaviorPropertyValueFetcher,
  useDeviceFetcher,
  useLocationFetcher,
  usePageFetcher,
  useSourcesFetcher,
} from "./fetchers"
import {
  FilterRow,
  SuggestInput,
  type Operator,
  type SuggestionFetcher,
} from "./shared"

export type DialogFormProps = {
  onDone: () => void
  onProvideControls: (apply: () => void, enabled: boolean) => void
}

type FilterField = {
  key: string
  dim: string
  label: string
  placeholder: string
  fetcher: SuggestionFetcher
}

type FilterState = {
  operators: Record<string, Operator>
  values: Record<string, string>
}

function createInitialState(fields: FilterField[]): FilterState {
  return {
    operators: Object.fromEntries(fields.map((field) => [field.key, "is"])),
    values: Object.fromEntries(fields.map((field) => [field.key, ""])),
  }
}

function applyOperatorFilters(
  current: AnalyticsQuery,
  filters: Array<{ dim: string; op: Operator; value: string }>
) {
  const next: AnalyticsQuery = { ...current }
  const eq = { ...next.filters }
  const adv = Array.isArray(next.advancedFilters)
    ? [...next.advancedFilters]
    : []

  for (const filter of filters) {
    const value = filter.value.trim()
    delete eq[filter.dim]
    for (let index = adv.length - 1; index >= 0; index -= 1) {
      if (adv[index][1] === filter.dim) adv.splice(index, 1)
    }
    if (!value) continue
    if (filter.op === "is") {
      eq[filter.dim] = value
    } else {
      adv.push([filter.op, filter.dim, value])
    }
  }

  return { ...next, filters: eq, advancedFilters: adv }
}

function useRegisterDialogControls(
  apply: () => void,
  enabled: boolean,
  onProvideControls: DialogFormProps["onProvideControls"]
) {
  useEffect(() => {
    onProvideControls(apply, enabled)
  }, [apply, enabled, onProvideControls])
}

function FilterFormShell({ children }: { children: ReactNode }) {
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault()
      }}
    >
      {children}
    </form>
  )
}

function MultiFieldFilterForm({
  fields,
  onDone,
  onProvideControls,
}: DialogFormProps & { fields: FilterField[] }) {
  const { updateQuery } = useQueryContext()
  const [state, setState] = useState<FilterState>(() =>
    createInitialState(fields)
  )

  const disabled = useMemo(
    () => fields.every((field) => state.values[field.key].trim() === ""),
    [fields, state.values]
  )

  const apply = useCallback(() => {
    updateQuery((current) =>
      applyOperatorFilters(
        current,
        fields.map((field) => ({
          dim: field.dim,
          op: state.operators[field.key],
          value: state.values[field.key],
        }))
      )
    )
    onDone()
  }, [fields, onDone, state.operators, state.values, updateQuery])

  useRegisterDialogControls(apply, !disabled, onProvideControls)

  return (
    <FilterFormShell>
      {fields.map((field) => (
        <FilterRow
          key={field.key}
          label={field.label}
          operator={state.operators[field.key]}
          onOperatorChange={(operator: Operator) => {
            setState((current) => ({
              ...current,
              operators: { ...current.operators, [field.key]: operator },
            }))
          }}
          value={state.values[field.key]}
          onValueChange={(value: string) => {
            setState((current) => ({
              ...current,
              values: { ...current.values, [field.key]: value },
            }))
          }}
          fetcher={field.fetcher}
          placeholder={field.placeholder}
        />
      ))}
    </FilterFormShell>
  )
}

function SingleFieldFilterForm({
  dim,
  label,
  placeholder,
  fetcher,
  onDone,
  onProvideControls,
}: DialogFormProps & {
  dim: string
  label: string
  placeholder: string
  fetcher: SuggestionFetcher
}) {
  const { updateQuery } = useQueryContext()
  const [operator, setOperator] = useState<Operator>("is")
  const [value, setValue] = useState("")
  const disabled = value.trim() === ""

  const apply = useCallback(() => {
    updateQuery((current) =>
      applyOperatorFilters(current, [{ dim, op: operator, value }])
    )
    onDone()
  }, [dim, onDone, operator, updateQuery, value])

  useRegisterDialogControls(apply, !disabled, onProvideControls)

  return (
    <FilterFormShell>
      <FilterRow
        label={label}
        operator={operator}
        onOperatorChange={setOperator}
        value={value}
        onValueChange={setValue}
        fetcher={fetcher}
        placeholder={placeholder}
      />
    </FilterFormShell>
  )
}

export function PageFilterForm(props: DialogFormProps) {
  const defaultFetcher = usePageFetcher("default")
  const entryFetcher = usePageFetcher("entry")
  const exitFetcher = usePageFetcher("exit")

  return (
    <MultiFieldFilterForm
      {...props}
      fields={[
        {
          key: "page",
          dim: "page",
          label: "Page",
          placeholder: "Select a Page",
          fetcher: defaultFetcher,
        },
        {
          key: "entry_page",
          dim: "entry_page",
          label: "Entry Page",
          placeholder: "Select an Entry Page",
          fetcher: entryFetcher,
        },
        {
          key: "exit_page",
          dim: "exit_page",
          label: "Exit Page",
          placeholder: "Select an Exit Page",
          fetcher: exitFetcher,
        },
      ]}
    />
  )
}

export function LocationFilterForm(props: DialogFormProps) {
  const countriesFetcher = useLocationFetcher("countries")
  const regionsFetcher = useLocationFetcher("regions")
  const citiesFetcher = useLocationFetcher("cities")

  return (
    <MultiFieldFilterForm
      {...props}
      fields={[
        {
          key: "country",
          dim: "country",
          label: "Country",
          placeholder: "Select a Country",
          fetcher: countriesFetcher,
        },
        {
          key: "region",
          dim: "region",
          label: "Region",
          placeholder: "Select a Region",
          fetcher: regionsFetcher,
        },
        {
          key: "city",
          dim: "city",
          label: "City",
          placeholder: "Select a City",
          fetcher: citiesFetcher,
        },
      ]}
    />
  )
}

export function SourceFilterForm(props: DialogFormProps) {
  return (
    <SingleFieldFilterForm
      {...props}
      dim="source"
      label="Source"
      placeholder="Select a Source"
      fetcher={useSourcesFetcher("all")}
    />
  )
}

export function UtmFilterForm(props: DialogFormProps) {
  const sourceFetcher = useSourcesFetcher("utm-source")
  const mediumFetcher = useSourcesFetcher("utm-medium")
  const campaignFetcher = useSourcesFetcher("utm-campaign")
  const contentFetcher = useSourcesFetcher("utm-content")
  const termFetcher = useSourcesFetcher("utm-term")

  return (
    <MultiFieldFilterForm
      {...props}
      fields={[
        {
          key: "utm_source",
          dim: "utm_source",
          label: "UTM Source",
          placeholder: "Select a UTM Source",
          fetcher: sourceFetcher,
        },
        {
          key: "utm_medium",
          dim: "utm_medium",
          label: "UTM Medium",
          placeholder: "Select a UTM Medium",
          fetcher: mediumFetcher,
        },
        {
          key: "utm_campaign",
          dim: "utm_campaign",
          label: "UTM Campaign",
          placeholder: "Select a UTM Campaign",
          fetcher: campaignFetcher,
        },
        {
          key: "utm_content",
          dim: "utm_content",
          label: "UTM Content",
          placeholder: "Select a UTM Content",
          fetcher: contentFetcher,
        },
        {
          key: "utm_term",
          dim: "utm_term",
          label: "UTM Term",
          placeholder: "Select a UTM Term",
          fetcher: termFetcher,
        },
      ]}
    />
  )
}

export function DeviceFilterForm({
  dim,
  ...props
}: DialogFormProps & { dim: "browser" | "os" }) {
  return (
    <SingleFieldFilterForm
      {...props}
      dim={dim}
      label={dim === "browser" ? "Browser" : "Operating System"}
      placeholder={`Select a ${dim === "browser" ? "Browser" : "OS"}`}
      fetcher={useDeviceFetcher(
        dim === "browser" ? "browsers" : "operating-systems"
      )}
    />
  )
}

export function DeviceVersionFilterForm({
  dim,
  ...props
}: DialogFormProps & { dim: "browser_version" | "os_version" }) {
  return (
    <SingleFieldFilterForm
      {...props}
      dim={dim}
      label={dim === "browser_version" ? "Browser Version" : "OS Version"}
      placeholder={`Select a ${
        dim === "browser_version" ? "Browser" : "OS"
      } Version`}
      fetcher={useDeviceFetcher(
        dim === "browser_version"
          ? "browser-versions"
          : "operating-system-versions"
      )}
    />
  )
}

export function ScreenSizeFilterForm(props: DialogFormProps) {
  return (
    <SingleFieldFilterForm
      {...props}
      dim="size"
      label="Screen Size"
      placeholder="Select a Screen Size"
      fetcher={useDeviceFetcher("screen-sizes")}
    />
  )
}

export function GoalFilterForm(props: DialogFormProps) {
  return (
    <SingleFieldFilterForm
      {...props}
      dim="goal"
      label="Goal"
      placeholder="Select a Goal"
      fetcher={useBehaviorFetcher("conversions")}
    />
  )
}

export function PropertyFilterForm({
  onDone,
  onProvideControls,
}: DialogFormProps) {
  const { updateQuery } = useQueryContext()
  const [operator, setOperator] = useState<Operator>("is")
  const [propertyKey, setPropertyKey] = useState("")
  const [propertyValue, setPropertyValue] = useState("")
  const disabled = propertyKey.trim() === "" || propertyValue.trim() === ""
  const propertyFilterKey = propertyKey.trim()
    ? `prop:${propertyKey.trim()}`
    : null

  const apply = useCallback(() => {
    if (!propertyFilterKey) return
    updateQuery((current) =>
      applyOperatorFilters(current, [
        { dim: propertyFilterKey, op: operator, value: propertyValue },
      ])
    )
    onDone()
  }, [onDone, operator, propertyFilterKey, propertyValue, updateQuery])

  useRegisterDialogControls(apply, !disabled, onProvideControls)

  const propertyKeyFetcher = useBehaviorPropertyKeyFetcher()
  const propertyValueFetcher = useBehaviorPropertyValueFetcher(propertyKey)

  return (
    <FilterFormShell>
      <div className="grid grid-cols-1 gap-1.5 md:grid-cols-[max-content_minmax(0,1fr)] md:items-center">
        <Label className="text-sm text-muted-foreground md:self-center">
          Property
        </Label>
        <SuggestInput
          value={propertyKey}
          onChange={(value: string) => {
            setPropertyKey(value)
            setPropertyValue("")
          }}
          fetcher={propertyKeyFetcher}
          placeholder="Select a Property"
        />
      </div>
      <FilterRow
        label="Value"
        operator={operator}
        onOperatorChange={setOperator}
        value={propertyValue}
        onValueChange={setPropertyValue}
        fetcher={propertyValueFetcher}
        placeholder="Select a Value"
      />
    </FilterFormShell>
  )
}
