import type { ComponentProps, FormEvent } from "react"
import { Head, useForm, usePage } from "@inertiajs/react"
import { BookOpen, Code2, FileText, Globe } from "lucide-react"

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
import AppLayout from "@/layouts/app-layout"

// --- Brand icons (not in lucide) ---

function GitHubIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  )
}

function GitLabIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 14.5L10.9 5.27H5.1L8 14.5z" />
      <path d="M8 14.5L5.1 5.27H1.22L8 14.5z" opacity={0.7} />
      <path
        d="M1.22 5.27L.34 7.98c-.08.24.01.5.22.64L8 14.5 1.22 5.27z"
        opacity={0.5}
      />
      <path d="M1.22 5.27h3.88L3.56.44c-.09-.28-.49-.28-.58 0L1.22 5.27z" />
      <path d="M8 14.5l2.9-9.23h3.88L8 14.5z" opacity={0.7} />
      <path
        d="M14.78 5.27l.88 2.71c.08.24-.01.5-.22.64L8 14.5l6.78-9.23z"
        opacity={0.5}
      />
      <path d="M14.78 5.27H10.9l1.56-4.83c.09-.28.49-.28.58 0l1.74 4.83z" />
    </svg>
  )
}

function BitbucketIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M.778 1.212a.768.768 0 00-.768.892l2.17 13.203a1.043 1.043 0 001.032.893h9.863a.768.768 0 00.768-.645l2.17-13.451a.768.768 0 00-.768-.892H.778zm9.14 9.59H6.166L5.347 5.54h5.39l-.82 5.263z" />
    </svg>
  )
}

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
