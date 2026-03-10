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
import { Checkbox } from "@/components/ui/checkbox"
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldSeparator,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"

type LoginPageProps = SharedProps & {
  googleOauthEnabled: boolean
  googleOauthAuthenticityToken: string
}

export default function LoginPage() {
  const { flash, googleOauthEnabled, googleOauthAuthenticityToken } =
    usePage<LoginPageProps>().props
  const { data, setData, post, processing, errors, transform } = useForm({
    email: "",
    password: "",
    remember: false,
  })

  // Combine error sources: useForm field errors + flash alert (from AuthFailure)
  const errorMessage =
    (errors as Record<string, string | undefined>).base || flash?.alert

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    transform((data) => ({
      authenticity_token: csrfToken(),
      identity: {
        email: data.email,
        password: data.password,
        remember_me: data.remember ? "1" : "0",
      },
    }))
    post("/login", {
      onFinish: () => setData("password", ""),
    })
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 bg-muted p-6 md:p-10">
      <Head title="Log in" />
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
              <CardTitle className="text-lg md:text-xl">Welcome back</CardTitle>
              <CardDescription>Sign in to your account</CardDescription>
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
                          className="w-full"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 24 24"
                            className="mr-2 size-4"
                          >
                            <path
                              d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z"
                              fill="currentColor"
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
                      <FieldLabel htmlFor="email">Email</FieldLabel>
                      <Input
                        id="email"
                        type="email"
                        placeholder="you@example.com"
                        value={data.email}
                        onChange={(e) => setData("email", e.target.value)}
                        required
                        autoFocus
                      />
                      {errors.email && <FieldError>{errors.email}</FieldError>}
                    </Field>
                    <Field className="grid grid-cols-[1fr_auto] gap-x-2 gap-y-2">
                      <FieldLabel
                        htmlFor="password"
                        className="col-start-1 row-start-1 w-auto"
                      >
                        Password
                      </FieldLabel>
                      <Input
                        id="password"
                        type="password"
                        value={data.password}
                        onChange={(e) => setData("password", e.target.value)}
                        required
                        className="col-span-2 row-start-2"
                      />
                      <Link
                        href="/password/new"
                        className="col-start-2 row-start-1 w-auto self-center justify-self-end text-xs underline-offset-4 hover:underline md:text-sm"
                      >
                        Forgot password?
                      </Link>
                      {errors.password && (
                        <FieldError className="col-span-2">
                          {errors.password}
                        </FieldError>
                      )}
                    </Field>
                    <Field orientation="horizontal">
                      <Checkbox
                        id="remember_me"
                        checked={data.remember}
                        onCheckedChange={(checked) =>
                          setData("remember", checked === true)
                        }
                      />
                      <FieldLabel htmlFor="remember_me">Remember me</FieldLabel>
                    </Field>
                    <Field>
                      <Button
                        type="submit"
                        className="w-full"
                        disabled={processing}
                      >
                        {processing ? "Signing in..." : "Sign in"}
                      </Button>
                      <FieldDescription className="text-center">
                        Don&apos;t have an account?{" "}
                        <Link
                          href="/register"
                          className="underline underline-offset-4"
                        >
                          Sign up
                        </Link>
                      </FieldDescription>
                    </Field>
                  </FieldGroup>
                </form>
              </FieldGroup>
            </CardContent>
          </Card>
          <FieldDescription className="px-6 text-center">
            By continuing, you agree to our{" "}
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
