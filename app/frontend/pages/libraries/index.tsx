import { useState, type FormEvent } from "react"
import { Link, router } from "@inertiajs/react"
import { BookOpen, FileText, Library, Plus, Search } from "lucide-react"

import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import PublicLayout from "@/layouts/public-layout"

interface LibraryItem {
  namespace: string
  name: string
  displayName: string
  aliases: string[]
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
  versionCount: number
  pageCount: number
  sourceType: string | null
}

interface Props {
  libraries: LibraryItem[]
  query: string
}

function LicenseBadge({ status }: { status: string | null }) {
  if (!status) return null

  const variant =
    status === "verified"
      ? "secondary"
      : status === "unclear"
        ? "outline"
        : "destructive"

  return <Badge variant={variant}>{status}</Badge>
}


export default function LibrariesIndex({ libraries, query }: Props) {
  const [search, setSearch] = useState(query)

  const handleSearch = (e: FormEvent) => {
    e.preventDefault()
    router.get("/libraries", search ? { query: search } : {}, {
      preserveState: true,
      preserveScroll: true,
    })
  }

  return (
    <PublicLayout title="Libraries">
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-3xl text-center">
          <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
            Libraries
          </h1>
          <p className="mt-4 text-lg text-muted-foreground">
            Browse documentation packages available through the ContextQMD
            registry.
          </p>
        </div>

        {/* Search + Submit */}
        <form
          onSubmit={handleSearch}
          className="mx-auto mt-10 flex max-w-xl gap-2"
        >
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              type="text"
              placeholder="Search libraries by name or alias..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9"
            />
          </div>
          <Button type="submit">Search</Button>
          <Button
            variant="outline"
            nativeButton={false}
            render={<Link href="/crawl/new" />}
          >
            <Plus className="size-4" />
            Submit
          </Button>
        </form>
      </section>

      {/* Results */}
      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        {libraries.length === 0 ? (
          <div className="mx-auto max-w-md py-16 text-center">
            <div className="mx-auto flex size-12 items-center justify-center rounded-xl bg-muted">
              <Library className="size-6 text-muted-foreground" />
            </div>
            <h2 className="mt-4 text-lg font-semibold">No libraries found</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              {query
                ? `No results for "${query}". Try a different search term.`
                : "No libraries have been added to the registry yet."}
            </p>
            {query && (
              <Button
                variant="outline"
                className="mt-6"
                nativeButton={false}
                render={<Link href="/libraries" />}
              >
                Clear search
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="mb-4 text-sm text-muted-foreground">
              {query
                ? `${libraries.length} result${libraries.length !== 1 ? "s" : ""} for "${query}"`
                : `${libraries.length} libraries`}
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {libraries.map((lib) => (
                <Link
                  key={`${lib.namespace}/${lib.name}`}
                  href={`/libraries/${lib.namespace}/${lib.name}`}
                  className="block"
                >
                  <Card className="h-full transition-colors hover:border-foreground/20">
                    <CardHeader>
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <CardTitle className="truncate">
                            {lib.displayName}
                          </CardTitle>
                          <p className="mt-1 text-xs text-muted-foreground">
                            {lib.namespace}/{lib.name}
                          </p>
                        </div>
                        <LicenseBadge status={lib.licenseStatus} />
                      </div>
                    </CardHeader>
                    <CardContent>
                      <div className="flex flex-wrap gap-1">
                        {lib.defaultVersion && (
                          <Badge variant="secondary">
                            v{lib.defaultVersion}
                          </Badge>
                        )}
                        {lib.sourceType && (
                          <Badge variant="outline" className="gap-1 text-xs">
                            <SourceTypeIcon
                              sourceType={lib.sourceType}
                              size="size-3"
                              showLabel
                            />
                          </Badge>
                        )}
                        {lib.aliases.map((alias) => (
                          <Badge
                            key={alias}
                            variant="outline"
                            className="text-xs"
                          >
                            {alias}
                          </Badge>
                        ))}
                      </div>
                      <div className="mt-3 flex items-center gap-3 text-xs text-muted-foreground">
                        {lib.versionCount > 0 && (
                          <span className="flex items-center gap-1">
                            <BookOpen className="size-3" />
                            {lib.versionCount} version
                            {lib.versionCount !== 1 ? "s" : ""}
                          </span>
                        )}
                        {lib.pageCount > 0 && (
                          <span className="flex items-center gap-1">
                            <FileText className="size-3" />
                            {lib.pageCount} page{lib.pageCount !== 1 ? "s" : ""}
                          </span>
                        )}
                        {lib.pageCount === 0 && lib.versionCount === 0 && (
                          <span className="italic">Not yet indexed</span>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              ))}
            </div>
          </>
        )}
      </section>
    </PublicLayout>
  )
}
