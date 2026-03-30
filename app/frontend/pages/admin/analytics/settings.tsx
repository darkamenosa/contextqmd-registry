import { useMemo, useState } from "react"
import { Head, Link, router, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  Code2,
  Copy,
  ExternalLink,
  Filter,
  Globe,
  Link2,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Tag,
  Target,
  Trash2,
  X,
} from "lucide-react"

import { csrfToken } from "@/lib/csrf-token"
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
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
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

import type {
  AnalyticsInitializationState,
  AnalyticsSettingsPageProps,
  AnalyticsSettingsSiteOption,
  AnalyticsTrackerSnippet,
  GoalDefinition,
  GoogleSearchConsoleProperty,
} from "./types"

/* ────────────────────────────────────────────────────────── */
/*  Helpers                                                   */
/* ────────────────────────────────────────────────────────── */

type GoalType = "event" | "page" | "scroll"

type GoalFormState = {
  displayName: string
  goalType: GoalType
  eventName: string
  pagePath: string
  scrollThreshold: number
  customPropPairs: Array<{ key: string; value: string }>
}

function goalTypeOf(def: GoalDefinition): GoalType {
  if (def.eventName) return "event"
  if (def.scrollThreshold != null && def.scrollThreshold >= 0) return "scroll"
  return "page"
}

function goalFormFrom(def: GoalDefinition): GoalFormState {
  return {
    displayName: def.displayName,
    goalType: goalTypeOf(def),
    eventName: def.eventName ?? "",
    pagePath: def.pagePath ?? "",
    scrollThreshold:
      def.scrollThreshold != null && def.scrollThreshold >= 0
        ? def.scrollThreshold
        : 50,
    customPropPairs: Object.entries(def.customProps ?? {}).map(
      ([key, value]) => ({ key, value })
    ),
  }
}

function goalFormToDef(f: GoalFormState): GoalDefinition {
  const customProps: Record<string, string> = {}
  for (const { key, value } of f.customPropPairs) {
    const k = key.trim()
    if (k) customProps[k] = value.trim()
  }
  return {
    displayName: f.displayName.trim(),
    eventName: f.goalType === "event" ? f.eventName.trim() : null,
    pagePath: f.goalType !== "event" ? f.pagePath.trim() : null,
    scrollThreshold: f.goalType === "scroll" ? f.scrollThreshold : null,
    customProps: Object.keys(customProps).length > 0 ? customProps : undefined,
  }
}

function goalRuleLabel(def: GoalDefinition): string {
  if (def.eventName) return def.eventName
  if (def.scrollThreshold != null && def.scrollThreshold >= 0)
    return `${def.pagePath} @ ${def.scrollThreshold}%`
  return def.pagePath ?? ""
}

function goalTypeLabel(type: GoalType): string {
  return type === "event" ? "Event" : type === "scroll" ? "Scroll" : "Page"
}

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

