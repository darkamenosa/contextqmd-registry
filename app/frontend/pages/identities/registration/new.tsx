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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldSeparator,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"

type RegisterPageProps = SharedProps & {
  googleOauthEnabled: boolean
  googleOauthAuthenticityToken: string
}

export default function RegisterPage() {
  const { flash, googleOauthEnabled, googleOauthAuthenticityToken } =
    usePage<RegisterPageProps>().props
  const { data, setData, post, processing, errors, transform } = useForm({
    name: "",
    email: "",
    password: "",
  })

  const errorMessage =
    (errors as Record<string, string | undefined>).base || flash?.alert

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({
      authenticity_token: csrfToken(),
      identity: { email: data.email, password: data.password },
      user: { name: data.name },
    }))
    post("/register")
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 bg-muted p-6 md:p-10">
      <Head title="Create account" />
      <div className="flex w-full max-w-sm flex-col gap-6">
        <Link
          href="/"
          className="flex items-center gap-2 self-center font-medium"
        >
          <div className="flex size-6 items-center justify-center rounded-md bg-primary text-primary-foreground">
            <Command className="size-4" />
          </div>
          ContextQMD
        </Link>

        <div className="flex flex-col gap-6">
          <Card>
            <CardHeader className="text-center">
              <CardTitle className="text-xl">Create an account</CardTitle>
              <CardDescription>Get started with ContextQMD</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="gap-5">
                {googleOauthEnabled && (
                  <>
                    <Field>
                      <form method="post" action="/auth/google_oauth2">
                        <input
                          type="hidden"
                          name="authenticity_token"
                          value={googleOauthAuthenticityToken}
                          readOnly
                        />
                        <Button
                          variant="outline"
                          type="submit"
                          className="w-full py-5"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 48 48"
                            className="mr-2 size-5"
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
                          Continue with Google
                        </Button>
                      </form>
                    </Field>
                    <FieldSeparator className="*:data-[slot=field-separator-content]:bg-card">
                      Or continue with
                    </FieldSeparator>
                  </>
                )}
                {errorMessage && (
                  <div
                    role="alert"
                    className="rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive"
                  >
                    {errorMessage}
                  </div>
                )}
                <form onSubmit={handleSubmit}>
                  <FieldGroup className="gap-4">
                    <Field>
                      <FieldLabel htmlFor="name">Name</FieldLabel>
                      <Input
                        id="name"
                        type="text"
                        placeholder="Your name"
                        value={data.name}
                        onChange={(e) => setData("name", e.target.value)}
                        autoFocus
                      />
                      {errors.name && <FieldError>{errors.name}</FieldError>}
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="email">Email</FieldLabel>
                      <Input
                        id="email"
                        type="email"
                        placeholder="you@example.com"
                        value={data.email}
                        onChange={(e) => setData("email", e.target.value)}
                        required
                      />
                      {errors.email && <FieldError>{errors.email}</FieldError>}
                    </Field>
                    <Field>
                      <FieldLabel htmlFor="password">Password</FieldLabel>
                      <Input
                        id="password"
                        type="password"
                        placeholder="6+ characters"
                        value={data.password}
                        onChange={(e) => setData("password", e.target.value)}
                        required
                      />
                      {errors.password && (
                        <FieldError>{errors.password}</FieldError>
                      )}
                    </Field>
                    <Field>
                      <Button
                        type="submit"
                        className="w-full"
                        disabled={processing}
                      >
                        {processing ? "Creating account..." : "Create account"}
                      </Button>
                      <FieldDescription className="text-center">
                        Already have an account?{" "}
                        <Link
                          href="/login"
                          className="underline underline-offset-4"
                        >
                          Sign in
                        </Link>
                      </FieldDescription>
                    </Field>
                  </FieldGroup>
                </form>
              </FieldGroup>
            </CardContent>
          </Card>
          <FieldDescription className="px-6 text-center">
            By creating an account, you agree to our{" "}
            <Link href="/terms" className="underline underline-offset-4">
              Terms of Service
            </Link>{" "}
            and{" "}
            <Link href="/privacy" className="underline underline-offset-4">
              Privacy Policy
            </Link>
            .
          </FieldDescription>
        </div>
      </div>
    </div>
  )
}
