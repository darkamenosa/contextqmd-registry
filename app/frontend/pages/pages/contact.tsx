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
            and feature requests, open an issue on GitHub or reach out via
            email.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <Button
              size="lg"
              nativeButton={false}
              render={
                <a
                  href="https://github.com/contextqmd/contextqmd"
                  target="_blank"
                  rel="noopener noreferrer"
                />
              }
            >
              <Github className="size-5" />
              GitHub
            </Button>
            <Button
              variant="outline"
              size="lg"
              nativeButton={false}
              render={<a href="mailto:hello@contextqmd.com" />}
            >
              <Mail className="size-5" />
              Email Us
            </Button>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
