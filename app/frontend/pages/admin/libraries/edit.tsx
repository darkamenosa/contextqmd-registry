import { useState, type FormEvent } from "react"
import { Head, Link, useForm } from "@inertiajs/react"
import type { CrawlRules } from "@/types"
import { ChevronDown, ChevronLeft, FolderGit2, Globe } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field"
import { Input } from "@/components/ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import AdminLayout from "@/layouts/admin-layout"

// Mirror server-side DEFAULT_* constants — shown for admin reference only.
const GIT_DEFAULT_EXCLUDE_PREFIXES = {
  "Build output": [
    "dist",
    "build",
    "out",
    "_build",
    "_site",
    ".next",
    ".nuxt",
    "target",
  ],
  Dependencies: ["vendor", "node_modules", ".bundle", "bower_components"],
  Tooling: [
    ".github",
    ".gitlab",
    ".circleci",
    ".husky",
    ".devcontainer",
    ".vscode",
    ".claude",
    ".codex",
  ],
  Test: [
    "test",
    "tests",
    "spec",
    "specs",
    "__tests__",
    "__mocks__",
    "fixtures",
    "testdata",
  ],
  "Archive/stale": [
    "archive",
    "archived",
    "deprecated",
    "legacy",
    "obsolete",
    "outdated",
    "superseded",
    "old",
    "previous",
  ],
  Examples: ["examples", "example", "demo", "demos", "sample", "samples"],
  i18n: [
    "i18n",
    "l10n",
    "locales",
    "translations",
    "zh-cn",
    "zh-tw",
    "zh-hk",
    "zh-mo",
    "zh-sg",
  ],
} as const

const GIT_DEFAULT_EXCLUDE_BASENAMES = [
  "CHANGELOG.md",
  "changelog.md",
  "CHANGELOG.mdx",
  "changelog.mdx",
  "LICENSE.md",
  "license.md",
  "LICENSE.txt",
  "license.txt",
  "CODE_OF_CONDUCT.md",
  "code_of_conduct.md",
  "CONTRIBUTING.md",
  "contributing.md",
  "SECURITY.md",
  "security.md",
  "NEWS.md",
] as const

const WEBSITE_DEFAULT_EXCLUDE_PATHS = [
  "/blog/",
  "/changelog/",
  "/releases/",
  "/pricing/",
  "/login/",
  "/signup/",
  "/account/",
  "/admin/",
  "/tag/",
  "/category/",
  "/author/",
  "/feed/",
] as const

const GIT_DEFAULT_PREFIX_COUNT = Object.values(
  GIT_DEFAULT_EXCLUDE_PREFIXES
).reduce((sum, arr) => sum + arr.length, 0)

interface LibraryEdit {
  id: number
  namespace: string
  name: string
  displayName: string
  homepageUrl: string | null
  defaultVersion: string | null
  aliases: string[]
  crawlRules: CrawlRules
  sourceType: string | null
}

interface Props {
  library: LibraryEdit
  versions: string[]
}

function TagList({ items }: { items: readonly string[] }) {
  return (
    <div className="flex flex-wrap gap-1">
      {items.map((item) => (
        <Badge
          key={item}
          variant="outline"
          className="font-mono text-[11px] font-normal text-muted-foreground"
        >
          {item}
        </Badge>
      ))}
    </div>
  )
}

function DefaultsCollapsible({
  label,
  count,
  children,
}: {
  label: string
  count: number
  children: React.ReactNode
}) {
  const [open, setOpen] = useState(false)

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger className="flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground">
        <ChevronDown
          className={`size-3.5 shrink-0 transition-transform ${open ? "" : "-rotate-90"}`}
        />
        {label}
        <Badge variant="secondary" className="ml-auto text-[10px] tabular-nums">
          {count}
        </Badge>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="mt-1.5 rounded-md border bg-muted/30 p-3">
          {children}
        </div>
      </CollapsibleContent>
    </Collapsible>
  )
}

