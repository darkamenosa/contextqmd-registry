import { useState } from "react"
import { Head, useForm, usePage } from "@inertiajs/react"
import type { AccessToken } from "@/types"
import { Check, Copy, KeyRound, Plus, Trash2 } from "lucide-react"

import { withCurrentAccountScope } from "@/lib/account-scope"
import { formatDateShort } from "@/lib/format-date"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import AppLayout from "@/layouts/app-layout"

interface Props {
  accessTokens: AccessToken[]
  newToken: string | null
}

function CopyButton({
  value,
  variant = "ghost",
  size = "icon",
  className = "",
}: {
  value: string
  variant?: "ghost" | "outline"
  size?: "icon" | "sm"
  className?: string
}) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    if (typeof navigator === "undefined" || !navigator.clipboard) return

    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }

  return (
    <Button variant={variant} size={size} className={className} onClick={copy}>
      {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
      {copied && size === "sm" && <span className="text-xs">Copied!</span>}
    </Button>
  )
}

function NewTokenAlert({ token }: { token: string }) {
  return (
    <Alert className="border-green-200 bg-green-50 dark:border-green-900 dark:bg-green-950">
      <KeyRound className="size-4" />
      <AlertDescription className="flex flex-col gap-2">
        <span className="text-sm font-medium text-foreground">
          Your new access token
        </span>
        <div className="flex items-center gap-2">
          <code className="flex-1 rounded-md border bg-background px-3 py-2 font-mono text-sm select-all">
            {token}
          </code>
          <CopyButton value={token} variant="outline" size="sm" />
        </div>
        <span className="text-xs text-muted-foreground">
          Copy this token now. You won&apos;t be able to see it again.
        </span>
      </AlertDescription>
    </Alert>
  )
}

function CreateTokenDialog() {
  const { url } = usePage()
  const [open, setOpen] = useState(false)
  const { data, setData, post, processing, errors, reset, transform } = useForm(
    {
      name: "",
      permission: "read",
    }
  )

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({ access_token: data }))
    post(withCurrentAccountScope(url, "/app/access_tokens"), {
      onSuccess: () => {
        reset()
        setOpen(false)
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" />}>
        <Plus className="size-4" />
        Generate token
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Generate access token</DialogTitle>
            <DialogDescription>
              Access tokens can be used to authenticate with the API.
            </DialogDescription>
          </DialogHeader>
          <FieldGroup className="gap-4 py-4">
            <Field>
              <FieldLabel htmlFor="token-name">Description</FieldLabel>
              <Input
                id="token-name"
                placeholder="e.g. CI integration"
                value={data.name}
                onChange={(e) => setData("name", e.target.value)}
              />
              {errors.name && <FieldError>{errors.name}</FieldError>}
            </Field>
            <Field>
              <FieldLabel>Permissions</FieldLabel>
              <div className="flex items-center gap-6">
                <label className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked
                    onCheckedChange={() => {
                      /* Read is always required */
                    }}
                  />
                  Read
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <Checkbox
                    checked={data.permission === "write"}
                    onCheckedChange={(checked) =>
                      setData("permission", checked ? "write" : "read")
                    }
                  />
                  Write
                </label>
              </div>
              {errors.permission && (
                <FieldError>{errors.permission}</FieldError>
              )}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <Button type="submit" disabled={processing}>
              Generate token
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function RevokeTokenDialog({
  token,
  open,
  onOpenChange,
}: {
  token: AccessToken
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { url } = usePage()
  const { delete: destroy, processing } = useForm({})

  function handleRevoke() {
    destroy(withCurrentAccountScope(url, `/app/access_tokens/${token.id}`), {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Revoke access token?</DialogTitle>
          <DialogDescription>
            The token{" "}
            <span className="font-medium text-foreground">{token.name}</span>{" "}
            will be permanently revoked. Any applications using this token will
            lose access immediately.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            onClick={handleRevoke}
            disabled={processing}
          >
            Yes, revoke token
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function TokenPrefix({ prefix }: { prefix: string | null }) {
  if (!prefix) return <span className="text-muted-foreground">-</span>

  return (
    <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
      {prefix}••••
    </code>
  )
}

function TokensTable({ tokens }: { tokens: AccessToken[] }) {
  const [revokeToken, setRevokeToken] = useState<AccessToken | null>(null)

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Access Tokens</CardTitle>
          <CardDescription>
            Manage personal access tokens for the API.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-t">
                  <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                    Description
                  </th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                    Token
                  </th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-muted-foreground">
                    Permission
                  </th>
                  <th className="hidden px-4 py-3 text-left text-sm font-medium text-muted-foreground sm:table-cell">
                    Created
                  </th>
                  <th className="hidden px-4 py-3 text-left text-sm font-medium text-muted-foreground sm:table-cell">
                    Last used
                  </th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-muted-foreground">
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {tokens.length > 0 ? (
                  tokens.map((token) => (
                    <tr
                      key={token.id}
                      className="border-t transition-colors hover:bg-muted/50"
                    >
                      <td className="px-4 py-3 text-sm font-medium">
                        {token.name}
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <TokenPrefix prefix={token.tokenPrefix} />
                      </td>
                      <td className="px-4 py-3 text-sm">
                        <Badge
                          variant="outline"
                          className="text-muted-foreground capitalize"
                        >
                          {token.permission === "write"
                            ? "Read + Write"
                            : "Read"}
                        </Badge>
                      </td>
                      <td className="hidden px-4 py-3 text-sm sm:table-cell">
                        {formatDateShort(token.createdAt)}
                      </td>
                      <td className="hidden px-4 py-3 text-sm text-muted-foreground sm:table-cell">
                        {token.lastUsedAt
                          ? formatDateShort(token.lastUsedAt)
                          : "Never"}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-destructive hover:text-destructive"
                          onClick={() => setRevokeToken(token)}
                        >
                          <Trash2 className="size-4" />
                          <span className="sr-only">Revoke</span>
                        </Button>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td
                      colSpan={6}
                      className="h-24 text-center text-sm text-muted-foreground"
                    >
                      No access tokens yet. Generate one to get started.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {revokeToken && (
        <RevokeTokenDialog
          token={revokeToken}
          open={!!revokeToken}
          onOpenChange={(open) => {
            if (!open) setRevokeToken(null)
          }}
        />
      )}
    </>
  )
}

export default function AppAccessTokensIndex({
  accessTokens,
  newToken,
}: Props) {
  return (
    <AppLayout>
      <Head title="Access Tokens" />
      <div className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">
              Access Tokens
            </h1>
            <p className="text-sm text-muted-foreground">
              Personal access tokens for API authentication.
            </p>
          </div>
          <CreateTokenDialog />
        </div>

        {newToken && <NewTokenAlert token={newToken} />}

        <TokensTable tokens={accessTokens} />
      </div>
    </AppLayout>
  )
}
