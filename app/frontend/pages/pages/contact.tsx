import { ExternalLink, Github } from "lucide-react"

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
            and feedback, please open an issue on GitHub.
          </p>
          <div className="mt-8">
            <Button
              size="lg"
              nativeButton={false}
              render={
                <a
                  href="https://github.com/contextqmd/contextqmd-registry/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                />
              }
            >
              <Github className="size-5" />
              Open an Issue on GitHub
              <ExternalLink className="size-4" />
            </Button>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
