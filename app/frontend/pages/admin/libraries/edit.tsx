import type { FormEvent } from "react"
import { Head, Link, useForm } from "@inertiajs/react"
import { ChevronLeft } from "lucide-react"

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
import AdminLayout from "@/layouts/admin-layout"

interface LibraryEdit {
  id: number
  namespace: string
  name: string
  displayName: string
  homepageUrl: string | null
  defaultVersion: string | null
  aliases: string[]
}

interface Props {
  library: LibraryEdit
}

export default function AdminLibraryEdit({ library }: Props) {
  const { data, setData, patch, processing, transform } = useForm({
    displayName: library.displayName,
    homepageUrl: library.homepageUrl || "",
    defaultVersion: library.defaultVersion || "",
    aliases: library.aliases.join(", "),
  })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    transform((data) => ({
      library: {
        display_name: data.displayName,
        homepage_url: data.homepageUrl || null,
        default_version: data.defaultVersion || null,
        aliases: data.aliases
          .split(",")
          .map((a) => a.trim())
          .filter(Boolean),
      },
    }))
    patch(`/admin/libraries/${library.id}`)
  }

  return (
    <AdminLayout>
      <Head title={`Edit ${library.displayName}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center gap-2.5">
          <Link
            href={`/admin/libraries/${library.id}`}
            aria-label="Back to library"
            className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <h1 className="min-w-0 truncate text-lg font-semibold">
            Edit {library.displayName}
          </h1>
          <span className="font-mono text-sm text-muted-foreground">
            {library.namespace}/{library.name}
          </span>
        </div>

        <Card className="max-w-2xl">
          <CardHeader>
            <CardTitle>Library metadata</CardTitle>
            <CardDescription>
              Namespace and name cannot be changed as they are used for routing
              and API access.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit}>
              <FieldGroup className="gap-5">
                <Field>
                  <FieldLabel htmlFor="displayName">Display Name</FieldLabel>
                  <Input
                    id="displayName"
                    value={data.displayName}
                    onChange={(e) => setData("displayName", e.target.value)}
                    required
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="homepageUrl">Homepage URL</FieldLabel>
                  <Input
                    id="homepageUrl"
                    type="url"
                    placeholder="https://example.com"
                    value={data.homepageUrl}
                    onChange={(e) => setData("homepageUrl", e.target.value)}
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="defaultVersion">
                    Default Version
                  </FieldLabel>
                  <Input
                    id="defaultVersion"
                    placeholder="latest"
                    value={data.defaultVersion}
                    onChange={(e) => setData("defaultVersion", e.target.value)}
                  />
                  <FieldDescription>
                    The version shown by default on the library detail page.
                  </FieldDescription>
                </Field>

                <Field>
                  <FieldLabel htmlFor="aliases">Aliases</FieldLabel>
                  <Input
                    id="aliases"
                    placeholder="react, reactjs, react-dom"
                    value={data.aliases}
                    onChange={(e) => setData("aliases", e.target.value)}
                  />
                  <FieldDescription>
                    Comma-separated search aliases.
                  </FieldDescription>
                </Field>

                <div className="flex items-center gap-3 pt-2">
                  <Button type="submit" disabled={processing}>
                    {processing ? "Saving..." : "Save Changes"}
                  </Button>
                  <Button
                    variant="outline"
                    nativeButton={false}
                    render={<Link href={`/admin/libraries/${library.id}`} />}
                  >
                    Cancel
                  </Button>
                </div>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  )
}
