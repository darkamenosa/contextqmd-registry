import type { FormEvent } from "react"
import { Link, useForm } from "@inertiajs/react"
import { ArrowLeft } from "lucide-react"

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

export default function LibrariesNew() {
  const { data, setData, post, processing, transform } = useForm({
    namespace: "",
    name: "",
    displayName: "",
    homepageUrl: "",
    defaultVersion: "",
    aliases: "",
  })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    transform((data) => ({
      library: {
        namespace: data.namespace,
        name: data.name,
        display_name: data.displayName,
        homepage_url: data.homepageUrl || null,
        default_version: data.defaultVersion || null,
        aliases: data.aliases
          ? data.aliases
              .split(",")
              .map((a) => a.trim())
              .filter(Boolean)
          : [],
      },
    }))
    post("/libraries")
  }

  return (
    <PublicLayout title="Submit Library">
      <section className="mx-auto max-w-2xl px-4 pt-6 pb-16 sm:px-6 sm:pt-16 sm:pb-24 lg:px-8">
        <div className="-ml-3 mb-4 sm:mb-6">
          <Button
            variant="ghost"
            size="sm"
            nativeButton={false}
            render={<Link href="/libraries" />}
          >
            <ArrowLeft className="size-4" />
            Back to libraries
          </Button>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">Submit a Library</CardTitle>
            <CardDescription>
              Add a new library to the ContextQMD registry. All fields marked
              with * are required.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit}>
              <FieldGroup className="gap-5">
                <Field>
                  <FieldLabel htmlFor="namespace">Namespace *</FieldLabel>
                  <Input
                    id="namespace"
                    type="text"
                    placeholder="e.g. react"
                    value={data.namespace}
                    onChange={(e) => setData("namespace", e.target.value)}
                    pattern="[a-z0-9-]+"
                    title="Lowercase alphanumeric characters and hyphens only"
                    required
                  />
                  <FieldDescription>
                    Lowercase alphanumeric characters and hyphens only.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="name">Name *</FieldLabel>
                  <Input
                    id="name"
                    type="text"
                    placeholder="e.g. react-dom"
                    value={data.name}
                    onChange={(e) => setData("name", e.target.value)}
                    pattern="[a-z0-9-]+"
                    title="Lowercase alphanumeric characters and hyphens only"
                    required
                  />
                  <FieldDescription>
                    Lowercase alphanumeric characters and hyphens only.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="displayName">Display Name *</FieldLabel>
                  <Input
                    id="displayName"
                    type="text"
                    placeholder="e.g. React DOM"
                    value={data.displayName}
                    onChange={(e) => setData("displayName", e.target.value)}
                    required
                  />
                  <FieldDescription>
                    Human-readable name shown in the registry.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="homepageUrl">Homepage URL</FieldLabel>
                  <Input
                    id="homepageUrl"
                    type="url"
                    placeholder="https://example.com/docs"
                    value={data.homepageUrl}
                    onChange={(e) => setData("homepageUrl", e.target.value)}
                  />
                  <FieldDescription>
                    Link to the library's homepage or documentation site.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="defaultVersion">
                    Default Version
                  </FieldLabel>
                  <Input
                    id="defaultVersion"
                    type="text"
                    placeholder="e.g. 1.0.0"
                    value={data.defaultVersion}
                    onChange={(e) => setData("defaultVersion", e.target.value)}
                  />
                  <FieldDescription>
                    The version to serve by default when no specific version is
                    requested.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="aliases">Aliases</FieldLabel>
                  <Input
                    id="aliases"
                    type="text"
                    placeholder="e.g. react, reactjs, react.js"
                    value={data.aliases}
                    onChange={(e) => setData("aliases", e.target.value)}
                  />
                  <FieldDescription>
                    Comma-separated list of alternative names for search.
                  </FieldDescription>
                </Field>

                <div className="pt-2">
                  <Button
                    type="submit"
                    className="w-full sm:w-auto"
                    disabled={processing}
                  >
                    {processing ? "Submitting..." : "Submit Library"}
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