export default function AdminLibraryEdit({ library, versions }: Props) {
  const rules = library.crawlRules || {}
  const sourceType = library.sourceType
  const isGit =
    !sourceType || ["git", "github", "gitlab", "bitbucket"].includes(sourceType)
  const isWebsite = !sourceType || sourceType === "website"

  const { data, setData, patch, processing, transform } = useForm({
    displayName: library.displayName,
    homepageUrl: library.homepageUrl || "",
    defaultVersion: library.defaultVersion || "",
    aliases: library.aliases.join(", "),
    gitIncludePrefixes: (rules.gitIncludePrefixes || []).join("\n"),
    gitExcludePrefixes: (rules.gitExcludePrefixes || []).join("\n"),
    gitExcludeBasenames: (rules.gitExcludeBasenames || []).join("\n"),
    websiteExcludePathPrefixes: (
      rules.websiteExcludePathPrefixes || []
    ).join("\n"),
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
        crawl_rules: {
          git_include_prefixes: data.gitIncludePrefixes,
          git_exclude_prefixes: data.gitExcludePrefixes,
          git_exclude_basenames: data.gitExcludeBasenames,
          website_exclude_path_prefixes: data.websiteExcludePathPrefixes,
        },
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

        <form onSubmit={handleSubmit} className="flex max-w-2xl flex-col gap-4">
          {/* --- Library metadata --- */}
          <Card>
            <CardHeader>
              <CardTitle>Library metadata</CardTitle>
              <CardDescription>
                Namespace and name cannot be changed as they are used for
                routing and API access.
              </CardDescription>
            </CardHeader>
            <CardContent>
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
                  <FieldLabel>Default Version</FieldLabel>
                  {versions.length > 0 ? (
                    <Select
                      value={data.defaultVersion || undefined}
                      onValueChange={(val) =>
                        setData("defaultVersion", val ?? "")
                      }
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Select a version" />
                      </SelectTrigger>
                      <SelectContent>
                        {versions.map((v) => (
                          <SelectItem key={v} value={v}>
                            {v}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <p className="text-sm text-muted-foreground">
                      No versions available yet.
                    </p>
                  )}
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
              </FieldGroup>
            </CardContent>
          </Card>

          {/* --- Git source crawl rules --- */}
          {isGit && (
            <Card>
              <CardHeader>
                <div className="flex items-center gap-2">
                  <FolderGit2 className="size-4 text-muted-foreground" />
                  <CardTitle>Git source rules</CardTitle>
                </div>
                <CardDescription>
                  Controls which directories and files are included when
                  crawling git repositories. Custom entries are additive — they
                  extend the built-in defaults, not replace them.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <FieldGroup className="gap-5">
                  <Field>
                    <FieldLabel htmlFor="gitIncludePrefixes">
                      Folders to Include
                    </FieldLabel>
                    <Textarea
                      id="gitIncludePrefixes"
                      placeholder={"docs\nguides"}
                      value={data.gitIncludePrefixes}
                      onChange={(e) =>
                        setData("gitIncludePrefixes", e.target.value)
                      }
                      className="min-h-[80px] font-mono text-sm"
                    />
                    <FieldDescription>
                      Directory prefixes to force-include (overrides all
                      excludes). Leave empty to include all folders not
                      excluded.
                    </FieldDescription>
                  </Field>

                  <Field>
                    <FieldLabel htmlFor="gitExcludePrefixes">
                      Folders to Exclude
                    </FieldLabel>
                    <Textarea
                      id="gitExcludePrefixes"
                      placeholder={"internal\nscripts"}
                      value={data.gitExcludePrefixes}
                      onChange={(e) =>
                        setData("gitExcludePrefixes", e.target.value)
                      }
                      className="min-h-[80px] font-mono text-sm"
                    />
                    <FieldDescription>
                      Additional directory prefixes to skip. Entire subtrees are
                      pruned — no files inside will be scanned.
                    </FieldDescription>
                  </Field>

                  <Field>
                    <FieldLabel htmlFor="gitExcludeBasenames">
                      Files to Exclude
                    </FieldLabel>
                    <Textarea
                      id="gitExcludeBasenames"
                      placeholder={"MIGRATION.md\nINTERNAL.md"}
                      value={data.gitExcludeBasenames}
                      onChange={(e) =>
                        setData("gitExcludeBasenames", e.target.value)
                      }
                      className="min-h-[80px] font-mono text-sm"
                    />
                    <FieldDescription>
                      Additional filenames to skip (matched by exact name, any
                      directory).
                    </FieldDescription>
                  </Field>

                  <Separator />

                  <DefaultsCollapsible
                    label="Default excluded folders"
                    count={GIT_DEFAULT_PREFIX_COUNT}
                  >
                    <div className="space-y-3">
                      {Object.entries(GIT_DEFAULT_EXCLUDE_PREFIXES).map(
                        ([group, items]) => (
                          <div key={group} className="space-y-1">
                            <span className="text-[11px] text-muted-foreground">
                              {group}
                            </span>
                            <TagList items={items} />
                          </div>
                        )
                      )}
                    </div>
                  </DefaultsCollapsible>

                  <DefaultsCollapsible
                    label="Default excluded files"
                    count={GIT_DEFAULT_EXCLUDE_BASENAMES.length}
                  >
                    <TagList items={GIT_DEFAULT_EXCLUDE_BASENAMES} />
                  </DefaultsCollapsible>
                </FieldGroup>
              </CardContent>
            </Card>
          )}

          {/* --- Website source crawl rules --- */}
          {isWebsite && (
            <Card>
              <CardHeader>
                <div className="flex items-center gap-2">
                  <Globe className="size-4 text-muted-foreground" />
                  <CardTitle>Website source rules</CardTitle>
                </div>
                <CardDescription>
                  Controls which URL paths are skipped when crawling website
                  documentation. Custom entries extend the built-in defaults.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <FieldGroup className="gap-5">
                  <Field>
                    <FieldLabel htmlFor="websiteExcludePathPrefixes">
                      Exclude URLs
                    </FieldLabel>
                    <Textarea
                      id="websiteExcludePathPrefixes"
                      placeholder={"/careers/\n/press/"}
                      value={data.websiteExcludePathPrefixes}
                      onChange={(e) =>
                        setData("websiteExcludePathPrefixes", e.target.value)
                      }
                      className="min-h-[80px] font-mono text-sm"
                    />
                    <FieldDescription>
                      URL path prefixes to skip. Pages whose path starts with
                      any of these will not be crawled.
                    </FieldDescription>
                  </Field>

                  <Separator />

                  <DefaultsCollapsible
                    label="Default excluded URL paths"
                    count={WEBSITE_DEFAULT_EXCLUDE_PATHS.length}
                  >
                    <TagList items={WEBSITE_DEFAULT_EXCLUDE_PATHS} />
                  </DefaultsCollapsible>
                </FieldGroup>
              </CardContent>
            </Card>
          )}

          <div className="flex items-center gap-3">
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
        </form>
      </div>
    </AdminLayout>
  )
}
