import { useCallback, useMemo, useState } from "react"
import { Head, Link, router, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  Code2,
  Copy,
  Filter,
  Globe,
  GripVertical,
  Link2,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
  X,
} from "lucide-react"

import { csrfToken } from "@/lib/csrf-token"
import { formatCalendarDay, formatDateTime } from "@/lib/format-date"
import { cn } from "@/lib/utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button, buttonVariants } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Field, FieldLabel } from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import AdminLayout from "@/layouts/admin-layout"

import { navigateAnalytics, useAnalyticsLocation } from "./lib/location-store"
import {
  buildAnalyticsSettingsTabUrl,
  getAnalyticsSettingsTabFromUrl,
  type AnalyticsSettingsTab,
} from "./lib/settings-tabs"
import type {
  AnalyticsInitializationState,
  AnalyticsSettingsPageProps,
  AnalyticsSettingsSiteOption,
  AnalyticsTrackerSnippet,
  AnalyticsTrackingRules,
  FunnelPageMatch,
  FunnelPageSuggestion,
  FunnelStepDefinition,
  FunnelStepType,
  GoalDefinition,
  GoalSuggestion,
  GoogleSearchConsoleProperty,
} from "./types"
import { SuggestInput } from "./ui/filter-dialog/shared"

/* ────────────────────────────────────────────────────────── */
/*  Helpers                                                   */
/* ────────────────────────────────────────────────────────── */

async function apiFetch(
  url: string,
  method: string,
  body?: unknown
): Promise<Response> {
  const headers: Record<string, string> = {
    "X-CSRF-Token": csrfToken() ?? "",
  }
  if (body !== undefined) headers["Content-Type"] = "application/json"
  return fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
}

type FunnelStepFormState = {
  name: string
  type: FunnelStepType
  match: FunnelPageMatch
  value: string
  goalKey: string
}

type GoalFormType = "custom_event" | "page_visit" | "scroll_depth"

type GoalPropertyRule = {
  key: string
  value: string
}

type GoalFormState = {
  displayName: string
  type: GoalFormType
  eventName: string
  pagePath: string
  scrollThreshold: string
  customProps: GoalPropertyRule[]
}

const FUNNEL_PAGE_MATCH_OPTIONS: Array<{
  value: FunnelPageMatch
  label: string
}> = [
  { value: "equals", label: "Equals" },
  { value: "contains", label: "Contains" },
  { value: "starts_with", label: "Starts with" },
  { value: "ends_with", label: "Ends with" },
]

function defaultFunnelStep(
  type: FunnelStepType = "page_visit"
): FunnelStepFormState {
  return {
    name: "",
    type,
    match: "equals",
    value: "",
    goalKey: "",
  }
}

function suggestedPageStep(
  suggestion: FunnelPageSuggestion
): FunnelStepFormState {
  return {
    ...defaultFunnelStep("page_visit"),
    name: suggestion.label,
    match: suggestion.match,
    value: suggestion.value,
  }
}

function suggestedGoalStep(goalKey = ""): FunnelStepFormState {
  return {
    ...defaultFunnelStep("goal"),
    name: goalKey,
    goalKey,
  }
}

function normalizeFunnelStep(
  raw: FunnelStepDefinition | string
): FunnelStepFormState {
  if (typeof raw === "string") {
    return raw.startsWith("/")
      ? { ...defaultFunnelStep(), value: raw }
      : {
          ...defaultFunnelStep(),
          type: "goal",
          goalKey: raw,
        }
  }

  const type =
    raw.type === "goal" || raw.type === "event" ? "goal" : "page_visit"
  const name =
    typeof raw.name === "string"
      ? raw.name
      : typeof raw.label === "string"
        ? raw.label
        : ""

  if (type === "goal") {
    return {
      name,
      type,
      match: "completes" as FunnelPageMatch,
      value: "",
      goalKey:
        (typeof raw.goalKey === "string" && raw.goalKey) ||
        (typeof raw.goal_key === "string" && raw.goal_key) ||
        (typeof raw.value === "string" ? raw.value : ""),
    }
  }

  const match =
    raw.match === "contains" ||
    raw.match === "starts_with" ||
    raw.match === "ends_with" ||
    raw.match === "equals"
      ? raw.match
      : "equals"

  return {
    name,
    type,
    match,
    value: typeof raw.value === "string" ? raw.value : "",
    goalKey: "",
  }
}

function funnelStepLabel(
  step: FunnelStepDefinition | FunnelStepFormState
): string {
  const normalized = normalizeFunnelStep(step)
  if (normalized.name.trim()) return normalized.name.trim()
  return normalized.type === "goal"
    ? normalized.goalKey.trim()
    : normalized.value.trim()
}

function funnelStepSummary(
  step: FunnelStepDefinition | FunnelStepFormState
): string {
  const normalized = normalizeFunnelStep(step)

  if (normalized.type === "goal") {
    return `Completes: ${normalized.goalKey.trim() || "Choose goal"}`
  }

  const matchLabel =
    FUNNEL_PAGE_MATCH_OPTIONS.find(
      (option) => option.value === normalized.match
    )?.label ?? "Equals"

  return `${matchLabel} ${normalized.value.trim() || "Choose path"}`
}

function isValidFunnelStep(step: FunnelStepFormState): boolean {
  return step.type === "goal"
    ? step.goalKey.trim() !== ""
    : step.value.trim() !== ""
}

function funnelStepToPayload(
  step: FunnelStepFormState
): Record<string, string> {
  const payload: Record<string, string> = {
    type: step.type,
    match: step.type === "goal" ? "completes" : step.match,
  }
  if (step.name.trim() !== "") payload.name = step.name.trim()
  if (step.type === "goal") {
    payload.goal_key = step.goalKey.trim()
  } else {
    payload.value = step.value.trim()
  }
  return payload
}

function defaultGoalForm(type: GoalFormType = "custom_event"): GoalFormState {
  return {
    displayName: "",
    type,
    eventName: "",
    pagePath: "",
    scrollThreshold: "75",
    customProps: [],
  }
}

function normalizeGoalDefinition(goal: GoalDefinition): GoalFormState {
  const type: GoalFormType = goal.eventName
    ? "custom_event"
    : (goal.scrollThreshold ?? -1) >= 0
      ? "scroll_depth"
      : "page_visit"

  return {
    displayName: goal.displayName ?? "",
    type,
    eventName: goal.eventName ?? "",
    pagePath: goal.pagePath ?? "",
    scrollThreshold:
      type === "scroll_depth" ? String(goal.scrollThreshold ?? 75) : "75",
    customProps: Object.entries(goal.customProps ?? {}).map(([key, value]) => ({
      key,
      value,
    })),
  }
}

function goalDisplayName(form: GoalFormState): string {
  const explicit = form.displayName.trim()
  if (explicit) return explicit
  if (form.type === "custom_event") return form.eventName.trim()
  if (form.type === "scroll_depth") return `Scroll ${form.pagePath.trim()}`
  return `Visit ${form.pagePath.trim()}`
}

function humanizeGoalEventName(name: string): string {
  const trimmed = name.trim()
  if (!trimmed) return trimmed
  if (/[A-Z]/.test(trimmed) || /[: ]/.test(trimmed)) return trimmed

  return trimmed
    .split(/[_-]+/)
    .map((segment) => {
      const lower = segment.toLowerCase()
      if (lower === "cta") return "CTA"
      if (lower === "api") return "API"
      if (lower === "utm") return "UTM"
      return lower.charAt(0).toUpperCase() + lower.slice(1)
    })
    .join(" ")
}

function normalizeGoalCustomProps(
  rules: GoalPropertyRule[]
): Record<string, string> {
  return rules.reduce<Record<string, string>>((memo, rule) => {
    const key = rule.key.trim()
    const value = rule.value.trim()
    if (key && value) memo[key] = value
    return memo
  }, {})
}

