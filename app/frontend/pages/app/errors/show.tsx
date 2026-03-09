import { Head, Link, usePage } from "@inertiajs/react"
import type { SharedProps } from "@/types"
import { ArrowLeft, Home } from "lucide-react"

import { withAccountScope } from "@/lib/account-scope"
import { Button } from "@/components/ui/button"
import AppLayout from "@/layouts/app-layout"

interface Props {
  status: number
  title: string
  message: string
}

export default function AppErrorPage({ status, title, message }: Props) {
  const page = usePage<SharedProps>()
  const accountId =
    page.props.currentUser?.accountId ??
    page.props.currentIdentity?.defaultAccountId
  const dashboardPath = withAccountScope(page.url, "/app/dashboard", accountId)

  return (
    <AppLayout>
      <Head title={title} />
      <main className="flex flex-1 items-center justify-center px-4 py-16">
        <div className="flex flex-col items-center gap-6 text-center">
          <div className="relative">
            <span className="text-8xl font-bold text-muted-foreground/20 select-none lg:text-9xl">
              {status}
            </span>
            <div className="absolute inset-0 flex items-center justify-center">
              <span className="text-7xl font-bold text-foreground lg:text-8xl">
                {status}
              </span>
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">
              {title}
            </h1>
            <p className="mx-auto max-w-sm text-pretty text-muted-foreground">
              {message}
            </p>
          </div>

          <div className="flex gap-3">
            <Button nativeButton={false} render={<Link href={dashboardPath} />}>
              <Home className="size-4" />
              Go to Dashboard
            </Button>
            <Button variant="outline" onClick={() => window.history.back()}>
              <ArrowLeft className="size-4" />
              Go Back
            </Button>
          </div>
        </div>
      </main>
    </AppLayout>
  )
}
