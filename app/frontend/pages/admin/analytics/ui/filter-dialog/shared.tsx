import {
  useDeferredValue,
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type SetStateAction,
} from "react"

import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

export type Operator = "is" | "is_not" | "contains"

export type SuggestionOption = {
  label: string
  value: string
}

export type SuggestionFetcher = (q: string) => Promise<SuggestionOption[]>

export function FilterRow({
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
  onOperatorChange:
    | Dispatch<SetStateAction<Operator>>
    | ((op: Operator) => void)
  value: string
  onValueChange: Dispatch<SetStateAction<string>> | ((v: string) => void)
  fetcher: SuggestionFetcher
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

export function SuggestInput({
  value,
  onChange,
  fetcher,
  placeholder,
  disabled,
}: {
  value: string
  onChange: Dispatch<SetStateAction<string>> | ((v: string) => void)
  fetcher: SuggestionFetcher
  placeholder?: string
  disabled?: boolean
}) {
  const [open, setOpen] = useState(false)
  const [options, setOptions] = useState<SuggestionOption[]>([])
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
