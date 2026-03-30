import { GitBranch, Mail } from "lucide-react"

import { Button } from "@/components/ui/button"
import PublicLayout from "@/layouts/public-layout"

interface SeoData {
  title?: string
  description?: string
  url?: string
  type?: "website" | "article" | "product"
  noindex?: boolean
  image?: string
}

interface Props {
  seo?: SeoData
}

export default function Contact({ seo }: Props) {
  return (
    <PublicLayout seo={seo}>
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-12 sm:px-6 sm:pt-16 sm:pb-20 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            Contact
          </p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
            Get in touch
          </h1>
          <p className="mt-3 text-base text-muted-foreground sm:mt-6 sm:text-lg">
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
              <GitBranch className="size-5" />
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
