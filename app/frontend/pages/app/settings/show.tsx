import { useState } from "react"
import { Head, useForm, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { Info } from "lucide-react"

import { withAccountScope } from "@/lib/account-scope"
import { userInitials } from "@/lib/user-initials"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
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
import { Separator } from "@/components/ui/separator"
import AppLayout from "@/layouts/app-layout"

interface Props {
  name: string
  email: string
  passwordChangeable: boolean
}

function Section({
  title,
  description,
  children,
}: {
  title: string
  description: string
  children: React.ReactNode
}) {
  return (
    <div className="grid grid-cols-1 gap-x-8 gap-y-4 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]">
      <div>
        <h2 className="font-semibold">{title}</h2>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <div>{children}</div>
    </div>
  )
}

function ProfileSection({ name, email }: { name: string; email: string }) {
  const { url } = usePage()
  const { data, setData, patch, processing, errors, transform } = useForm({
    name,
  })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({ settings: data }))
    patch(withAccountScope(url, "/app/settings"))
  }

  const initials = userInitials(name)

  return (
    <Section
      title="Profile"
      description="Your personal information and display name."
    >
      <div className="flex flex-col gap-5">
        <div className="flex items-center gap-3">
          <Avatar className="size-10 rounded-lg">
            <AvatarFallback className="rounded-lg bg-primary text-primary-foreground">
              {initials}
            </AvatarFallback>
          </Avatar>
          <div>
            <p className="text-sm font-medium">{name}</p>
            <p className="text-xs text-muted-foreground">{email}</p>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field>
            <FieldLabel htmlFor="name">Display name</FieldLabel>
            <Input
              id="name"
              value={data.name}
              onChange={(e) => setData("name", e.target.value)}
            />
            {errors.name && <FieldError>{errors.name}</FieldError>}
          </Field>
          <div>
            <Button size="sm" type="submit" disabled={processing}>
              Save changes
            </Button>
          </div>
        </form>
      </div>
    </Section>
  )
}

function PasswordSection() {
  const { url } = usePage()
  const { data, setData, patch, processing, errors, reset, transform } =
    useForm({
      current_password: "",
      password: "",
      password_confirmation: "",
    })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({ settings: data }))
    patch(withAccountScope(url, "/app/settings"), {
      onSuccess: () => reset(),
    })
  }

  return (
    <Section
      title="Password"
      description="Update your password to keep your account secure."
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <FieldGroup className="gap-4">
          <Field>
            <FieldLabel htmlFor="current_password">Current password</FieldLabel>
            <Input
              id="current_password"
              type="password"
              value={data.current_password}
              onChange={(e) => setData("current_password", e.target.value)}
            />
            {errors.current_password && (
              <FieldError>{errors.current_password}</FieldError>
            )}
          </Field>
          <Field>
            <FieldLabel htmlFor="password">New password</FieldLabel>
            <Input
              id="password"
              type="password"
              value={data.password}
              onChange={(e) => setData("password", e.target.value)}
            />
            {errors.password && <FieldError>{errors.password}</FieldError>}
          </Field>
          <Field>
            <FieldLabel htmlFor="password_confirmation">
              Confirm new password
            </FieldLabel>
            <Input
              id="password_confirmation"
              type="password"
              value={data.password_confirmation}
              onChange={(e) => setData("password_confirmation", e.target.value)}
            />
            {errors.password_confirmation && (
              <FieldError>{errors.password_confirmation}</FieldError>
            )}
          </Field>
        </FieldGroup>
        <div>
          <Button size="sm" type="submit" disabled={processing}>
            Update password
          </Button>
        </div>
      </form>
    </Section>
  )
}

function OAuthPasswordSection() {
  return (
    <Section
      title="Password"
      description="Password management for your account."
    >
      <Alert>
        <Info className="size-4" />
        <AlertDescription>
          You signed in with Google. Password is managed by your identity
          provider and cannot be changed here.
        </AlertDescription>
      </Alert>
    </Section>
  )
}

function DangerZoneSection() {
  const page = usePage<SharedProps>()
  const { currentUser } = page.props
  const { delete: destroy, processing } = useForm({})
  const [open, setOpen] = useState(false)
  const settingsPath = withAccountScope(page.url, "/app/settings")
  const isOwner = currentUser?.role === "owner"
  const deleteLabel = processing
    ? isOwner
      ? "Cancelling..."
      : "Leaving..."
    : isOwner
      ? "Yes, cancel account"
      : "Yes, leave account"

  function handleDelete() {
    destroy(settingsPath, {
      onSuccess: () => setOpen(false),
    })
  }

  return (
    <Section
      title={isOwner ? "Cancel Account" : "Leave Account"}
      description={
        isOwner
          ? "Cancel this account. You have 30 days to reactivate before data is permanently deleted."
          : "Leave this account. Your data will be preserved but you will lose access."
      }
    >
      <div className="flex items-center justify-between rounded-md border border-destructive/20 bg-destructive/5 px-4 py-3">
        <div>
          <p className="text-sm font-medium">
            {currentUser?.accountName ?? currentUser?.name}
          </p>
          <p className="text-xs text-muted-foreground">{currentUser?.email}</p>
        </div>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger render={<Button variant="destructive" size="sm" />}>
            {isOwner ? "Cancel account" : "Leave account"}
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {isOwner ? "Cancel this account?" : "Leave this account?"}
              </DialogTitle>
              <DialogDescription>
                {isOwner
                  ? "This account will be scheduled for deletion in 30 days. You can reactivate it during this period."
                  : "You will lose access to this account. An admin can re-invite you later."}
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => setOpen(false)}
                disabled={processing}
              >
                Go back
              </Button>
              <Button
                variant="destructive"
                onClick={handleDelete}
                disabled={processing}
              >
                {deleteLabel}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </Section>
  )
}

export default function AppSettings({
  name,
  email,
  passwordChangeable,
}: Props) {
  return (
    <AppLayout>
      <Head title="Settings" />
      <div className="flex flex-col gap-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
          <p className="text-sm text-muted-foreground">
            Manage your account settings and preferences.
          </p>
        </div>
        <Card>
          <CardContent className="flex flex-col gap-6 pt-6">
            <ProfileSection name={name} email={email} />
            <Separator />
            {passwordChangeable ? (
              <PasswordSection />
            ) : (
              <OAuthPasswordSection />
            )}
            <Separator />
            <DangerZoneSection />
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  )
}
