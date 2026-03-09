import { Head, Link, useForm, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { Command } from "lucide-react"

import { csrfToken } from "@/lib/csrf-token"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"

interface PageProps extends SharedProps {
  resetPasswordToken: string
  [key: string]: unknown
}

export default function ResetPasswordPage() {
  const { flash, resetPasswordToken } = usePage<PageProps>().props
  const { data, setData, put, processing, errors, transform } = useForm({
    password: "",
    passwordConfirmation: "",
  })

  const errorMessage =
    (errors as Record<string, string | undefined>).base || flash?.alert

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({
      authenticity_token: csrfToken(),
      identity: {
        password: data.password,
        password_confirmation: data.passwordConfirmation,
        reset_password_token: resetPasswordToken,
      },
    }))
    put("/password")
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 bg-muted p-6 md:p-10">
      <Head title="Reset password" />
      <div className="flex w-full max-w-sm flex-col gap-6">
        <Link
          href="/"
          className="flex items-center gap-2 self-center font-medium"
        >
          <div className="flex size-6 items-center justify-center rounded-md bg-primary text-primary-foreground">
            <Command className="size-4" />
          </div>
          ContextqmdRegistry
        </Link>

        <Card>
          <CardHeader className="text-center">
            <CardTitle className="text-xl">Reset password</CardTitle>
            <CardDescription>Enter your new password</CardDescription>
          </CardHeader>
          <CardContent>
            {errorMessage && (
              <div
                role="alert"
                className="mb-4 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive"
              >
                {errorMessage}
              </div>
            )}
            <form onSubmit={handleSubmit}>
              <FieldGroup className="gap-4">
                <Field>
                  <FieldLabel htmlFor="password">New password</FieldLabel>
                  <Input
                    id="password"
                    type="password"
                    placeholder="6+ characters"
                    value={data.password}
                    onChange={(e) => setData("password", e.target.value)}
                    required
                    autoFocus
                  />
                  {errors.password && (
                    <FieldError>{errors.password}</FieldError>
                  )}
                </Field>
                <Field>
                  <FieldLabel htmlFor="password-confirmation">
                    Confirm password
                  </FieldLabel>
                  <Input
                    id="password-confirmation"
                    type="password"
                    value={data.passwordConfirmation}
                    onChange={(e) =>
                      setData("passwordConfirmation", e.target.value)
                    }
                    required
                  />
                  {(errors as Record<string, string | undefined>)
                    .password_confirmation && (
                    <FieldError>
                      {
                        (errors as Record<string, string | undefined>)
                          .password_confirmation
                      }
                    </FieldError>
                  )}
                </Field>
                <Field>
                  <Button
                    type="submit"
                    className="w-full"
                    disabled={processing}
                  >
                    {processing ? "Resetting..." : "Reset password"}
                  </Button>
                </Field>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