function goalFormToPayload(form: GoalFormState): {
  display_name: string
  event_name?: string
  page_path?: string
  scroll_threshold: number
  custom_props: Record<string, string>
} {
  const payload = {
    display_name: goalDisplayName(form),
    scroll_threshold: -1,
    custom_props: normalizeGoalCustomProps(form.customProps),
  } as {
    display_name: string
    event_name?: string
    page_path?: string
    scroll_threshold: number
    custom_props: Record<string, string>
  }

  if (form.type === "custom_event") {
    payload.event_name = form.eventName.trim()
  } else {
    payload.page_path = form.pagePath.trim()
    payload.scroll_threshold =
      form.type === "scroll_depth"
        ? Number.parseInt(form.scrollThreshold, 10) || 0
        : -1
  }

  return payload
}

function goalTypeLabel(goal: GoalDefinition): string {
  if (goal.eventName) return "Custom event"
  if ((goal.scrollThreshold ?? -1) >= 0) return "Scroll depth"
  return "Page visit"
}

function goalMatcherSummary(goal: GoalDefinition): string {
  if (goal.eventName) {
    const props = Object.entries(goal.customProps ?? {})
      .map(([key, value]) => `${key}=${value}`)
      .join(" · ")
    return props ? `${goal.eventName} · ${props}` : goal.eventName
  }

  if ((goal.scrollThreshold ?? -1) >= 0) {
    return `${goal.pagePath} · ${goal.scrollThreshold}%`
  }

  return goal.pagePath ?? "Page path required"
}

function CopyableField({
  label,
  value,
  mono = true,
}: {
  label: string
  value: string
  mono?: boolean
}) {
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    if (typeof navigator === "undefined" || !navigator.clipboard) return
    await navigator.clipboard.writeText(value)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1600)
  }

  return (
    <div className="group flex items-baseline justify-between gap-3 py-2">
      <span className="shrink-0 text-xs font-medium tracking-wide text-muted-foreground uppercase">
        {label}
      </span>
      <div className="flex min-w-0 items-center gap-1.5">
        <span
          className={cn("truncate text-right text-[13px]", mono && "font-mono")}
          title={value}
        >
          {value}
        </span>
        <button
          type="button"
          onClick={() => void copy()}
          className="shrink-0 rounded-xs p-0.5 text-muted-foreground/50 opacity-0 transition-all group-hover:opacity-100 hover:text-foreground"
          aria-label={`Copy ${label}`}
        >
          {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
        </button>
      </div>
    </div>
  )
}

function TrackingScriptTab({ tracker }: { tracker: AnalyticsTrackerSnippet }) {
  const [copied, setCopied] = useState(false)

  const copySnippet = async () => {
    if (typeof navigator === "undefined" || !navigator.clipboard) return

    await navigator.clipboard.writeText(tracker.snippetHtml)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1600)
  }

  return (
    <div className="space-y-4">
      {/* Code block with integrated header */}
      <div className="overflow-hidden rounded-xl border bg-zinc-950 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-2.5">
          <div className="flex items-center gap-2 text-zinc-400">
            <Code2 className="size-3.5" />
            <span className="text-xs font-medium tracking-wide">
              Tracking snippet
            </span>
          </div>
          <button
            type="button"
            onClick={() => void copySnippet()}
            className={cn(
              "flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium transition-all",
              copied
                ? "bg-emerald-500/15 text-emerald-400"
                : "text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200"
            )}
          >
            {copied ? (
              <>
                <Check className="size-3" />
                Copied
              </>
            ) : (
              <>
                <Copy className="size-3" />
                Copy
              </>
            )}
          </button>
        </div>
        <pre className="overflow-x-auto p-4 text-[13px]/6 text-zinc-300 select-all">
          <code>{tracker.snippetHtml}</code>
        </pre>
      </div>

      {/* Metadata fields */}
      <div className="rounded-xl border px-4 py-2">
        <div className="grid gap-x-10 sm:grid-cols-3">
          <CopyableField label="Website ID" value={tracker.websiteId} />
          <CopyableField label="Domain" value={tracker.domainHint} />
          <CopyableField label="Script URL" value={tracker.scriptUrl} />
        </div>
      </div>
    </div>
  )
}

