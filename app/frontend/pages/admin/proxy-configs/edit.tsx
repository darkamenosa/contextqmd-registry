import { Head, Link, useForm } from "@inertiajs/react"
import { ChevronLeft, Save, X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
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
import { Textarea } from "@/components/ui/textarea"
import AdminLayout from "@/layouts/admin-layout"

interface ProxyConfigEdit {
  id: number
  name: string
  scheme: string
  host: string
  port: number
  username: string | null
  password: string | null
  kind: string | null
  usageScope: string
  priority: number
  active: boolean
  maxConcurrency: number
  leaseTtlSeconds: number
  supportsStickySessions: boolean
  provider: string | null
  notes: string | null
}

interface Props {
  proxyConfig: ProxyConfigEdit
  schemes: string[]
  kinds: string[]
  scopes: string[]
}

export default function AdminProxyConfigEdit({
  proxyConfig: config,
  schemes,
  kinds,
  scopes,
}: Props) {
  const { data, setData, patch, processing, transform } = useForm({
    name: config.name,
    scheme: config.scheme,
    host: config.host,
    port: String(config.port),
    username: config.username || "",
    password: config.password || "",
    kind: config.kind || "datacenter",
    usageScope: config.usageScope,
    priority: String(config.priority),
    maxConcurrency: String(config.maxConcurrency),
    leaseTtlSeconds: String(config.leaseTtlSeconds),
    active: config.active,
    supportsStickySessions: config.supportsStickySessions,
    provider: config.provider || "",
    notes: config.notes || "",
  })

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    transform((data) => ({
      proxy_config: {
        name: data.name,
        scheme: data.scheme,
        host: data.host,
        port: parseInt(data.port, 10),
        username: data.username || "",
        password: data.password || "",
        kind: data.kind,
        usage_scope: data.usageScope,
        priority: parseInt(data.priority, 10),
        max_concurrency: parseInt(data.maxConcurrency, 10),
        lease_ttl_seconds: parseInt(data.leaseTtlSeconds, 10),
        active: data.active,
        supports_sticky_sessions: data.supportsStickySessions,
        provider: data.provider || "",
        notes: data.notes || "",
      },
    }))
    patch(`/admin/proxy_configs/${config.id}`)
  }

  return (
    <AdminLayout>
      <Head title={`Edit ${config.name}`} />

      <form onSubmit={handleSubmit} className="flex flex-col gap-5">
        {/* Header */}
        <div className="flex items-center gap-2">
          <Link
            href={`/admin/proxy_configs/${config.id}`}
            aria-label="Back to proxy"
            className="rounded-sm p-0.5 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <h1 className="text-base/6 font-semibold">
            Edit <span className="text-foreground">{config.name}</span>
          </h1>
          <Badge
            variant="outline"
            className="font-mono text-[11px] font-normal"
          >
            {config.scheme}://{config.host}:{config.port}
          </Badge>
        </div>

        {/* Connection section */}
        <section>
          <div className="mb-3 flex items-center gap-2 border-b pb-2">
            <h2 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
              Connection
            </h2>
          </div>
          <FieldGroup className="gap-4">
            <div className="grid gap-4 @lg/main:grid-cols-2">
              <Field>
                <FieldLabel htmlFor="name">Name</FieldLabel>
                <Input
                  id="name"
                  value={data.name}
                  onChange={(e) => setData("name", e.target.value)}
                  required
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="provider">Provider</FieldLabel>
                <Input
                  id="provider"
                  value={data.provider}
                  onChange={(e) => setData("provider", e.target.value)}
                  placeholder="e.g. BrightData, Oxylabs"
                />
              </Field>
            </div>
            <div className="grid gap-4 @lg/main:grid-cols-4">
              <Field>
                <FieldLabel>Scheme</FieldLabel>
                <Select
                  value={data.scheme}
                  onValueChange={(val) => setData("scheme", val ?? "http")}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {schemes.map((s) => (
                      <SelectItem key={s} value={s}>
                        {s.toUpperCase()}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
              <Field className="@lg/main:col-span-2">
                <FieldLabel htmlFor="host">Host</FieldLabel>
                <Input
                  id="host"
                  value={data.host}
                  onChange={(e) => setData("host", e.target.value)}
                  required
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="port">Port</FieldLabel>
                <Input
                  id="port"
                  type="number"
                  value={data.port}
                  onChange={(e) => setData("port", e.target.value)}
                  required
                  min={1}
                />
              </Field>
            </div>
            <div className="grid gap-4 @lg/main:grid-cols-2">
              <Field>
                <FieldLabel htmlFor="username">Username</FieldLabel>
                <Input
                  id="username"
                  value={data.username}
                  onChange={(e) => setData("username", e.target.value)}
                  placeholder="Optional"
                  autoComplete="off"
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="password">Password</FieldLabel>
                <Input
                  id="password"
                  type="password"
                  value={data.password}
                  onChange={(e) => setData("password", e.target.value)}
                  placeholder="Leave blank to keep existing"
                  autoComplete="off"
                />
              </Field>
            </div>
          </FieldGroup>
        </section>

        {/* Behavior section */}
        <section>
          <div className="mb-3 flex items-center gap-2 border-b pb-2">
            <h2 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
              Behavior
            </h2>
          </div>
          <FieldGroup className="gap-4">
            <div className="grid gap-4 @lg/main:grid-cols-3">
              <Field>
                <FieldLabel>Kind</FieldLabel>
                <Select
                  value={data.kind}
                  onValueChange={(val) => setData("kind", val ?? "datacenter")}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {kinds.map((k) => (
                      <SelectItem key={k} value={k}>
                        {k.charAt(0).toUpperCase() + k.slice(1)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <FieldDescription>Proxy network type</FieldDescription>
              </Field>
              <Field>
                <FieldLabel>Usage Scope</FieldLabel>
                <Select
                  value={data.usageScope}
                  onValueChange={(val) => setData("usageScope", val ?? "all")}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {scopes.map((s) => (
                      <SelectItem key={s} value={s}>
                        {s.charAt(0).toUpperCase() + s.slice(1)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <FieldDescription>
                  Which crawl types can use this proxy
                </FieldDescription>
              </Field>
              <Field>
                <FieldLabel htmlFor="priority">Priority</FieldLabel>
                <Input
                  id="priority"
                  type="number"
                  value={data.priority}
                  onChange={(e) => setData("priority", e.target.value)}
                />
                <FieldDescription>Higher = preferred</FieldDescription>
              </Field>
            </div>
            <div className="grid gap-4 @lg/main:grid-cols-3">
              <Field>
                <FieldLabel htmlFor="maxConcurrency">
                  Max Concurrency
                </FieldLabel>
                <Input
                  id="maxConcurrency"
                  type="number"
                  value={data.maxConcurrency}
                  onChange={(e) => setData("maxConcurrency", e.target.value)}
                  min={1}
                />
                <FieldDescription>Max simultaneous leases</FieldDescription>
              </Field>
              <Field>
                <FieldLabel htmlFor="leaseTtlSeconds">
                  Lease TTL (seconds)
                </FieldLabel>
                <Input
                  id="leaseTtlSeconds"
                  type="number"
                  value={data.leaseTtlSeconds}
                  onChange={(e) => setData("leaseTtlSeconds", e.target.value)}
                  min={1}
                />
                <FieldDescription>
                  How long a lease stays active
                </FieldDescription>
              </Field>
              <div className="flex flex-col justify-end gap-3 pb-1">
                <label className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked={data.supportsStickySessions}
                    onCheckedChange={(checked) =>
                      setData("supportsStickySessions", checked === true)
                    }
                  />
                  Supports sticky sessions
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked={data.active}
                    onCheckedChange={(checked) =>
                      setData("active", checked === true)
                    }
                  />
                  Active
                </label>
              </div>
            </div>
          </FieldGroup>
        </section>

        {/* Notes section */}
        <section>
          <div className="mb-3 flex items-center gap-2 border-b pb-2">
            <h2 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
              Notes
            </h2>
          </div>
          <Field>
            <Textarea
              id="notes"
              value={data.notes}
              onChange={(e) => setData("notes", e.target.value)}
              placeholder="Internal notes about this proxy..."
              className="min-h-16"
              rows={3}
            />
          </Field>
        </section>

        {/* Actions */}
        <div className="flex items-center gap-2 border-t pt-4">
          <Button
            type="submit"
            size="sm"
            disabled={processing}
            className="gap-1.5"
          >
            <Save className="size-3.5" />
            {processing ? "Saving..." : "Save Changes"}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="gap-1.5 text-muted-foreground"
            nativeButton={false}
            render={<Link href={`/admin/proxy_configs/${config.id}`} />}
          >
            <X className="size-3.5" />
            Cancel
          </Button>
        </div>
      </form>
    </AdminLayout>
  )
}
