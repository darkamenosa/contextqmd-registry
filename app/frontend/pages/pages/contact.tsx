import { Github, Mail } from "lucide-react"

import { Button } from "@/components/ui/button"
import PublicLayout from "@/layouts/public-layout"

export default function Contact() {
  return (
    <PublicLayout title="Contact">
      <section className="mx-auto max-w-7xl px-4 py-20 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            Contact
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight">
            Get in touch
          </h1>
          <p className="mt-6 text-lg text-muted-foreground">
            ContextQMD is an open-source project. For questions, bug reports,
            and feedback, reach out via email. GitHub repository coming soon.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4">
            <Button
              size="lg"
              nativeButton={false}
              render={
                <a href="mailto:contextqmd@example.com" />
              }
            >
              <Mail className="size-5" />
              Send us an Email
            </Button>
            <p className="flex items-center gap-2 text-sm text-muted-foreground">
              <Github className="size-4" />
              GitHub (coming soon)
            </p>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