function ExclusionsSection({
  rules,
  settingsDataPath,
}: {
  rules: AnalyticsTrackingRules
  settingsDataPath: string
}) {
  const [excludePaths, setExcludePaths] = useState<string[]>(rules.excludePaths)
  const [includePaths, setIncludePaths] = useState<string[]>(rules.includePaths)
  const [newExclude, setNewExclude] = useState("")
  const [newInclude, setNewInclude] = useState("")
  const [processing, setProcessing] = useState(false)

  const [prevRules, setPrevRules] = useState(rules)
  if (rules !== prevRules) {
    setPrevRules(rules)
    setExcludePaths(rules.excludePaths)
    setIncludePaths(rules.includePaths)
  }

  function normalizePath(raw: string): string | null {
    const trimmed = raw.trim()
    if (!trimmed) return null
    return trimmed.startsWith("/") ? trimmed : `/${trimmed}`
  }

  async function saveRules(include: string[], exclude: string[]) {
    setProcessing(true)
    try {
      await apiFetch(settingsDataPath, "PATCH", {
        settings: {
          tracking_rules: {
            include_paths: include,
            exclude_paths: exclude,
          },
        },
      })
      router.reload({ only: ["settings"] })
    } finally {
      setProcessing(false)
    }
  }

  function addExclude() {
    const path = normalizePath(newExclude)
    if (!path || excludePaths.includes(path)) return
    const updated = [...excludePaths, path]
    setExcludePaths(updated)
    setNewExclude("")
    void saveRules(includePaths, updated)
  }

  function removeExclude(path: string) {
    const updated = excludePaths.filter((p) => p !== path)
    setExcludePaths(updated)
    void saveRules(includePaths, updated)
  }

  function addInclude() {
    const path = normalizePath(newInclude)
    if (!path || includePaths.includes(path)) return
    const updated = [...includePaths, path]
    setIncludePaths(updated)
    setNewInclude("")
    void saveRules(updated, excludePaths)
  }

  function removeInclude(path: string) {
    const updated = includePaths.filter((p) => p !== path)
    setIncludePaths(updated)
    void saveRules(updated, excludePaths)
  }

  const defaultExcludePaths = useMemo(
    () =>
      rules.effectiveExcludePaths.filter(
        (path) => !excludePaths.includes(path)
      ),
    [excludePaths, rules.effectiveExcludePaths]
  )

  return (
    <div className="space-y-4">
      <div className="rounded-xl border bg-muted/20 px-4 py-3">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-muted-foreground">
            Use{" "}
            <code className="rounded bg-background px-1 py-0.5 font-mono text-[0.7rem]">
              *
            </code>{" "}
            for a single segment and{" "}
            <code className="rounded bg-background px-1 py-0.5 font-mono text-[0.7rem]">
              **
            </code>{" "}
            for nested paths.
          </p>
          <div className="flex flex-wrap gap-2">
            <Badge variant="outline">{excludePaths.length} excludes</Badge>
            <Badge variant="outline">
              {includePaths.length > 0
                ? `${includePaths.length} includes`
                : "allowlist off"}
            </Badge>
            <Badge variant="secondary">
              {defaultExcludePaths.length} defaults
            </Badge>
          </div>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card size="sm">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Exclude paths</CardTitle>
            <CardDescription className="text-xs">
              URL paths to skip from analytics.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <form
              onSubmit={(e) => {
                e.preventDefault()
                addExclude()
              }}
              className="flex flex-col gap-2 sm:flex-row"
            >
              <Input
                value={newExclude}
                onChange={(e) => setNewExclude(e.target.value)}
                placeholder="/admin or /admin/*"
                className="text-sm sm:flex-1"
              />
              <Button
                type="submit"
                variant="secondary"
                disabled={!newExclude.trim() || processing}
              >
                <Plus className="size-3.5" />
                Add
              </Button>
            </form>

            {excludePaths.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {excludePaths.map((path) => (
                  <Badge
                    key={path}
                    variant="secondary"
                    className="group flex max-w-full items-center gap-1 px-2.5 py-1 text-xs"
                  >
                    <span className="truncate text-sm">{path}</span>
                    <Button
                      variant="ghost"
                      size="icon-xs"
                      className="size-5 rounded-full opacity-60 transition-opacity group-hover:opacity-100"
                      onClick={() => removeExclude(path)}
                      disabled={processing}
                      aria-label={`Remove exclusion ${path}`}
                    >
                      <X className="size-3.5" />
                    </Button>
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">
                No custom exclusions. Internal defaults still apply.
              </p>
            )}
          </CardContent>
        </Card>

        <Card size="sm">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Include paths</CardTitle>
            <CardDescription className="text-xs">
              Optional allowlist. When set, only matching paths are tracked.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <form
              onSubmit={(e) => {
                e.preventDefault()
                addInclude()
              }}
              className="flex flex-col gap-2 sm:flex-row"
            >
              <Input
                value={newInclude}
                onChange={(e) => setNewInclude(e.target.value)}
                placeholder="/blog/** or /docs/**"
                className="text-sm sm:flex-1"
              />
              <Button
                type="submit"
                variant="secondary"
                disabled={!newInclude.trim() || processing}
              >
                <Plus className="size-3.5" />
                Add
              </Button>
            </form>

            {includePaths.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {includePaths.map((path) => (
                  <Badge
                    key={path}
                    variant="secondary"
                    className="group flex max-w-full items-center gap-1 px-2.5 py-1 text-xs"
                  >
                    <span className="truncate text-sm">{path}</span>
                    <Button
                      variant="ghost"
                      size="icon-xs"
                      className="size-5 rounded-full opacity-60 transition-opacity group-hover:opacity-100"
                      onClick={() => removeInclude(path)}
                      disabled={processing}
                      aria-label={`Remove include ${path}`}
                    >
                      <X className="size-3.5" />
                    </Button>
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">
                All paths are tracked (no allowlist set).
              </p>
            )}
          </CardContent>
        </Card>
      </div>

      <Card size="sm">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Internal defaults</CardTitle>
          <CardDescription className="text-xs">
            Always excluded from tracking.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-1.5">
            {defaultExcludePaths.map((path) => (
              <Badge key={path} variant="secondary" className="text-xs">
                {path}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Delete confirmation dialog                                */
/* ────────────────────────────────────────────────────────── */

function DeleteConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  onConfirm,
  processing,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  title: string
  description: string
  onConfirm: () => void
  processing?: boolean
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button
            variant="destructive"
            disabled={processing}
            onClick={onConfirm}
          >
            Delete
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Goal form dialog                                          */
/* ────────────────────────────────────────────────────────── */

function GoalFormDialog({
  open,
  onOpenChange,
  initialGoal,
  eventSuggestions,
  onSave,
  processing,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  initialGoal: GoalDefinition | null
  eventSuggestions: GoalSuggestion[]
  onSave: (goal: ReturnType<typeof goalFormToPayload>) => void
  processing?: boolean
}) {
  const [form, setForm] = useState<GoalFormState>(
    initialGoal ? normalizeGoalDefinition(initialGoal) : defaultGoalForm()
  )

  const [key, setKey] = useState("goal-form-closed")
  const nextKey = `${open}-${initialGoal?.displayName ?? "new"}`
  if (nextKey !== key) {
    setForm(
      initialGoal ? normalizeGoalDefinition(initialGoal) : defaultGoalForm()
    )
    setKey(nextKey)
  }

  const valid =
    form.type === "custom_event"
      ? form.eventName.trim() !== ""
      : form.pagePath.trim() !== ""

  const eventFetcher = useCallback(
    async (q: string) => {
      const needle = q.trim().toLowerCase()
      return eventSuggestions
        .filter((entry) => !needle || entry.name.toLowerCase().includes(needle))
        .map((entry) => ({
          label: entry.name,
          value: entry.name,
        }))
    },
    [eventSuggestions]
  )

  function updateCustomProp(index: number, patch: Partial<GoalPropertyRule>) {
    setForm((current) => ({
      ...current,
      customProps: current.customProps.map((rule, ruleIndex) =>
        ruleIndex === index ? { ...rule, ...patch } : rule
      ),
    }))
  }

  function removeCustomProp(index: number) {
    setForm((current) => ({
      ...current,
      customProps: current.customProps.filter(
        (_, ruleIndex) => ruleIndex !== index
      ),
    }))
  }

  function addCustomProp() {
    setForm((current) => ({
      ...current,
      customProps: [...current.customProps, { key: "", value: "" }],
    }))
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[88vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{initialGoal ? "Edit goal" : "Add goal"}</DialogTitle>
          <DialogDescription>
            Keep managed goals explicit, but start from detected event names
            whenever possible.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          <Field>
            <FieldLabel>Goal type</FieldLabel>
            <Tabs
              value={form.type}
              onValueChange={(value) =>
                setForm((current) => ({
                  ...current,
                  type: value as GoalFormType,
                }))
              }
            >
              <TabsList variant="line">
                <TabsTrigger value="custom_event">Custom event</TabsTrigger>
                <TabsTrigger value="page_visit">Page visit</TabsTrigger>
                <TabsTrigger value="scroll_depth">Scroll depth</TabsTrigger>
              </TabsList>
            </Tabs>
          </Field>

          <div className="grid gap-4 sm:grid-cols-2">
            <Field>
              <FieldLabel>Display name</FieldLabel>
              <Input
                value={form.displayName}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    displayName: event.target.value,
                  }))
                }
                placeholder={
                  form.type === "custom_event"
                    ? "Signup"
                    : form.type === "scroll_depth"
                      ? "Scroll /pricing"
                      : "Visit /pricing"
                }
              />
            </Field>

            {form.type === "custom_event" ? (
              <Field>
                <FieldLabel>Event name</FieldLabel>
                <SuggestInput
                  value={form.eventName}
                  onChange={(value: string) =>
                    setForm((current) => ({
                      ...current,
                      eventName: value,
                    }))
                  }
                  fetcher={eventFetcher}
                  placeholder={
                    eventSuggestions[0]?.name
                      ? `e.g. ${eventSuggestions[0].name}`
                      : "signup"
                  }
                />
              </Field>
            ) : (
              <Field>
                <FieldLabel>Page path</FieldLabel>
                <Input
                  value={form.pagePath}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      pagePath: event.target.value,
                    }))
                  }
                  placeholder="/register"
                />
              </Field>
            )}
          </div>

          {form.type === "scroll_depth" ? (
            <Field>
              <FieldLabel>Scroll threshold</FieldLabel>
              <Input
                type="number"
                min={0}
                max={100}
                value={form.scrollThreshold}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    scrollThreshold: event.target.value,
                  }))
                }
                placeholder="75"
              />
            </Field>
          ) : null}

          {form.type === "custom_event" ? (
            <div className="space-y-3 rounded-lg border bg-muted/20 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-medium">Property rules</p>
                  <p className="text-xs text-muted-foreground">
                    Optional. Narrow this goal to a specific event variant like{" "}
                    <code className="rounded bg-background px-1 py-0.5 font-mono text-[0.7rem]">
                      plan=pro
                    </code>
                    .
                  </p>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={addCustomProp}
                  disabled={form.customProps.length >= 3}
                >
                  <Plus className="size-3.5" />
                  Add property
                </Button>
              </div>

              {form.customProps.length > 0 ? (
                <div className="space-y-2">
                  {form.customProps.map((rule, index) => (
                    <div
                      key={`goal-prop-${index}`}
                      className="grid gap-2 sm:grid-cols-[1fr_1fr_auto]"
                    >
                      <Input
                        value={rule.key}
                        onChange={(event) =>
                          updateCustomProp(index, { key: event.target.value })
                        }
                        placeholder="plan"
                      />
                      <Input
                        value={rule.value}
                        onChange={(event) =>
                          updateCustomProp(index, { value: event.target.value })
                        }
                        placeholder="pro"
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        onClick={() => removeCustomProp(index)}
                        aria-label="Remove property rule"
                      >
                        <Trash2 className="size-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-xs text-muted-foreground">
                  No property rules yet. Basic event goals do not need any.
                </p>
              )}
            </div>
          ) : null}
        </div>

        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button
            disabled={!valid || processing}
            onClick={() => {
              if (!valid) return
              onSave(goalFormToPayload(form))
            }}
          >
            {initialGoal ? "Update goal" : "Save goal"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Goals tab                                                 */
/* ────────────────────────────────────────────────────────── */

function GoalsTab({
  goalDefinitions,
  goalSuggestions,
  settingsDataPath,
}: {
  goalDefinitions: GoalDefinition[]
  goalSuggestions: GoalSuggestion[]
  settingsDataPath: string
}) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingIndex, setEditingIndex] = useState<number | null>(null)
  const [deletingIndex, setDeletingIndex] = useState<number | null>(null)
  const [processing, setProcessing] = useState(false)

  const editingGoal =
    editingIndex !== null ? (goalDefinitions[editingIndex] ?? null) : null

  async function persistGoalDefinitions(nextDefinitions: GoalDefinition[]) {
    setProcessing(true)
    try {
      const response = await apiFetch(settingsDataPath, "PATCH", {
        settings: {
          goal_definitions: nextDefinitions.map((goal) => ({
            display_name: goal.displayName,
            event_name: goal.eventName ?? "",
            page_path: goal.pagePath ?? "",
            scroll_threshold:
              goal.scrollThreshold === null ||
              goal.scrollThreshold === undefined
                ? -1
                : goal.scrollThreshold,
            custom_props: goal.customProps ?? {},
          })),
        },
      })

      if (response.ok) {
        router.reload({ only: ["settings"] })
        setDialogOpen(false)
        setEditingIndex(null)
        setDeletingIndex(null)
      }
    } finally {
      setProcessing(false)
    }
  }

  function mergeGoalSuggestion(name: string) {
    const exists = goalDefinitions.some(
      (goal) => goal.eventName === name || goal.displayName === name
    )
    if (exists) return

    void persistGoalDefinitions([
      ...goalDefinitions,
      {
        displayName: humanizeGoalEventName(name),
        eventName: name,
        customProps: {},
      },
    ])
  }

  function addAllSuggestions() {
    const existingNames = new Set(
      goalDefinitions.flatMap(
        (goal) => [goal.displayName, goal.eventName].filter(Boolean) as string[]
      )
    )

    const additions = goalSuggestions
      .filter((suggestion) => !existingNames.has(suggestion.name))
      .map<GoalDefinition>((suggestion) => ({
        displayName: humanizeGoalEventName(suggestion.name),
        eventName: suggestion.name,
        customProps: {},
      }))

    if (additions.length === 0) return
    void persistGoalDefinitions([...goalDefinitions, ...additions])
  }

  function saveGoal(nextGoal: ReturnType<typeof goalFormToPayload>) {
    const normalized: GoalDefinition = {
      displayName: nextGoal.display_name,
      eventName: nextGoal.event_name ?? null,
      pagePath: nextGoal.page_path ?? null,
      scrollThreshold: nextGoal.scroll_threshold,
      customProps: nextGoal.custom_props,
    }

    const nextDefinitions =
      editingIndex === null
        ? [...goalDefinitions, normalized]
        : goalDefinitions.map((goal, index) =>
            index === editingIndex ? normalized : goal
          )

    void persistGoalDefinitions(nextDefinitions)
  }

  function deleteGoal() {
    if (deletingIndex === null) return
    void persistGoalDefinitions(
      goalDefinitions.filter((_, index) => index !== deletingIndex)
    )
  }

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-sm text-muted-foreground">
              {goalDefinitions.length}{" "}
              {goalDefinitions.length === 1 ? "managed goal" : "managed goals"}
            </p>
            <p className="text-xs text-muted-foreground">
              Track custom events freely, then promote the useful ones into
              stable goals for reporting and funnels.
            </p>
          </div>
          <Button
            size="sm"
            onClick={() => {
              setEditingIndex(null)
              setDialogOpen(true)
            }}
          >
            <Plus className="size-3.5" />
            Add goal
          </Button>
        </div>

        {goalSuggestions.length > 0 ? (
          <Card size="sm">
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <CardTitle className="text-sm">
                    Detected from recent events
                  </CardTitle>
                  <CardDescription className="text-xs">
                    These event names were seen recently. Add them as managed
                    goals with one click.
                  </CardDescription>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={addAllSuggestions}
                  disabled={processing}
                >
                  <Plus className="size-3.5" />
                  Add all
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-2">
              {goalSuggestions.map((suggestion) => (
                <div
                  key={suggestion.name}
                  className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">
                      {humanizeGoalEventName(suggestion.name)}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      <span className="font-mono">{suggestion.name}</span>
                      {" · "}seen in {suggestion.recentVisits} recent{" "}
                      {suggestion.recentVisits === 1 ? "visit" : "visits"}
                    </p>
                  </div>
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    onClick={() => mergeGoalSuggestion(suggestion.name)}
                    disabled={processing}
                  >
                    Add
                  </Button>
                </div>
              ))}
            </CardContent>
          </Card>
        ) : (
          <Card size="sm">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">
                Detected from recent events
              </CardTitle>
              <CardDescription className="text-xs">
                No recent custom events detected yet. Once your site sends
                events like{" "}
                <code className="rounded bg-background px-1 py-0.5 font-mono text-[0.7rem]">
                  window.analytics("signup")
                </code>
                , they will appear here as one-click suggestions.
              </CardDescription>
            </CardHeader>
          </Card>
        )}

        {goalDefinitions.length > 0 ? (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="hidden sm:table-cell">Match</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {goalDefinitions.map((goal, index) => (
                  <TableRow key={`${goal.displayName}-${index}`}>
                    <TableCell className="font-medium">
                      {goal.displayName}
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline">{goalTypeLabel(goal)}</Badge>
                    </TableCell>
                    <TableCell className="hidden text-muted-foreground sm:table-cell">
                      <span className="text-xs">
                        {goalMatcherSummary(goal)}
                      </span>
                    </TableCell>
                    <TableCell>
                      <DropdownMenu>
                        <DropdownMenuTrigger
                          render={<Button variant="ghost" size="icon-sm" />}
                        >
                          <MoreHorizontal className="size-4" />
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem
                            onClick={() => {
                              setEditingIndex(index)
                              setDialogOpen(true)
                            }}
                          >
                            <Pencil className="size-3.5" />
                            Edit
                          </DropdownMenuItem>
                          <DropdownMenuSeparator />
                          <DropdownMenuItem
                            variant="destructive"
                            onClick={() => setDeletingIndex(index)}
                          >
                            <Trash2 className="size-3.5" />
                            Delete
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        ) : (
          <div className="rounded-lg border border-dashed p-8 text-center">
            <Filter className="mx-auto mb-3 size-8 text-muted-foreground/50" />
            <p className="font-medium">No goals configured</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Promote a detected event above, or add a managed goal manually for
              page visits, scrolls, or property-matched events.
            </p>
          </div>
        )}
      </div>

      <GoalFormDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open)
          if (!open) setEditingIndex(null)
        }}
        initialGoal={editingGoal}
        eventSuggestions={goalSuggestions}
        onSave={saveGoal}
        processing={processing}
      />

      <DeleteConfirmDialog
        open={deletingIndex !== null}
        onOpenChange={(open) => {
          if (!open) setDeletingIndex(null)
        }}
        title="Delete goal"
        description={`Delete "${deletingIndex !== null ? (goalDefinitions[deletingIndex]?.displayName ?? "this goal") : "this goal"}"? This cannot be undone.`}
        onConfirm={deleteGoal}
        processing={processing}
      />
    </>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Funnel form dialog                                        */
/* ────────────────────────────────────────────────────────── */

const MAX_FUNNEL_STEPS = 8

function FunnelFormDialog({
  open,
  onOpenChange,
  initialName,
  initialSteps,
  goalNames,
  pageSuggestions,
  onSave,
  processing,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  initialName: string
  initialSteps: FunnelStepDefinition[]
  goalNames: string[]
  pageSuggestions: FunnelPageSuggestion[]
  onSave: (name: string, steps: Array<Record<string, string>>) => void
  processing?: boolean
}) {
  const [name, setName] = useState(initialName)
  const [steps, setSteps] = useState<FunnelStepFormState[]>(
    initialSteps.length > 0 ? initialSteps.map(normalizeFunnelStep) : []
  )

  /* Builder form state — one step at a time */
  const [stepName, setStepName] = useState("")
  const [stepType, setStepType] = useState<FunnelStepType>("page_visit")
  const [stepMatch, setStepMatch] = useState<FunnelPageMatch>("equals")
  const [stepValue, setStepValue] = useState("")
  const [stepGoalKey, setStepGoalKey] = useState("")
  const [editingStepIndex, setEditingStepIndex] = useState<number | null>(null)

  const goalFetcher = useCallback(
    async (q: string) => {
      const needle = q.trim().toLowerCase()
      return goalNames
        .filter((g) => !needle || g.toLowerCase().includes(needle))
        .map((g) => ({ label: g, value: g }))
    },
    [goalNames]
  )

  /* Drag-and-drop state */
  const [dragIndex, setDragIndex] = useState<number | null>(null)

  const [key, setKey] = useState(`${initialName}-${open}`)
  const nextKey = `${initialName}-${open}`
  if (nextKey !== key) {
    setName(initialName)
    setSteps(
      initialSteps.length > 0 ? initialSteps.map(normalizeFunnelStep) : []
    )
    setStepName("")
    setStepType("page_visit")
    setStepMatch("equals")
    setStepValue("")
    setStepGoalKey("")
    setEditingStepIndex(null)
    setDragIndex(null)
    setKey(nextKey)
  }

  const isEdit = initialName !== ""
  const valid =
    name.trim() !== "" && steps.filter(isValidFunnelStep).length >= 2
  const canAddStep = steps.length < MAX_FUNNEL_STEPS
  const currentStepValid =
    stepType === "goal" ? stepGoalKey.trim() !== "" : stepValue.trim() !== ""

  function resetBuilder() {
    setStepName("")
    setStepType("page_visit")
    setStepMatch("equals")
    setStepValue("")
    setStepGoalKey("")
    setEditingStepIndex(null)
  }

  function applyBuilderStep(step: FunnelStepFormState) {
    if (!isValidFunnelStep(step)) return

    if (editingStepIndex === null) {
      if (!canAddStep) return
      setSteps((current) => [...current, step])
    } else {
      setSteps((current) =>
        current.map((existing, index) =>
          index === editingStepIndex ? step : existing
        )
      )
    }
    resetBuilder()
  }

  function addStep() {
    if (!canAddStep || !currentStepValid) return
    applyBuilderStep({
      name: stepName,
      type: stepType,
      match: (stepType === "goal" ? "completes" : stepMatch) as FunnelPageMatch,
      value: stepType === "page_visit" ? stepValue : "",
      goalKey: stepType === "goal" ? stepGoalKey : "",
    })
  }

  function handleDrop(targetIndex: number) {
    if (dragIndex === null || dragIndex === targetIndex) return
    setSteps((current) => {
      const next = [...current]
      const [removed] = next.splice(dragIndex, 1)
      next.splice(targetIndex, 0, removed)
      return next
    })
    setDragIndex(null)
  }

  function addSuggested(step: FunnelStepFormState) {
    applyBuilderStep(step)
  }

  function editStep(index: number) {
    const step = steps[index]
    if (!step) return

    setStepName(step.name)
    setStepType(step.type)
    setStepMatch(step.type === "goal" ? "equals" : step.match)
    setStepValue(step.value)
    setStepGoalKey(step.goalKey)
    setEditingStepIndex(index)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="max-h-[88vh] gap-0 overflow-y-auto border border-border/70 bg-background p-0 shadow-2xl sm:max-w-4xl"
      >
        <div className="border-b border-border/80 bg-muted/20 px-5 py-4 sm:px-6">
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1 space-y-3">
              <h2 className="text-base font-semibold text-foreground">
                {isEdit ? "Edit funnel" : "Add funnel"}
              </h2>
              <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
                <span className="shrink-0 text-sm font-medium text-foreground">
                  Funnel name
                </span>
                <Input
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g., Onboarding, Purchase flow"
                  className="h-10 bg-background"
                />
              </div>
            </div>
            <DialogClose
              render={
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="mt-0.5 shrink-0 rounded-full border border-transparent text-muted-foreground hover:border-border hover:bg-background"
                />
              }
            >
              <X className="size-4" />
              <span className="sr-only">Close</span>
            </DialogClose>
          </div>
        </div>

        <div className="grid gap-5 px-5 py-5 sm:grid-cols-[minmax(0,1.05fr)_minmax(20rem,0.95fr)] sm:px-6">
          <section className="rounded-2xl border border-border/70 bg-background p-4 sm:p-5">
            <div className="space-y-1">
              <h3 className="font-semibold tracking-tight">Add new step</h3>
              <p className="text-xs text-muted-foreground">
                Define the next action visitors should take in this funnel.
              </p>
            </div>

            <div className="mt-4 space-y-4">
              <Field>
                <FieldLabel>Step name</FieldLabel>
                <Input
                  value={stepName}
                  onChange={(e) => setStepName(e.target.value)}
                  placeholder="Step name (optional)"
                />
              </Field>

              <Tabs
                value={stepType}
                onValueChange={(v) => setStepType(v as FunnelStepType)}
              >
                <TabsList variant="line">
                  <TabsTrigger value="page_visit">Page visit</TabsTrigger>
                  <TabsTrigger value="goal">Goal</TabsTrigger>
                </TabsList>
              </Tabs>

              {stepType === "page_visit" ? (
                <Field>
                  <FieldLabel>Where URL</FieldLabel>
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                    <Select
                      value={stepMatch}
                      onValueChange={(v) => setStepMatch(v as FunnelPageMatch)}
                    >
                      <SelectTrigger className="w-full shrink-0 sm:w-[140px]">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {FUNNEL_PAGE_MATCH_OPTIONS.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <Input
                      value={stepValue}
                      onChange={(e) => setStepValue(e.target.value)}
                      placeholder="/pricing"
                      className="flex-1"
                    />
                  </div>
                </Field>
              ) : (
                <Field>
                  <FieldLabel>Visitor completes</FieldLabel>
                  <SuggestInput
                    value={stepGoalKey}
                    onChange={setStepGoalKey}
                    fetcher={goalFetcher}
                    placeholder={
                      goalNames[0] ? `e.g. ${goalNames[0]}` : "Goal key"
                    }
                  />
                </Field>
              )}

              <Button
                onClick={addStep}
                disabled={
                  (!canAddStep && editingStepIndex === null) ||
                  !currentStepValid
                }
                className="h-10 w-full"
              >
                <Plus className="size-3.5" />
                {editingStepIndex === null ? "Add step" : "Update step"}
              </Button>

              {editingStepIndex !== null ? (
                <Button
                  type="button"
                  variant="ghost"
                  className="h-9 w-full"
                  onClick={resetBuilder}
                >
                  Cancel editing step {editingStepIndex + 1}
                </Button>
              ) : null}

              <div className="space-y-2 border-t border-border/60 pt-4">
                <p className="text-xs font-medium tracking-[0.12em] text-muted-foreground uppercase">
                  Suggested steps
                </p>
                <div className="flex flex-wrap gap-1.5">
                  {pageSuggestions.map((s) => (
                    <Button
                      key={`${s.match}:${s.value}`}
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={!canAddStep && editingStepIndex === null}
                      onClick={() => addSuggested(suggestedPageStep(s))}
                      className="rounded-full"
                    >
                      {s.label}
                    </Button>
                  ))}
                  {goalNames.slice(0, 4).map((g) => (
                    <Button
                      key={g}
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={!canAddStep && editingStepIndex === null}
                      onClick={() => addSuggested(suggestedGoalStep(g))}
                      className="rounded-full"
                    >
                      {g}
                    </Button>
                  ))}
                </div>
              </div>
            </div>
          </section>

          <section className="rounded-2xl border border-border/70 bg-muted/[0.22] p-4 sm:p-5">
            <div className="flex items-end justify-between gap-3">
              <div className="space-y-1">
                <h3 className="font-semibold tracking-tight">Funnel steps</h3>
                <p className="text-xs text-muted-foreground">
                  Click a step to edit it. Drag to reorder and keep the journey
                  short.
                </p>
              </div>
              <Badge variant="secondary" className="rounded-full px-2.5 py-1">
                {steps.length}/{MAX_FUNNEL_STEPS}
              </Badge>
            </div>

            <div className="mt-4">
              {steps.length === 0 ? (
                <div className="flex min-h-64 flex-col items-center justify-center rounded-2xl border border-dashed border-border/70 bg-background/80 px-6 text-center">
                  <div className="rounded-full border border-border/70 bg-muted/50 px-3 py-1 text-[0.7rem] font-medium tracking-[0.16em] text-muted-foreground uppercase">
                    Empty canvas
                  </div>
                  <p className="mt-4 text-sm font-medium text-foreground">
                    No steps yet
                  </p>
                  <p className="mt-1 max-w-xs text-sm text-muted-foreground">
                    Add a page visit or goal on the left to start shaping this
                    conversion path.
                  </p>
                </div>
              ) : (
                <div className="space-y-2">
                  {steps.map((step, i) => (
                    <div
                      key={i}
                      draggable
                      onDragStart={() => setDragIndex(i)}
                      onDragOver={(e) => e.preventDefault()}
                      onDrop={() => handleDrop(i)}
                      onDragEnd={() => setDragIndex(null)}
                      className={cn(
                        "flex cursor-grab items-center gap-3 rounded-2xl border border-border/70 bg-background p-3.5 transition-opacity active:cursor-grabbing",
                        dragIndex === i && "opacity-40",
                        editingStepIndex === i &&
                          "border-primary/60 ring-1 ring-primary/30"
                      )}
                      onClick={() => editStep(i)}
                    >
                      <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold text-muted-foreground">
                        {i + 1}
                      </div>
                      <GripVertical className="size-4 shrink-0 text-muted-foreground/40" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">
                          {funnelStepLabel(step) || "Untitled step"}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                          {step.type === "goal" ? "Goal" : "Page visit"}
                          {" \u00b7 "}
                          {funnelStepSummary(step)}
                        </p>
                      </div>
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="rounded-full text-muted-foreground hover:bg-muted"
                        onClick={(event) => {
                          event.stopPropagation()
                          setSteps((s) => s.filter((_, idx) => idx !== i))
                          if (editingStepIndex === i) {
                            resetBuilder()
                          } else if (
                            editingStepIndex !== null &&
                            editingStepIndex > i
                          ) {
                            setEditingStepIndex(editingStepIndex - 1)
                          }
                        }}
                      >
                        <X className="size-3.5" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </section>
        </div>

        <DialogFooter className="mx-0 mb-0 items-center px-5 py-4 sm:justify-end sm:px-6">
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button
            disabled={!valid || processing}
            onClick={() =>
              onSave(
                name.trim(),
                steps.filter(isValidFunnelStep).map(funnelStepToPayload)
              )
            }
          >
            {isEdit ? "Update funnel" : "Create funnel"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Funnels tab                                               */
/* ────────────────────────────────────────────────────────── */

function FunnelsTab({
  funnels,
  goalNames,
  pageSuggestions,
  funnelsPath,
}: {
  funnels: AnalyticsSettingsPageProps["funnels"]
  goalNames: string[]
  pageSuggestions: FunnelPageSuggestion[]
  funnelsPath: string
}) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<
    AnalyticsSettingsPageProps["funnels"][number] | null
  >(null)
  const [deleting, setDeleting] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const editSteps = useMemo(() => (editing ? editing.steps : []), [editing])

  async function handleSave(
    name: string,
    steps: Array<Record<string, string>>
  ) {
    setProcessing(true)
    const method = editing ? "PATCH" : "POST"
    const url = editing
      ? `${funnelsPath}/${encodeURIComponent(editing.name)}`
      : funnelsPath
    const res = await apiFetch(url, method, {
      funnel: { name, steps },
    })
    setProcessing(false)
    if (res.ok) {
      router.reload()
      setDialogOpen(false)
      setEditing(null)
    }
  }

  async function handleDelete() {
    if (!deleting) return
    setProcessing(true)
    const res = await apiFetch(
      `${funnelsPath}/${encodeURIComponent(deleting)}`,
      "DELETE"
    )
    setProcessing(false)
    if (res.ok) {
      router.reload()
      setDeleting(null)
    }
  }

  function stepPreview(steps: FunnelStepDefinition[]) {
    const labels = steps.map(funnelStepLabel).filter(Boolean).slice(0, 3)
    const preview = labels.join(" \u2192 ")
    return steps.length > 3 ? `${preview} \u2192 \u2026` : preview
  }

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">
            {funnels.length} {funnels.length === 1 ? "funnel" : "funnels"}
          </p>
          <Button
            size="sm"
            onClick={() => {
              setEditing(null)
              setDialogOpen(true)
            }}
          >
            <Plus className="size-3.5" />
            Add funnel
          </Button>
        </div>

        {funnels.length > 0 ? (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Steps</TableHead>
                  <TableHead className="hidden sm:table-cell">
                    Preview
                  </TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {funnels.map((funnel) => (
                  <TableRow key={funnel.name}>
                    <TableCell className="font-medium">{funnel.name}</TableCell>
                    <TableCell>
                      <Badge variant="outline">
                        {funnel.steps.length}{" "}
                        {funnel.steps.length === 1 ? "step" : "steps"}
                      </Badge>
                    </TableCell>
                    <TableCell className="hidden text-muted-foreground sm:table-cell">
                      <span className="text-xs">
                        {stepPreview(funnel.steps)}
                      </span>
                    </TableCell>
                    <TableCell>
                      <DropdownMenu>
                        <DropdownMenuTrigger
                          render={<Button variant="ghost" size="icon-sm" />}
                        >
                          <MoreHorizontal className="size-4" />
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem
                            onClick={() => {
                              setEditing(funnel)
                              setDialogOpen(true)
                            }}
                          >
                            <Pencil className="size-3.5" />
                            Edit
                          </DropdownMenuItem>
                          <DropdownMenuSeparator />
                          <DropdownMenuItem
                            variant="destructive"
                            onClick={() => setDeleting(funnel.name)}
                          >
                            <Trash2 className="size-3.5" />
                            Delete
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        ) : (
          <div className="rounded-lg border border-dashed p-8 text-center">
            <Filter className="mx-auto mb-3 size-8 text-muted-foreground/50" />
            <p className="font-medium">No funnels configured</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Funnels track multi-step paths to see where visitors drop off.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-4"
              onClick={() => {
                setEditing(null)
                setDialogOpen(true)
              }}
            >
              <Plus className="size-3.5" />
              Create a funnel
            </Button>
          </div>
        )}
      </div>

      <FunnelFormDialog
        open={dialogOpen}
        onOpenChange={(v) => {
          setDialogOpen(v)
          if (!v) setEditing(null)
        }}
        initialName={editing?.name ?? ""}
        initialSteps={editSteps}
        goalNames={goalNames}
        pageSuggestions={pageSuggestions}
        onSave={handleSave}
        processing={processing}
      />

      <DeleteConfirmDialog
        open={!!deleting}
        onOpenChange={(v) => {
          if (!v) setDeleting(null)
        }}
        title="Delete funnel"
        description={`Delete "${deleting}"? This cannot be undone.`}
        onConfirm={handleDelete}
        processing={processing}
      />
    </>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  GSC helpers                                               */
/* ────────────────────────────────────────────────────────── */

function statusBadge(connected: boolean, configured: boolean) {
  if (configured) return <Badge>Connected</Badge>
  if (connected) return <Badge variant="secondary">Property required</Badge>
  return <Badge variant="outline">Disconnected</Badge>
}

function syncBadgeEl(
  gsc: AnalyticsSettingsPageProps["settings"]["googleSearchConsole"]
) {
  if (gsc.syncInProgress) return <Badge variant="secondary">Syncing</Badge>
  if (gsc.syncError) return <Badge variant="destructive">Sync failed</Badge>
  if (gsc.syncStale) return <Badge variant="outline">Needs refresh</Badge>
  if (gsc.lastSyncedAt) return <Badge>Up to date</Badge>
  return <Badge variant="outline">Not synced</Badge>
}

function propertyDescription(p: GoogleSearchConsoleProperty) {
  return `${p.type === "domain" ? "Domain" : "URL prefix"} \u00b7 ${p.permissionLevel}`
}

function formatGoogleSearchConsolePropertyLabel(identifier?: string | null) {
  if (!identifier) return null
  if (identifier.startsWith("sc-domain:")) {
    return identifier.slice("sc-domain:".length)
  }

  try {
    const url = new URL(identifier)
    return `${url.host}${url.pathname === "/" ? "" : url.pathname}`
  } catch {
    return identifier
  }
}

function googleSearchConsolePropertyLabel(
  identifier: string | null | undefined,
  properties: GoogleSearchConsoleProperty[]
) {
  if (!identifier) return null

  return (
    properties.find((property) => property.identifier === identifier)?.label ??
    formatGoogleSearchConsolePropertyLabel(identifier)
  )
}

function googleSearchConsoleDateLabel(value?: string | null) {
  return value ? formatCalendarDay(value) : "Not available"
}

function googleSearchConsoleDateTimeLabel(value?: string | null) {
  return value ? formatDateTime(value) : "Not synced yet"
}

function googleSearchConsoleSyncCoverage(
  gsc: AnalyticsSettingsPageProps["settings"]["googleSearchConsole"]
) {
  if (!gsc.syncedFrom || !gsc.syncedTo) return "No completed sync yet"
  return `${googleSearchConsoleDateLabel(gsc.syncedFrom)} to ${googleSearchConsoleDateLabel(gsc.syncedTo)}`
}

/* ────────────────────────────────────────────────────────── */
/*  Google Search Console tab                                 */
/* ────────────────────────────────────────────────────────── */

function GoogleIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 48 48"
      className={className}
    >
      <path
        fill="#EA4335"
        d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
      />
      <path
        fill="#4285F4"
        d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
      />
      <path
        fill="#FBBC05"
        d="M10.53 28.59a14.5 14.5 0 0 1 0-9.18l-7.98-6.19a24.0 24.0 0 0 0 0 21.56l7.98-6.19z"
      />
      <path
        fill="#34A853"
        d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
      />
    </svg>
  )
}

function GoogleSearchConsoleTab({
  gsc,
  connectPath,
  connectionPath,
  syncPath,
}: {
  gsc: AnalyticsSettingsPageProps["settings"]["googleSearchConsole"]
  connectPath: string
  connectionPath: string
  syncPath: string
}) {
  const [propertyId, setPropertyId] = useState(gsc.propertyIdentifier ?? "")
  const currentPropertyLabel = googleSearchConsolePropertyLabel(
    gsc.propertyIdentifier,
    gsc.properties
  )
  const selectedProperty =
    gsc.properties.find((property) => property.identifier === propertyId) ??
    null

  if (!gsc.available) {
    return (
      <Alert>
        <AlertDescription>
          OAuth credentials are not configured for this environment.
        </AlertDescription>
      </Alert>
    )
  }

  if (!gsc.connected) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <GoogleIcon className="size-4" />
            Google Search Console
          </CardTitle>
          <CardDescription>
            Discover what Google search terms drive traffic to your website.
            Search Console powers query and SEO reports for this site.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <form method="post" action={connectPath}>
            <input
              type="hidden"
              name="authenticity_token"
              value={csrfToken()}
              readOnly
            />
            <Button type="submit">
              <Link2 className="size-4" />
              Connect Google Search Console
            </Button>
          </form>
          <p className="text-sm text-muted-foreground">
            Make sure you have access to the verified property in Google Search
            Console.
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <CardTitle className="flex items-center gap-2">
                <GoogleIcon className="size-4" />
                Google Search Console
              </CardTitle>
              {statusBadge(gsc.connected, gsc.configured)}
            </div>
            <CardDescription>
              {gsc.accountEmail ?? "Connected"}
              {currentPropertyLabel ? ` \u00b7 ${currentPropertyLabel}` : ""}
            </CardDescription>
          </div>
          <form method="post" action={connectionPath}>
            <input
              type="hidden"
              name="authenticity_token"
              value={csrfToken()}
              readOnly
            />
            <input type="hidden" name="_method" value="delete" readOnly />
            <Button
              type="submit"
              variant="ghost"
              size="sm"
              className="text-muted-foreground hover:text-destructive"
            >
              Disconnect
            </Button>
          </form>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {gsc.propertiesError ? (
          <Alert>
            <AlertDescription>{gsc.propertiesError}</AlertDescription>
          </Alert>
        ) : null}
        {gsc.syncError ? (
          <Alert>
            <AlertCircle className="size-4" />
            <AlertDescription>{gsc.syncError}</AlertDescription>
          </Alert>
        ) : null}

        {gsc.properties.length > 0 ? (
          <form method="post" action={connectionPath} className="space-y-2">
            <input
              type="hidden"
              name="authenticity_token"
              value={csrfToken()}
              readOnly
            />
            <input type="hidden" name="_method" value="patch" readOnly />
            <FieldLabel>Property</FieldLabel>
            <div className="flex items-center gap-3">
              <Select
                value={propertyId}
                onValueChange={(v) => setPropertyId(v ?? "")}
              >
                <SelectTrigger className="flex-1">
                  <SelectValue placeholder="Choose a property">
                    {(value) => {
                      const label = googleSearchConsolePropertyLabel(
                        typeof value === "string" ? value : null,
                        gsc.properties
                      )

                      return (
                        <span className={cn(!label && "text-muted-foreground")}>
                          {label ?? "Choose a property"}
                        </span>
                      )
                    }}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent align="start" className="max-h-80">
                  {gsc.properties.map((p) => (
                    <SelectItem
                      key={p.identifier}
                      value={p.identifier}
                      label={p.label}
                    >
                      <span>{p.label}</span>
                      <span className="ml-2 text-xs text-muted-foreground">
                        {propertyDescription(p)}
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button type="submit" disabled={!propertyId}>
                Save
              </Button>
            </div>
            {selectedProperty ? (
              <p className="text-sm text-muted-foreground">
                {propertyDescription(selectedProperty)}
              </p>
            ) : null}
            <input
              type="hidden"
              name="google_search_console[property_identifier]"
              value={propertyId}
              readOnly
            />
          </form>
        ) : (
          <p className="text-sm text-muted-foreground">
            No verified properties found for this account.
          </p>
        )}

        {gsc.configured ? (
          <div className="rounded-lg bg-muted/30 px-4 py-3">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0 space-y-1">
                <div className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="font-medium">Sync</span>
                  {syncBadgeEl(gsc)}
                </div>
                <p className="text-sm text-muted-foreground">
                  Updated {googleSearchConsoleDateTimeLabel(gsc.lastSyncedAt)}.{" "}
                  Range {googleSearchConsoleSyncCoverage(gsc)}. Target{" "}
                  {googleSearchConsoleDateLabel(gsc.refreshWindowTo)}.
                </p>
              </div>
              <form method="post" action={syncPath}>
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={csrfToken()}
                  readOnly
                />
                <Button
                  type="submit"
                  variant="outline"
                  size="sm"
                  disabled={gsc.syncInProgress}
                >
                  <RefreshCw className="size-3.5" />
                  {gsc.syncInProgress ? "Syncing\u2026" : "Sync now"}
                </Button>
              </form>
            </div>
          </div>
        ) : null}
      </CardContent>
    </Card>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Site picker (no site selected)                            */
/* ────────────────────────────────────────────────────────── */

function SitePicker({
  sites,
  initialization,
  activeTab,
}: {
  sites: AnalyticsSettingsSiteOption[]
  initialization: AnalyticsInitializationState
  activeTab: AnalyticsSettingsTab
}) {
  if (sites.length === 0) {
    return (
      <div className="rounded-lg border border-dashed p-8 text-center">
        <Globe className="mx-auto mb-3 size-8 text-muted-foreground/50" />
        <p className="font-medium">No analytics sites configured</p>
        {initialization.canBootstrap ? (
          <>
            <p className="mt-1 text-sm text-muted-foreground">
              This project is configured for single-site analytics, but the site
              record has not been initialized yet.
            </p>
            <div className="mx-auto mt-4 max-w-md rounded-xl border bg-muted/30 p-4 text-left">
              <p className="text-xs font-medium tracking-[0.14em] text-muted-foreground uppercase">
                Default bootstrap
              </p>
              <p className="mt-2 text-sm text-foreground">
                Name: {initialization.suggestedName ?? "Not configured"}
              </p>
              <p className="mt-1 text-sm text-muted-foreground">
                Host: {initialization.suggestedHost ?? "Not configured"}
              </p>
            </div>
            <form method="post" action={initialization.bootstrapPath}>
              <input
                type="hidden"
                name="authenticity_token"
                value={csrfToken()}
                readOnly
              />
              <Button type="submit" className="mt-4">
                Initialize analytics
              </Button>
            </form>
          </>
        ) : (
          <p className="mt-1 text-sm text-muted-foreground">
            Add a site or configure a default single-site bootstrap before using
            analytics.
          </p>
        )}
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Choose the site you want to configure.
      </p>
      <div className="grid gap-3">
        {sites.map((s) => (
          <Link
            key={s.id}
            href={buildAnalyticsSettingsTabUrl(s.settingsPath, activeTab)}
            className="flex items-center justify-between rounded-lg border px-4 py-3 transition hover:bg-muted/40"
          >
            <div>
              <p className="font-medium">{s.name}</p>
              {s.domain ? (
                <p className="text-sm text-muted-foreground">{s.domain}</p>
              ) : null}
            </div>
            <ArrowUpRight className="size-4 text-muted-foreground" />
          </Link>
        ))}
      </div>
    </div>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Page                                                      */
/* ────────────────────────────────────────────────────────── */

export default function AnalyticsSettingsPage(
  props: AnalyticsSettingsPageProps
) {
  const { site, sites, initialization, funnels, settings, paths } = props
  const page = usePage<SharedProps>()
  const { flash } = page.props
  const location = useAnalyticsLocation()
  const currentSettingsUrl =
    location.pathname || location.search
      ? `${location.pathname}${location.search}`
      : page.url
  const activeTab: AnalyticsSettingsTab =
    getAnalyticsSettingsTabFromUrl(currentSettingsUrl)

  const goalNames = useMemo(
    () => settings.goalDefinitions.map((g) => g.displayName),
    [settings.goalDefinitions]
  )

  const funnelsPath = site?.id
    ? `/admin/analytics/sites/${site.id}/funnels`
    : ""

  function handleTabChange(nextTab: string) {
    const normalized = getAnalyticsSettingsTabFromUrl(`/?tab=${nextTab}`)
    const targetUrl = buildAnalyticsSettingsTabUrl(
      currentSettingsUrl,
      normalized
    )
    if (targetUrl !== currentSettingsUrl) {
      navigateAnalytics(targetUrl)
    }
  }

  return (
    <AdminLayout>
      <Head title={"Settings \u00b7 Analytics"} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-1">
            <div className="flex items-center gap-3">
              <h1 className="text-lg font-semibold">Analytics Settings</h1>
              {site && settings.gscConfigured ? <Badge>GSC ready</Badge> : null}
            </div>
            {site ? (
              sites.length > 1 ? (
                <Select
                  value={site.id ?? ""}
                  onValueChange={(id) => {
                    const s = sites.find((x) => x.id === id)
                    if (s) {
                      router.visit(
                        buildAnalyticsSettingsTabUrl(s.settingsPath, activeTab)
                      )
                    }
                  }}
                >
                  <SelectTrigger className="h-7 w-auto gap-1.5 border-none px-0 text-sm text-muted-foreground shadow-none">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {sites.map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name}
                        {s.domain ? ` (${s.domain})` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <p className="text-sm text-muted-foreground">
                  {site.name ?? site.domain} &middot; {site.domain}
                </p>
              )
            ) : (
              <p className="text-sm text-muted-foreground">
                {initialization.canBootstrap
                  ? "Initialize analytics to create the default site for this project."
                  : "Choose a site to manage analytics configuration."}
              </p>
            )}
          </div>

          {site ? (
            <div className="flex flex-wrap gap-2">
              <Link
                href={paths.live ?? "#"}
                className={buttonVariants({
                  variant: "outline",
                  size: "sm",
                })}
              >
                Live
              </Link>
              <Link
                href={paths.reports ?? "#"}
                className={buttonVariants({
                  variant: "outline",
                  size: "sm",
                })}
              >
                Reports
              </Link>
            </div>
          ) : null}
        </div>

        {flash?.alert ? (
          <Alert>
            <AlertDescription>{flash.alert}</AlertDescription>
          </Alert>
        ) : null}

        {!site ? (
          <SitePicker
            sites={sites}
            initialization={initialization}
            activeTab={activeTab}
          />
        ) : (
          <Tabs value={activeTab} onValueChange={handleTabChange}>
            <TabsList variant="line" className="mb-4">
              <TabsTrigger value="tracking">Tracking</TabsTrigger>
              <TabsTrigger value="goals">Goals</TabsTrigger>
              <TabsTrigger value="integrations">Integrations</TabsTrigger>
              <TabsTrigger value="exclusions">Exclusions</TabsTrigger>
              <TabsTrigger value="funnels">Funnels</TabsTrigger>
            </TabsList>

            <TabsContent value="tracking" keepMounted={false}>
              {activeTab === "tracking" ? (
                settings.tracker ? (
                  <TrackingScriptTab tracker={settings.tracker} />
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No tracker configured for this site yet.
                  </p>
                )
              ) : null}
            </TabsContent>

            <TabsContent value="goals" keepMounted={false}>
              {activeTab === "goals" ? (
                <GoalsTab
                  goalDefinitions={settings.goalDefinitions}
                  goalSuggestions={settings.goalSuggestions}
                  settingsDataPath={paths.settingsData ?? "#"}
                />
              ) : null}
            </TabsContent>

            <TabsContent value="integrations" keepMounted={false}>
              {activeTab === "integrations" ? (
                <GoogleSearchConsoleTab
                  gsc={settings.googleSearchConsole}
                  connectPath={paths.googleSearchConsoleConnect ?? "#"}
                  connectionPath={paths.googleSearchConsole ?? "#"}
                  syncPath={paths.googleSearchConsoleSync ?? "#"}
                />
              ) : null}
            </TabsContent>

            <TabsContent value="exclusions" keepMounted={false}>
              {activeTab === "exclusions" ? (
                settings.tracker ? (
                  <ExclusionsSection
                    rules={settings.trackingRules}
                    settingsDataPath={paths.settingsData ?? "#"}
                  />
                ) : (
                  <p className="text-sm text-muted-foreground">
                    Initialize tracking to configure exclusion rules.
                  </p>
                )
              ) : null}
            </TabsContent>

            <TabsContent value="funnels" keepMounted={false}>
              {activeTab === "funnels" ? (
                <FunnelsTab
                  funnels={funnels}
                  goalNames={goalNames}
                  pageSuggestions={settings.funnelPageSuggestions}
                  funnelsPath={funnelsPath}
                />
              ) : null}
            </TabsContent>
          </Tabs>
        )}
      </div>
    </AdminLayout>
  )
}
