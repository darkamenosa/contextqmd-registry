import { Link } from "@inertiajs/react"
import { ArrowLeft, Home } from "lucide-react"

import { Button } from "@/components/ui/button"
import PublicLayout from "@/layouts/public-layout"

interface Props {
  status: number
  title: string
  message: string
}

export default function ErrorPage({ status, title, message }: Props) {
  return (
    <PublicLayout title={title} seo={{ noindex: true }}>
      <main className="flex flex-1 items-center justify-center px-4 py-24">
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
            <Button nativeButton={false} render={<Link href="/" />}>
              <Home className="size-4" />
              Go Home
            </Button>
            <Button variant="outline" onClick={() => window.history.back()}>
              <ArrowLeft className="size-4" />
              Go Back
            </Button>
          </div>
        </div>
      </main>
    </PublicLayout>
  )
}
