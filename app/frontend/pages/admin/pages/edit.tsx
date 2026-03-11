import type { FormEvent } from "react"
import { Head, Link, useForm } from "@inertiajs/react"
import { ChevronLeft } from "lucide-react"

import { formatBytes } from "@/lib/format-date"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import AdminLayout from "@/layouts/admin-layout"

interface PageData {
  id: number
  pageUid: string
  path: string
  title: string
  content: string
  bytes: number
}

interface Props {
  page: PageData
  version: { id: number; version: string }
  library: { id: number; displayName: string }
}

export default function AdminPageEdit({ page, version, library }: Props) {
  const { data, setData, patch, processing, transform } = useForm({
    title: page.title,
    description: page.content,
  })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    transform((data) => ({ page: data }))
    patch(`/admin/pages/${page.id}`)
  }

  const contentBytes = new TextEncoder().encode(data.description).length

  return (
    <AdminLayout>
      <Head title={`Edit: ${page.title}`} />

      <div className="flex flex-col gap-4">
        {/* Header */}
        <div className="flex items-center gap-2.5">
          <Link
            href={`/admin/versions/${version.id}/pages`}
            aria-label="Back to pages"
            className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-lg font-semibold">Edit page</h1>
            <p className="text-sm text-muted-foreground">
              {library.displayName} / {version.version} / {page.path}
            </p>
          </div>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit}>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Page details</CardTitle>
            </CardHeader>
            <CardContent>
              <FieldGroup className="gap-5">
                <Field>
                  <FieldLabel htmlFor="title">Title</FieldLabel>
                  <Input
                    id="title"
                    value={data.title}
                    onChange={(e) => setData("title", e.target.value)}
                    required
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="content">Content (Markdown)</FieldLabel>
                  <Textarea
                    id="content"
                    value={data.description}
                    onChange={(e) => setData("description", e.target.value)}
                    className="min-h-[400px] font-mono text-sm"
                  />
                  <FieldDescription>
                    {formatBytes(contentBytes)} — page_uid: {page.pageUid}
                  </FieldDescription>
                </Field>

                <div className="flex items-center gap-3 pt-2">
                  <Button type="submit" disabled={processing}>
                    {processing ? "Saving..." : "Save changes"}
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    nativeButton={false}
                    render={
                      <Link href={`/admin/versions/${version.id}/pages`} />
                    }
                  >
                    Cancel
                  </Button>
                </div>
              </FieldGroup>
            </CardContent>
          </Card>
        </form>
      </div>
    </AdminLayout>
  )
}
