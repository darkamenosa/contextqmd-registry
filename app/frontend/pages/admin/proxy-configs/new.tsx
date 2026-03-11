import { Head, Link, useForm } from "@inertiajs/react"
import { ChevronLeft, Save, X } from "lucide-react"

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

interface Props {
  schemes: string[]
  kinds: string[]
  scopes: string[]
}

export default function AdminProxyConfigNew({ schemes, kinds, scopes }: Props) {
  const { data, setData, post, processing, transform } = useForm({
    name: "",
    scheme: "http",
    host: "",
    port: "8080",
    username: "",
    password: "",
    kind: "datacenter",
    usageScope: "all",
    priority: "0",
    maxConcurrency: "4",
    leaseTtlSeconds: "900",
    active: true,
    supportsStickySessions: false,
    provider: "",
    notes: "",
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
    post("/admin/proxy_configs")
  }

  return (
    <AdminLayout>
      <Head title="Add Proxy" />

      <form onSubmit={handleSubmit} className="flex flex-col gap-5">
        {/* Header */}
        <div className="flex items-center gap-2">
          <Link
            href="/admin/proxy_configs"
            aria-label="Back to proxy pool"
            className="rounded-sm p-0.5 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <h1 className="text-base/6 font-semibold">Add Proxy</h1>
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
                  placeholder="e.g. US Datacenter 1"
                  required
                />
                <FieldDescription>
                  A friendly label for this proxy
                </FieldDescription>
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
                  placeholder="proxy.example.com"
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
                  placeholder="Optional"
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
            {processing ? "Creating..." : "Create Proxy"}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="gap-1.5 text-muted-foreground"
            nativeButton={false}
            render={<Link href="/admin/proxy_configs" />}
          >
            <X className="size-3.5" />
            Cancel
          </Button>
        </div>
      </form>
    </AdminLayout>
  )
}
