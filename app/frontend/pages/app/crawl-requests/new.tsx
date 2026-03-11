import type { FormEvent } from "react"
import { Head, useForm, usePage } from "@inertiajs/react"
import { BookOpen } from "lucide-react"

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
import {
  BitbucketIcon,
  Code2,
  FileText,
  GitHubIcon,
  GitLabIcon,
  Globe,
} from "@/components/shared/source-type-icon"
import AppLayout from "@/layouts/app-layout"

// --- Source type config ---

interface SourceType {
  value: string
  label: string
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  icon: React.ComponentType<any>
  description: string
  placeholder: string
}

const sourceTypes: SourceType[] = [
  {
    value: "github",
    label: "GitHub",
    icon: GitHubIcon,
    description:
      "Index docs from a GitHub repository. Add /tree/<tag> for a specific version.",
    placeholder: "https://github.com/rails/rails/tree/v8.1.2",
  },
  {
    value: "gitlab",
    label: "GitLab",
    icon: GitLabIcon,
    description:
      "Index docs from a GitLab repository. Add /-/tree/<tag> for a specific version.",
    placeholder: "https://gitlab.com/inkscape/inkscape",
  },
  {
    value: "bitbucket",
    label: "Bitbucket",
    icon: BitbucketIcon,
    description: "Index docs from a Bitbucket repository.",
    placeholder: "https://bitbucket.org/atlassian/atlassian-frontend",
  },
  {
    value: "website",
    label: "Website",
    icon: Globe,
    description:
      "Crawl documentation from a website. Use the docs landing page URL.",
    placeholder: "https://nextjs.org/docs",
  },
  {
    value: "llms_txt",
    label: "llms.txt",
    icon: FileText,
    description:
      "Index from an llms.txt, llms-full.txt, or llms-small.txt file.",
    placeholder: "https://docs.anthropic.com/llms.txt",
  },
  {
    value: "openapi",
    label: "OpenAPI",
    icon: Code2,
    description: "Parse an OpenAPI or Swagger specification file.",
    placeholder: "https://api.example.com/openapi.json",
  },
]

// --- Page ---

export default function AppCrawlRequestsNew() {
  const { url: pageUrl } = usePage()
  const { data, setData, post, processing, transform } = useForm({
    url: "",
    sourceType: "github",
  })

  const selectedSource = sourceTypes.find((s) => s.value === data.sourceType)

  // POST to collection path: /app/:id/crawl (strip /new from current URL)
  const createPath = pageUrl.replace(/\/new$/, "")

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    transform((data) => ({
      crawl_request: {
        url: data.url,
      },
    }))
    post(createPath)
  }

  return (
    <AppLayout>
      <Head title="Submit Documentation URL" />

      <div className="mx-auto w-full max-w-3xl space-y-8">
        <div>
          <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">
            Submit Documentation URL
          </h1>
          <p className="mt-2 text-muted-foreground">
            Provide a URL to documentation you want indexed into the ContextQMD
            registry.
          </p>
        </div>

        {/* Source Type Selection */}
        <div>
          <h2 className="mb-3 text-sm font-semibold">Source type</h2>
          <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
            {sourceTypes.map((source) => {
              const isSelected = data.sourceType === source.value
              return (
                <button
                  key={source.value}
                  type="button"
                  onClick={() => setData("sourceType", source.value)}
                  className={`flex flex-col items-center gap-1.5 rounded-lg border px-2 py-3 text-center transition-all ${
                    isSelected
                      ? "border-primary bg-primary/5 shadow-sm"
                      : "border-border/50 bg-muted/30 hover:border-border hover:bg-muted/60"
                  }`}
                >
                  <source.icon
                    className={`size-5 transition-colors ${isSelected ? "text-foreground" : "text-muted-foreground"}`}
                  />
                  <span
                    className={`text-xs font-medium transition-colors ${isSelected ? "text-foreground" : "text-muted-foreground"}`}
                  >
                    {source.label}
                  </span>
                </button>
              )
            })}
          </div>
        </div>

        {/* URL Form */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-lg">
              {selectedSource && <selectedSource.icon className="size-5" />}
              {selectedSource?.label} URL
            </CardTitle>
            <CardDescription>{selectedSource?.description}</CardDescription>
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
                    The source type is auto-detected from the URL. Pick a type
                    above to see the expected format.
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
      </div>
    </AppLayout>
  )
}
