import type { FormEvent } from "react"
import { Link, useForm } from "@inertiajs/react"
import {
  ArrowLeft,
  BookOpen,
  Code2,
  FileCode,
  FileText,
  GitBranch,
  Globe,
} from "lucide-react"

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
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import PublicLayout from "@/layouts/public-layout"

const sourceTypes = [
  {
    value: "github",
    label: "GitHub",
    icon: GitBranch,
    description: "Index docs from a GitHub repository",
    placeholder: "https://github.com/vercel/next.js",
  },
  {
    value: "gitlab",
    label: "GitLab",
    icon: Code2,
    description: "Index docs from a GitLab repository",
    placeholder: "https://gitlab.com/org/project",
  },
  {
    value: "website",
    label: "Website",
    icon: Globe,
    description: "Crawl documentation from a website",
    placeholder: "https://nextjs.org/docs",
  },
  {
    value: "openapi",
    label: "OpenAPI",
    icon: FileCode,
    description: "Parse an OpenAPI/Swagger spec",
    placeholder: "https://api.example.com/openapi.json",
  },
  {
    value: "llms_txt",
    label: "LLMs.txt",
    icon: FileText,
    description: "Index from an llms.txt file",
    placeholder: "https://example.com/llms.txt",
  },
]

export default function CrawlRequestsNew() {
  const { data, setData, post, processing, transform } = useForm({
    url: "",
    sourceType: "github",
  })

  const selectedSource = sourceTypes.find((s) => s.value === data.sourceType)

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    transform((data) => ({
      crawl_request: {
        url: data.url,
        source_type: data.sourceType,
      },
    }))
    post("/crawl")
  }

  return (
    <PublicLayout title="Submit URL for Crawling">
      <section className="mx-auto max-w-3xl px-4 pt-16 pb-24 sm:px-6 lg:px-8">
        <div className="mb-8">
          <Button
            variant="ghost"
            size="sm"
            nativeButton={false}
            render={<Link href="/crawl" />}
          >
            <ArrowLeft className="size-4" />
            Back to Crawl Queue
          </Button>
        </div>

        <div className="mb-8">
          <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Submit Documentation URL
          </h1>
          <p className="mt-3 text-muted-foreground">
            Provide a URL to documentation you want indexed into the ContextQMD
            registry. We support multiple source types.
          </p>
        </div>

        {/* Source Type Selection */}
        <div className="mb-8">
          <h2 className="mb-4 text-sm font-semibold">
            Choose source type
          </h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {sourceTypes.map((source) => (
              <button
                key={source.value}
                type="button"
                onClick={() => setData("sourceType", source.value)}
                className={`flex flex-col items-center gap-2 rounded-xl border p-4 text-center transition-colors ${
                  data.sourceType === source.value
                    ? "border-primary bg-primary/5"
                    : "border-transparent bg-muted/50 hover:border-muted-foreground/20"
                }`}
              >
                <source.icon className="size-6" />
                <span className="text-sm font-medium">{source.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* URL Form */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-lg">
              {selectedSource && <selectedSource.icon className="size-5" />}
              {selectedSource?.label} URL
            </CardTitle>
            <CardDescription>
              {selectedSource?.description}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit}>
              <FieldGroup className="gap-5">
                <Field>
                  <FieldLabel htmlFor="url">Documentation URL</FieldLabel>
                  <Input
                    id="url"
                    type="url"
                    placeholder={selectedSource?.placeholder}
                    value={data.url}
                    onChange={(e) => setData("url", e.target.value)}
                    required
                  />
                  <FieldDescription>
                    The URL to the documentation source. For GitHub repos, use
                    the repository URL. For websites, use the docs landing page.
                  </FieldDescription>
                </Field>

                <div className="flex items-center gap-3 rounded-lg border bg-muted/30 p-4 text-sm text-muted-foreground">
                  <BookOpen className="size-5 shrink-0" />
                  <div>
                    <p className="font-medium text-foreground">
                      What happens next?
                    </p>
                    <p className="mt-1">
                      Your URL will be added to the crawl queue. We&apos;ll
                      fetch and index the documentation, then create a library
                      entry in the registry. This usually takes 1-10 minutes.
                    </p>
                  </div>
                </div>

                <div className="pt-2">
                  <Button
                    type="submit"
                    className="w-full sm:w-auto"
                    disabled={processing}
                  >
                    {processing ? "Submitting..." : "Submit for Crawling"}
                  </Button>
                </div>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      </section>
    </PublicLayout>
  )
}
