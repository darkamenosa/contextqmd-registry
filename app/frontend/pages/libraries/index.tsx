import { useState, type FormEvent } from "react"
import { Link, router } from "@inertiajs/react"
import type { PaginationData } from "@/types"
import { BookOpen, FileText, Library, Plus, Search } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { LicenseBadge } from "@/components/shared/license-badge"
import { PaginationFooter } from "@/components/shared/pagination-footer"
import { SourceTypeIcon } from "@/components/shared/source-type-icon"
import PublicLayout from "@/layouts/public-layout"

interface LibraryItem {
  slug: string
  displayName: string
  aliases: string[]
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
  versionCount: number
  pageCount: number
  sourceType: string | null
}

interface SeoData {
  title?: string
  description?: string
  url?: string
  type?: "website" | "article" | "product"
  noindex?: boolean
  image?: string
}

interface Props {
  libraries: LibraryItem[]
  pagination: PaginationData
  query: string
  seo?: SeoData
}

export default function LibrariesIndex({
  libraries,
  pagination,
  query,
  seo,
}: Props) {
  const [search, setSearch] = useState(query)

  const handleSearch = (e: FormEvent) => {
    e.preventDefault()
    router.get("/libraries", search ? { query: search } : {}, {
      preserveState: true,
      preserveScroll: true,
    })
  }

  return (
    <PublicLayout seo={seo}>
      <section className="mx-auto max-w-7xl px-4 pt-8 pb-6 sm:px-6 sm:pt-16 sm:pb-12 lg:px-8">
        <div className="mx-auto max-w-3xl text-center">
          <h1 className="text-3xl font-bold tracking-tight sm:text-5xl">
            Libraries
          </h1>
          <p className="mt-2 text-base text-muted-foreground sm:mt-4 sm:text-lg">
            Search and install version-aware documentation for your AI coding
            tools.
          </p>
        </div>

        {/* Search + Submit */}
        <form
          onSubmit={handleSearch}
          className="mx-auto mt-5 flex max-w-xl flex-col gap-2 sm:mt-10 sm:flex-row sm:flex-wrap"
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
          <Button type="submit" className="w-full sm:w-auto">
            Search
          </Button>
          <Button
            variant="outline"
            nativeButton={false}
            render={<Link href="/crawl/new" />}
            className="w-full sm:w-auto"
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
                ? `${pagination.total} result${pagination.total !== 1 ? "s" : ""} for "${query}"`
                : `${pagination.total} libraries`}
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {libraries.map((lib) => (
                <Link
                  key={lib.slug}
                  href={`/libraries/${lib.slug}`}
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
                            {lib.slug}
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
            <PaginationFooter
              pagination={pagination}
              buildParams={(page) => {
                const params: Record<string, string | number> = { page }
                if (query) params.query = query
                return params
              }}
            />
          </>
        )}
      </section>
    </PublicLayout>
  )
}