function stepLabelsFrom(steps: Array<Record<string, unknown>>): string[] {
  return steps.map(
    (s) => (s.label as string) || (s.name as string) || String(s)
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
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(18rem,0.9fr)]">
      <Card>
        <CardHeader className="gap-2">
          <div className="flex items-start justify-between gap-3">
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <Code2 className="size-4" />
                Tracking Snippet
              </CardTitle>
              <CardDescription>
                Install this on pages you want this analytics site to track. The
                site token is server-issued and scoped to this site.
              </CardDescription>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => void copySnippet()}
            >
              {copied ? (
                <>
                  <Check className="size-3.5" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="size-3.5" />
                  Copy
                </>
              )}
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <pre className="overflow-x-auto rounded-xl border bg-muted/40 p-4 text-xs leading-6 text-foreground">
            <code>{tracker.snippetHtml}</code>
          </pre>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Resolved Contract</CardTitle>
          <CardDescription>
            The public script host and event endpoint stay backend-owned.
            `data-domain` is advisory only.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <FieldGroup>
            <Field>
              <FieldLabel>Script URL</FieldLabel>
              <Input value={tracker.scriptUrl} readOnly />
            </Field>
            <Field>
              <FieldLabel>Events endpoint</FieldLabel>
              <Input value={tracker.eventsEndpoint} readOnly />
            </Field>
            <Field>
              <FieldLabel>Tracked domain hint</FieldLabel>
              <Input value={tracker.domainHint} readOnly />
            </Field>
          </FieldGroup>

          <Alert>
            <Link2 className="size-4" />
            <AlertDescription>
              This snippet points at the analytics service origin, not the site
              being tracked. Ownership still resolves server-side against the
              signed site token and site boundaries.
            </AlertDescription>
          </Alert>
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
  initial,
  onSave,
  processing,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  initial: GoalFormState
  onSave: (f: GoalFormState) => void
  processing?: boolean
}) {
  const [form, setForm] = useState(initial)
  const [prev, setPrev] = useState(initial)
  if (initial !== prev) {
    setForm(initial)
    setPrev(initial)
  }

  const isEdit = initial.displayName !== ""
  const valid =
    form.displayName.trim() !== "" &&
    (form.goalType === "event"
      ? form.eventName.trim() !== ""
      : form.pagePath.trim() !== "")

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit Goal" : "Add Goal"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update this conversion goal."
              : "Define a new conversion goal to track."}
          </DialogDescription>
        </DialogHeader>

        <FieldGroup className="gap-4">
          <Field>
            <FieldLabel>Display name</FieldLabel>
            <Input
              value={form.displayName}
              onChange={(e) =>
                setForm((f) => ({ ...f, displayName: e.target.value }))
              }
              placeholder="e.g. Signup, Purchase"
            />
          </Field>

          <Field>
            <FieldLabel>Type</FieldLabel>
            <Select
              value={form.goalType}
              onValueChange={(v) =>
                setForm((f) => ({ ...f, goalType: v as GoalType }))
              }
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="event">Custom event</SelectItem>
                <SelectItem value="page">Page visit</SelectItem>
                <SelectItem value="scroll">Scroll depth</SelectItem>
              </SelectContent>
            </Select>
            <FieldDescription>
              {form.goalType === "event"
                ? "Matches a named event fired by your tracker."
                : form.goalType === "scroll"
                  ? "Fires when a visitor scrolls past a threshold on a page."
                  : "Fires when a visitor lands on a matching page path."}
            </FieldDescription>
          </Field>

          {form.goalType === "event" ? (
            <Field>
              <FieldLabel>Event name</FieldLabel>
              <Input
                value={form.eventName}
                onChange={(e) =>
                  setForm((f) => ({ ...f, eventName: e.target.value }))
                }
                placeholder="e.g. signup, purchase"
              />
            </Field>
          ) : (
            <>
              <Field>
                <FieldLabel>Page path</FieldLabel>
                <Input
                  value={form.pagePath}
                  onChange={(e) =>
                    setForm((f) => ({ ...f, pagePath: e.target.value }))
                  }
                  placeholder="e.g. /checkout, /blog/*"
                />
                <FieldDescription>
                  Use * for single-segment and ** for multi-segment wildcard.
                </FieldDescription>
              </Field>
              {form.goalType === "scroll" ? (
                <Field>
                  <FieldLabel>
                    Scroll threshold ({form.scrollThreshold}%)
                  </FieldLabel>
                  <Input
                    type="number"
                    min={0}
                    max={100}
                    value={form.scrollThreshold}
                    onChange={(e) =>
                      setForm((f) => ({
                        ...f,
                        scrollThreshold: parseInt(e.target.value) || 0,
                      }))
                    }
                  />
                </Field>
              ) : null}
            </>
          )}

          <div className="space-y-2">
            <FieldLabel>Custom property matches</FieldLabel>
            {form.customPropPairs.length > 0 ? (
              <div className="space-y-2">
                {form.customPropPairs.map((pair, i) => (
                  <div key={i} className="flex items-center gap-2">
                    <Input
                      className="flex-1"
                      placeholder="key"
                      value={pair.key}
                      onChange={(e) => {
                        const pairs = [...form.customPropPairs]
                        pairs[i] = { ...pair, key: e.target.value }
                        setForm((f) => ({ ...f, customPropPairs: pairs }))
                      }}
                    />
                    <span className="text-muted-foreground">=</span>
                    <Input
                      className="flex-1"
                      placeholder="value"
                      value={pair.value}
                      onChange={(e) => {
                        const pairs = [...form.customPropPairs]
                        pairs[i] = { ...pair, value: e.target.value }
                        setForm((f) => ({ ...f, customPropPairs: pairs }))
                      }}
                    />
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() =>
                        setForm((f) => ({
                          ...f,
                          customPropPairs: f.customPropPairs.filter(
                            (_, j) => j !== i
                          ),
                        }))
                      }
                    >
                      <X className="size-3.5" />
                    </Button>
                  </div>
                ))}
              </div>
            ) : null}
            {form.customPropPairs.length < 3 ? (
              <Button
                variant="outline"
                size="sm"
                onClick={() =>
                  setForm((f) => ({
                    ...f,
                    customPropPairs: [
                      ...f.customPropPairs,
                      { key: "", value: "" },
                    ],
                  }))
                }
              >
                <Plus className="size-3.5" />
                Add property match
              </Button>
            ) : null}
            <FieldDescription>
              Optional. Only events with matching properties count. Max 3.
            </FieldDescription>
          </div>
        </FieldGroup>

        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button disabled={!valid || processing} onClick={() => onSave(form)}>
            {isEdit ? "Update goal" : "Add goal"}
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
  goals,
  settingsDataPath,
}: {
  goals: GoalDefinition[]
  settingsDataPath: string
}) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<GoalDefinition | null>(null)
  const [deleting, setDeleting] = useState<GoalDefinition | null>(null)
  const [processing, setProcessing] = useState(false)

  const dialogForm = useMemo<GoalFormState>(
    () =>
      editing
        ? goalFormFrom(editing)
        : {
            displayName: "",
            goalType: "event",
            eventName: "",
            pagePath: "",
            scrollThreshold: 50,
            customPropPairs: [],
          },
    [editing]
  )

  async function persistGoals(updated: GoalDefinition[], cb?: () => void) {
    setProcessing(true)
    const res = await apiFetch(settingsDataPath, "PATCH", {
      settings: {
        goal_definitions: updated.map((g) => ({
          display_name: g.displayName,
          ...(g.eventName ? { event_name: g.eventName } : {}),
          ...(g.pagePath ? { page_path: g.pagePath } : {}),
          scroll_threshold:
            g.scrollThreshold != null && g.scrollThreshold >= 0
              ? g.scrollThreshold
              : -1,
          custom_props: g.customProps ?? {},
        })),
      },
    })
    setProcessing(false)
    if (res.ok) {
      router.reload()
      cb?.()
    }
  }

  function handleSave(form: GoalFormState) {
    const def = goalFormToDef(form)
    const updated = editing
      ? goals.map((g) => (g.displayName === editing.displayName ? def : g))
      : [...goals, def]
    persistGoals(updated, () => {
      setDialogOpen(false)
      setEditing(null)
    })
  }

  function handleDelete() {
    if (!deleting) return
    persistGoals(
      goals.filter((g) => g.displayName !== deleting.displayName),
      () => setDeleting(null)
    )
  }

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-medium">Goals</h2>
            <p className="text-sm text-muted-foreground">
              Conversion rules tracked for this site
            </p>
          </div>
          <Button
            size="sm"
            onClick={() => {
              setEditing(null)
              setDialogOpen(true)
            }}
          >
            <Plus className="size-3.5" />
            Add goal
          </Button>
        </div>

        {goals.length > 0 ? (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="hidden sm:table-cell">Rule</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {goals.map((goal) => {
                  const propCount = Object.keys(goal.customProps ?? {}).length
                  return (
                    <TableRow key={goal.displayName}>
                      <TableCell className="font-medium">
                        {goal.displayName}
                        {propCount > 0 && (
                          <Badge variant="secondary" className="ml-2">
                            {propCount} prop{propCount > 1 ? "s" : ""}
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">
                          {goalTypeLabel(goalTypeOf(goal))}
                        </Badge>
                      </TableCell>
                      <TableCell className="hidden text-muted-foreground sm:table-cell">
                        <code className="text-xs">{goalRuleLabel(goal)}</code>
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
                                setEditing(goal)
                                setDialogOpen(true)
                              }}
                            >
                              <Pencil className="size-3.5" />
                              Edit
                            </DropdownMenuItem>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem
                              variant="destructive"
                              onClick={() => setDeleting(goal)}
                            >
                              <Trash2 className="size-3.5" />
                              Delete
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
        ) : (
          <div className="rounded-lg border border-dashed p-8 text-center">
            <Target className="mx-auto mb-3 size-8 text-muted-foreground/50" />
            <p className="font-medium">No goals configured</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Goals track conversions like signups, purchases, or page visits.
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
              Add your first goal
            </Button>
          </div>
        )}
      </div>

      <GoalFormDialog
        open={dialogOpen}
        onOpenChange={(v) => {
          setDialogOpen(v)
          if (!v) setEditing(null)
        }}
        initial={dialogForm}
        onSave={handleSave}
        processing={processing}
      />

      <DeleteConfirmDialog
        open={!!deleting}
        onOpenChange={(v) => {
          if (!v) setDeleting(null)
        }}
        title="Delete goal"
        description={`Delete "${deleting?.displayName}"? Historical data is not affected.`}
        onConfirm={handleDelete}
        processing={processing}
      />
    </>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Funnel form dialog                                        */
/* ────────────────────────────────────────────────────────── */

function FunnelFormDialog({
  open,
  onOpenChange,
  initialName,
  initialSteps,
  goalNames,
  onSave,
  processing,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  initialName: string
  initialSteps: string[]
  goalNames: string[]
  onSave: (name: string, steps: string[]) => void
  processing?: boolean
}) {
  const [name, setName] = useState(initialName)
  const [steps, setSteps] = useState<string[]>(
    initialSteps.length > 0 ? initialSteps : ["", ""]
  )
  const [key, setKey] = useState(`${initialName}-${open}`)
  const nextKey = `${initialName}-${open}`
  if (nextKey !== key) {
    setName(initialName)
    setSteps(initialSteps.length > 0 ? initialSteps : ["", ""])
    setKey(nextKey)
  }

  const isEdit = initialName !== ""
  const nonEmpty = steps.filter((s) => s.trim() !== "")
  const valid = name.trim() !== "" && nonEmpty.length >= 2

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit Funnel" : "Add Funnel"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update the funnel steps."
              : "Define a multi-step conversion path. At least 2 steps required."}
          </DialogDescription>
        </DialogHeader>

        <FieldGroup className="gap-4">
          <Field>
            <FieldLabel>Funnel name</FieldLabel>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Signup Flow"
            />
          </Field>

          <div className="space-y-2">
            <FieldLabel>Steps</FieldLabel>
            <div className="space-y-2">
              {steps.map((step, i) => (
                <div key={i} className="flex items-center gap-2">
                  <span className="w-6 text-right text-xs text-muted-foreground tabular-nums">
                    {i + 1}.
                  </span>
                  <Input
                    className="flex-1"
                    value={step}
                    onChange={(e) =>
                      setSteps((s) =>
                        s.map((v, j) => (j === i ? e.target.value : v))
                      )
                    }
                    placeholder={
                      goalNames[i] ? `e.g. ${goalNames[i]}` : "Step label"
                    }
                  />
                  {steps.length > 2 ? (
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() =>
                        setSteps((s) => s.filter((_, j) => j !== i))
                      }
                    >
                      <X className="size-3.5" />
                    </Button>
                  ) : (
                    <div className="w-7" />
                  )}
                </div>
              ))}
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setSteps((s) => [...s, ""])}
            >
              <Plus className="size-3.5" />
              Add step
            </Button>
            <FieldDescription>
              Each step is a goal name or page path visitors must reach in
              order.
            </FieldDescription>
          </div>
        </FieldGroup>

        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button
            disabled={!valid || processing}
            onClick={() =>
              onSave(
                name.trim(),
                steps.filter((s) => s.trim() !== "")
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
  funnelsPath,
}: {
  funnels: AnalyticsSettingsPageProps["funnels"]
  goalNames: string[]
  funnelsPath: string
}) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<
    AnalyticsSettingsPageProps["funnels"][number] | null
  >(null)
  const [deleting, setDeleting] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const editSteps = useMemo(
    () => (editing ? stepLabelsFrom(editing.steps) : []),
    [editing]
  )

  async function handleSave(name: string, steps: string[]) {
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

  function stepPreview(steps: Array<Record<string, unknown>>) {
    const labels = stepLabelsFrom(steps).slice(0, 3)
    const preview = labels.join(" \u2192 ")
    return steps.length > 3 ? `${preview} \u2192 \u2026` : preview
  }

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-medium">Funnels</h2>
            <p className="text-sm text-muted-foreground">
              Multi-step conversion paths
            </p>
          </div>
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
/*  Properties tab                                            */
/* ────────────────────────────────────────────────────────── */

function PropertiesTab({
  properties,
  settingsDataPath,
}: {
  properties: string[]
  settingsDataPath: string
}) {
  const [newProp, setNewProp] = useState("")
  const [processing, setProcessing] = useState(false)

  async function saveProps(updated: string[], cb?: () => void) {
    setProcessing(true)
    const res = await apiFetch(settingsDataPath, "PATCH", {
      settings: { allowed_event_props: updated },
    })
    setProcessing(false)
    if (res.ok) {
      router.reload()
      cb?.()
    }
  }

  function handleAdd() {
    const name = newProp.trim()
    if (!name || properties.includes(name)) return
    saveProps([...properties, name].sort(), () => setNewProp(""))
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-sm font-medium">Custom Properties</h2>
          <p className="text-sm text-muted-foreground">
            Extra event attributes used for filters, segmentation, and goal
            matching.
          </p>
        </div>
        {properties.length > 0 ? (
          <Button
            variant="outline"
            size="sm"
            disabled={processing}
            onClick={() => saveProps([])}
          >
            Clear all
          </Button>
        ) : null}
      </div>

      <div>
        <p className="text-sm text-muted-foreground">
          Only properties listed here will appear in analytics filters and goal
          configuration.
        </p>
      </div>

      {properties.length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {properties.map((prop) => (
            <Badge
              key={prop}
              variant="secondary"
              className="gap-1.5 py-1 pr-1 pl-2.5"
            >
              {prop}
              <button
                className="rounded-sm p-0.5 transition-colors hover:bg-foreground/10"
                onClick={() => saveProps(properties.filter((p) => p !== prop))}
                disabled={processing}
              >
                <X className="size-3" />
              </button>
            </Badge>
          ))}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed p-6 text-center">
          <Tag className="mx-auto mb-3 size-8 text-muted-foreground/50" />
          <p className="font-medium">No custom properties</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Add event attributes such as <code>plan</code> or <code>cta</code>
            to use them in analytics filters.
          </p>
        </div>
      )}

      <form
        className="flex items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          handleAdd()
        }}
      >
        <Input
          value={newProp}
          onChange={(e) => setNewProp(e.target.value)}
          placeholder="Property name (e.g. plan, category)"
          className="max-w-xs"
        />
        <Button
          type="submit"
          variant="outline"
          size="sm"
          disabled={!newProp.trim() || processing}
        >
          Add
        </Button>
      </form>
    </div>
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

function syncSummary(
  gsc: AnalyticsSettingsPageProps["settings"]["googleSearchConsole"]
): string {
  if (gsc.syncInProgress)
    return `Syncing ${gsc.refreshWindowFrom ?? "?"} to ${gsc.refreshWindowTo ?? "?"}.`
  if (gsc.syncError) return gsc.syncError
  if (gsc.lastSyncedAt)
    return `Synced ${gsc.syncedFrom ?? "?"} to ${gsc.syncedTo ?? "?"}. Refresh target: ${gsc.refreshWindowTo ?? "?"}.`
  return `No completed sync yet. Refresh target: ${gsc.refreshWindowTo ?? "?"}.`
}

function propertyDescription(p: GoogleSearchConsoleProperty) {
  return `${p.type === "domain" ? "Domain" : "URL prefix"} \u00b7 ${p.permissionLevel}`
}

/* ────────────────────────────────────────────────────────── */
/*  Google Search Console tab                                 */
/* ────────────────────────────────────────────────────────── */

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

  const selectedProperty = useMemo(
    () => gsc.properties.find((p) => p.identifier === propertyId) ?? null,
    [propertyId, gsc.properties]
  )

  return (
    <div className="space-y-4">
      <div className="space-y-1">
        <div className="flex items-center gap-2">
          <h2 className="text-base font-semibold">Search Providers</h2>
          <Badge variant="outline">Google first</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Connect Google Search Console, choose the property for this site, and
          keep search reporting healthy.
        </p>
      </div>

      {!gsc.available ? (
        <Alert>
          <AlertDescription>
            OAuth credentials are not configured for this environment.
          </AlertDescription>
        </Alert>
      ) : null}

      <Card>
        <CardHeader className="gap-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <CardTitle className="text-base">
                  Google Search Console
                </CardTitle>
                {statusBadge(gsc.connected, gsc.configured)}
              </div>
              <CardDescription>
                Search Console powers query and SEO reports for this site. It
                does not affect live analytics.
              </CardDescription>
            </div>
            {gsc.available && !gsc.connected ? (
              <form method="post" action={connectPath}>
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={csrfToken()}
                  readOnly
                />
                <Button type="submit">
                  <Link2 className="size-4" />
                  Connect Google
                </Button>
              </form>
            ) : null}
          </div>

          <div className="grid gap-3 md:grid-cols-3">
            <div className="rounded-xl border bg-muted/30 p-4">
              <p className="text-xs font-medium tracking-[0.14em] text-muted-foreground uppercase">
                Step 1
              </p>
              <p className="mt-2 font-medium">Connect account</p>
              <p className="mt-1 text-sm text-muted-foreground">
                {gsc.connected
                  ? (gsc.accountEmail ?? "Connected")
                  : "Connect a Google account with Search Console access."}
              </p>
            </div>
            <div className="rounded-xl border bg-muted/30 p-4">
              <p className="text-xs font-medium tracking-[0.14em] text-muted-foreground uppercase">
                Step 2
              </p>
              <p className="mt-2 font-medium">Choose property</p>
              <p className="mt-1 text-sm text-muted-foreground">
                {gsc.propertyIdentifier ??
                  "Select the verified property for this site."}
              </p>
            </div>
            <div className="rounded-xl border bg-muted/30 p-4">
              <p className="text-xs font-medium tracking-[0.14em] text-muted-foreground uppercase">
                Step 3
              </p>
              <p className="mt-2 flex items-center gap-2 font-medium">
                Sync data
                {syncBadgeEl(gsc)}
              </p>
              <p className="mt-1 text-sm text-muted-foreground">
                {syncSummary(gsc)}
              </p>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-5">
          {gsc.callbackUrl ? (
            <div className="rounded-xl border border-dashed p-5">
              <div className="space-y-1">
                <h3 className="font-medium">OAuth callback URL</h3>
                <p className="text-sm text-muted-foreground">
                  Add this exact URL to your Google Cloud OAuth client.
                </p>
              </div>
              <Input value={gsc.callbackUrl} readOnly className="mt-3" />
            </div>
          ) : null}

          {gsc.connected ? (
            <>
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
                <>
                  <form
                    method="post"
                    action={connectionPath}
                    className="space-y-4 rounded-xl border p-5"
                  >
                    <input
                      type="hidden"
                      name="authenticity_token"
                      value={csrfToken()}
                      readOnly
                    />
                    <input
                      type="hidden"
                      name="_method"
                      value="patch"
                      readOnly
                    />
                    <div className="space-y-1">
                      <h3 className="font-medium">Site property</h3>
                      <p className="text-sm text-muted-foreground">
                        Choose the Search Console property that should feed this
                        analytics site.
                      </p>
                    </div>
                    <FieldGroup className="gap-4">
                      <Field>
                        <FieldLabel>Verified property</FieldLabel>
                        <Select
                          value={propertyId}
                          onValueChange={(v) => setPropertyId(v ?? "")}
                        >
                          <SelectTrigger className="w-full">
                            <SelectValue placeholder="Choose a property" />
                          </SelectTrigger>
                          <SelectContent align="start" className="max-h-80">
                            {gsc.properties.map((p) => (
                              <SelectItem
                                key={p.identifier}
                                value={p.identifier}
                              >
                                <div className="flex flex-col text-left">
                                  <span>{p.label}</span>
                                  <span className="text-xs text-muted-foreground">
                                    {propertyDescription(p)}
                                  </span>
                                </div>
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <input
                          type="hidden"
                          name="google_search_console[property_identifier]"
                          value={propertyId}
                          readOnly
                        />
                        <FieldDescription>
                          Domain properties are broader. URL-prefix properties
                          are stricter and useful when you only want one
                          host/path.
                        </FieldDescription>
                      </Field>
                      {selectedProperty ? (
                        <div className="rounded-lg border border-border/70 bg-muted/30 p-3 text-sm text-muted-foreground">
                          {propertyDescription(selectedProperty)}
                        </div>
                      ) : null}
                      <div className="flex flex-wrap gap-2">
                        <Button type="submit" disabled={!propertyId}>
                          Save property
                        </Button>
                      </div>
                    </FieldGroup>
                  </form>

                  {gsc.configured ? (
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
                        disabled={gsc.syncInProgress}
                      >
                        <RefreshCw className="size-4" />
                        {gsc.syncInProgress
                          ? "Sync in progress"
                          : gsc.syncError || gsc.syncStale
                            ? "Retry sync"
                            : "Sync now"}
                      </Button>
                    </form>
                  ) : null}
                </>
              ) : (
                <div className="rounded-xl border border-dashed p-5">
                  <p className="font-medium">No verified properties found</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    This account is connected, but no eligible Search Console
                    properties were returned for it.
                  </p>
                </div>
              )}

              <div className="flex flex-wrap items-center gap-3">
                <form method="post" action={connectionPath}>
                  <input
                    type="hidden"
                    name="authenticity_token"
                    value={csrfToken()}
                    readOnly
                  />
                  <input type="hidden" name="_method" value="delete" readOnly />
                  <Button type="submit" variant="outline">
                    Disconnect
                  </Button>
                </form>
              </div>
            </>
          ) : (
            <div className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">
              Connect your Google account, grant read-only Search Console
              access, then come back here to choose the verified property for
              this site.
            </div>
          )}
        </CardContent>
      </Card>

      <Alert>
        <Search className="size-4" />
        <AlertDescription>
          Search Console query data is delayed by Google and may be incomplete
          for very recent periods.{" "}
          <a
            href="https://developers.google.com/webmaster-tools/v1/searchanalytics/query"
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 underline underline-offset-4"
          >
            API reference
            <ExternalLink className="size-3" />
          </a>
        </AlertDescription>
      </Alert>
    </div>
  )
}

/* ────────────────────────────────────────────────────────── */
/*  Site picker (no site selected)                            */
/* ────────────────────────────────────────────────────────── */

function SitePicker({
  sites,
  initialization,
}: {
  sites: AnalyticsSettingsSiteOption[]
  initialization: AnalyticsInitializationState
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
            href={s.settingsPath}
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
  const { flash } = usePage<SharedProps>().props

  const goalNames = useMemo(
    () => settings.goalDefinitions.map((g) => g.displayName),
    [settings.goalDefinitions]
  )

  const funnelsPath = site?.id
    ? `/admin/analytics/sites/${site.id}/funnels`
    : ""

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
                    if (s) router.visit(s.settingsPath)
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
          <SitePicker sites={sites} initialization={initialization} />
        ) : (
          <div className="space-y-8">
            <GoogleSearchConsoleTab
              gsc={settings.googleSearchConsole}
              connectPath={paths.googleSearchConsoleConnect ?? "#"}
              connectionPath={paths.googleSearchConsole ?? "#"}
              syncPath={paths.googleSearchConsoleSync ?? "#"}
            />

            {settings.tracker ? (
              <section className="space-y-3">
                <div className="space-y-1">
                  <h2 className="text-base font-semibold">Tracking</h2>
                  <p className="text-sm text-muted-foreground">
                    Install or verify the public tracking snippet for this site.
                  </p>
                </div>
                <TrackingScriptTab tracker={settings.tracker} />
              </section>
            ) : null}

            <section className="space-y-3">
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <h2 className="text-base font-semibold">Definitions</h2>
                  <Badge variant="outline">
                    {settings.goalDefinitions.length} goals
                  </Badge>
                  <Badge variant="outline">{funnels.length} funnels</Badge>
                  <Badge variant="outline">
                    {settings.allowedEventProps.length} properties
                  </Badge>
                </div>
                <p className="text-sm text-muted-foreground">
                  Manage conversions, funnels, and custom event properties used
                  in analytics reports.
                </p>
              </div>

              <Tabs defaultValue="goals">
                <TabsList variant="line" className="mb-2">
                  <TabsTrigger value="goals">
                    <Target className="size-3.5" />
                    Goals
                  </TabsTrigger>
                  <TabsTrigger value="funnels">
                    <Filter className="size-3.5" />
                    Funnels
                  </TabsTrigger>
                  <TabsTrigger value="props">
                    <Tag className="size-3.5" />
                    Custom Properties
                  </TabsTrigger>
                </TabsList>

                <TabsContent value="goals" className="pt-2">
                  <GoalsTab
                    goals={settings.goalDefinitions}
                    settingsDataPath={paths.settingsData ?? "#"}
                  />
                </TabsContent>

                <TabsContent value="funnels" className="pt-2">
                  <FunnelsTab
                    funnels={funnels}
                    goalNames={goalNames}
                    funnelsPath={funnelsPath}
                  />
                </TabsContent>

                <TabsContent value="props" className="pt-2">
                  <PropertiesTab
                    properties={settings.allowedEventProps}
                    settingsDataPath={paths.settingsData ?? "#"}
                  />
                </TabsContent>
              </Tabs>
            </section>
          </div>
        )}
      </div>
    </AdminLayout>
  )
}
