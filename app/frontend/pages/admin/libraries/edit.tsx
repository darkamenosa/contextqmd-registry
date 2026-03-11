import { Head, Link, useForm } from "@inertiajs/react"
import type { CrawlRules } from "@/types"
import { ChevronLeft, FolderGit2, Globe, Save, X } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
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

function DefaultTags({ items }: { items: readonly string[] }) {
  return (
    <div className="flex flex-wrap gap-1">
      {items.map((item) => (
        <span
          key={item}
          className="inline-block rounded-sm bg-muted px-1.5 py-px font-mono text-[10px]/4 text-muted-foreground"
        >
          {item}
        </span>
      ))}
    </div>
  )
}

export default function AdminLibraryEdit({ library, versions }: Props) {
  const rules = library.crawlRules || {}
  const sourceType = library.sourceType
  const isGit =
    !sourceType || ["git", "github", "gitlab", "bitbucket"].includes(sourceType)
  const isWebsite = !sourceType || sourceType === "website"
  const hasBothSources = isGit && isWebsite

  const { data, setData, patch, processing, transform } = useForm({
    displayName: library.displayName,
    homepageUrl: library.homepageUrl || "",
    defaultVersion: library.defaultVersion || "",
    aliases: library.aliases.join(", "),
    gitIncludePrefixes: (rules.gitIncludePrefixes || []).join("\n"),
    gitIncludeBasenames: (rules.gitIncludeBasenames || []).join("\n"),
    gitExcludePrefixes: (rules.gitExcludePrefixes || []).join("\n"),
    gitExcludeBasenames: (rules.gitExcludeBasenames || []).join("\n"),
    websiteExcludePathPrefixes: (rules.websiteExcludePathPrefixes || []).join(
      "\n"
    ),
  })

  function handleSubmit(e: React.FormEvent) {
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
          git_include_basenames: data.gitIncludeBasenames,
          git_exclude_prefixes: data.gitExcludePrefixes,
          git_exclude_basenames: data.gitExcludeBasenames,
          website_exclude_path_prefixes: data.websiteExcludePathPrefixes,
        },
      },
    }))
    patch(`/admin/libraries/${library.id}`)
  }

  const defaultTab = isGit ? "git" : "website"

  return (
    <AdminLayout>
      <Head title={`Edit ${library.displayName}`} />

      <form onSubmit={handleSubmit} className="flex flex-col gap-5">
        {/* Header */}
        <div className="flex items-center gap-2">
          <Link
            href={`/admin/libraries/${library.id}`}
            aria-label="Back to library"
            className="rounded-sm p-0.5 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ChevronLeft className="size-4" />
          </Link>
          <h1 className="text-base/6 font-semibold">
            Edit <span className="text-foreground">{library.displayName}</span>
          </h1>
          <Badge
            variant="outline"
            className="font-mono text-[11px] font-normal"
          >
            {library.namespace}/{library.name}
          </Badge>
        </div>

        {/* --- Metadata section --- */}
        <section>
          <div className="mb-3 flex items-center gap-2 border-b pb-2">
            <h2 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
              Metadata
            </h2>
          </div>
          <FieldGroup className="gap-4">
            <div className="grid gap-4 @lg/main:grid-cols-2">
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
            </div>
            <div className="grid gap-4 @lg/main:grid-cols-2">
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
                  <p className="py-1.5 text-sm text-muted-foreground">
                    No versions yet
                  </p>
                )}
              </Field>
              <Field>
                <FieldLabel htmlFor="aliases">Aliases</FieldLabel>
                <Input
                  id="aliases"
                  placeholder="react, reactjs, react-dom"
                  value={data.aliases}
                  onChange={(e) => setData("aliases", e.target.value)}
                />
                <FieldDescription>Comma-separated</FieldDescription>
              </Field>
            </div>
          </FieldGroup>
        </section>

        {/* --- Crawl rules section --- */}
        {(isGit || isWebsite) && (
          <section>
            <div className="mb-3 flex items-center gap-2 border-b pb-2">
              <h2 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                Crawl Rules
              </h2>
              <span className="text-[10px] text-muted-foreground/60">
                Custom entries extend built-in defaults
              </span>
            </div>

            {hasBothSources ? (
              <Tabs defaultValue={defaultTab}>
                <TabsList variant="line" className="mb-3">
                  {isGit && (
                    <TabsTrigger value="git" className="gap-1.5 text-xs">
                      <FolderGit2 className="size-3.5" />
                      Git
                    </TabsTrigger>
                  )}
                  {isWebsite && (
                    <TabsTrigger value="website" className="gap-1.5 text-xs">
                      <Globe className="size-3.5" />
                      Website
                    </TabsTrigger>
                  )}
                </TabsList>

                {isGit && (
                  <TabsContent value="git">
                    <GitRulesFields data={data} setData={setData} />
                  </TabsContent>
                )}
                {isWebsite && (
                  <TabsContent value="website">
                    <WebsiteRulesFields data={data} setData={setData} />
                  </TabsContent>
                )}
              </Tabs>
            ) : isGit ? (
              <div className="mb-3 flex items-center gap-1.5 text-xs text-muted-foreground">
                <FolderGit2 className="size-3.5" />
                <span className="font-medium">Git source</span>
              </div>
            ) : (
              <div className="mb-3 flex items-center gap-1.5 text-xs text-muted-foreground">
                <Globe className="size-3.5" />
                <span className="font-medium">Website source</span>
              </div>
            )}

            {!hasBothSources && isGit && (
              <GitRulesFields data={data} setData={setData} />
            )}
            {!hasBothSources && isWebsite && (
              <WebsiteRulesFields data={data} setData={setData} />
            )}
          </section>
        )}

        {/* --- Actions --- */}
        <div className="flex items-center gap-2 border-t pt-4">
          <Button
            type="submit"
            size="sm"
            disabled={processing}
            className="gap-1.5"
          >
            <Save className="size-3.5" />
            {processing ? "Saving..." : "Save Changes"}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="gap-1.5 text-muted-foreground"
            nativeButton={false}
            render={<Link href={`/admin/libraries/${library.id}`} />}
          >
            <X className="size-3.5" />
            Cancel
          </Button>
        </div>
      </form>
    </AdminLayout>
  )
}

// --- Git crawl rules fields ---

function GitRulesFields({
  data,
  setData,
}: {
  data: {
    gitIncludePrefixes: string
    gitIncludeBasenames: string
    gitExcludePrefixes: string
    gitExcludeBasenames: string
  }
  setData: (key: string, value: string) => void
}) {
  return (
    <FieldGroup className="gap-4">
      {/* 2x2 grid: Include/Exclude × Folders/Files */}
      <div className="grid gap-4 @lg/main:grid-cols-2">
        <Field>
          <FieldLabel htmlFor="gitIncludePrefixes">Include Folders</FieldLabel>
          <Textarea
            id="gitIncludePrefixes"
            placeholder={"docs\nguides"}
            value={data.gitIncludePrefixes}
            onChange={(e) => setData("gitIncludePrefixes", e.target.value)}
            className="min-h-16 font-mono text-xs"
            rows={3}
          />
          <FieldDescription className="text-xs">
            Root-relative paths to force-include (overrides excludes)
          </FieldDescription>
        </Field>

        <Field>
          <FieldLabel htmlFor="gitIncludeBasenames">Include Files</FieldLabel>
          <Textarea
            id="gitIncludeBasenames"
            placeholder={"CHANGELOG.md\nCONTRIBUTING.md"}
            value={data.gitIncludeBasenames}
            onChange={(e) => setData("gitIncludeBasenames", e.target.value)}
            className="min-h-16 font-mono text-xs"
            rows={3}
          />
          <FieldDescription className="text-xs">
            Force-include by filename (overrides file excludes)
          </FieldDescription>
        </Field>

        <Field>
          <FieldLabel htmlFor="gitExcludePrefixes">Exclude Folders</FieldLabel>
          <Textarea
            id="gitExcludePrefixes"
            placeholder={"internal\nscripts"}
            value={data.gitExcludePrefixes}
            onChange={(e) => setData("gitExcludePrefixes", e.target.value)}
            className="min-h-16 font-mono text-xs"
            rows={3}
          />
          <FieldDescription className="text-xs">
            Root-relative paths to skip (entire subtree pruned)
          </FieldDescription>
        </Field>

        <Field>
          <FieldLabel htmlFor="gitExcludeBasenames">Exclude Files</FieldLabel>
          <Textarea
            id="gitExcludeBasenames"
            placeholder={"MIGRATION.md\nINTERNAL.md"}
            value={data.gitExcludeBasenames}
            onChange={(e) => setData("gitExcludeBasenames", e.target.value)}
            className="min-h-16 font-mono text-xs"
            rows={3}
          />
          <FieldDescription className="text-xs">
            Skip by exact filename (any directory)
          </FieldDescription>
        </Field>
      </div>

      {/* Built-in defaults reference — separated from editing area */}
      <div className="rounded-md border border-dashed border-muted-foreground/20 bg-muted/30 px-3 py-2.5">
        <p className="mb-2 text-[11px] font-medium text-muted-foreground">
          Built-in defaults (always applied)
        </p>
        <div className="grid gap-3 @lg/main:grid-cols-2">
          <div>
            <p className="mb-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground/60 uppercase">
              Excluded folders
            </p>
            <div className="space-y-1.5">
              {Object.entries(GIT_DEFAULT_EXCLUDE_PREFIXES).map(
                ([group, items]) => (
                  <div key={group}>
                    <span className="text-[9px] font-medium text-muted-foreground/50">
                      {group}
                    </span>
                    <DefaultTags items={items} />
                  </div>
                )
              )}
            </div>
          </div>
          <div>
            <p className="mb-1.5 text-[10px] font-semibold tracking-wider text-muted-foreground/60 uppercase">
              Excluded files
            </p>
            <DefaultTags items={GIT_DEFAULT_EXCLUDE_BASENAMES} />
          </div>
        </div>
      </div>
    </FieldGroup>
  )
}

// --- Website crawl rules fields ---

function WebsiteRulesFields({
  data,
  setData,
}: {
  data: { websiteExcludePathPrefixes: string }
  setData: (key: string, value: string) => void
}) {
  return (
    <FieldGroup className="gap-4">
      <Field>
        <FieldLabel htmlFor="websiteExcludePathPrefixes">
          Exclude URL Paths
        </FieldLabel>
        <Textarea
          id="websiteExcludePathPrefixes"
          placeholder={"/careers/\n/press/"}
          value={data.websiteExcludePathPrefixes}
          onChange={(e) =>
            setData("websiteExcludePathPrefixes", e.target.value)
          }
          className="min-h-16 font-mono text-xs"
          rows={3}
        />
        <FieldDescription className="text-xs">
          Pages whose path starts with these prefixes won&apos;t be crawled
        </FieldDescription>
      </Field>

      <div className="rounded-md border border-dashed border-muted-foreground/20 bg-muted/30 px-3 py-2.5">
        <p className="mb-2 text-[11px] font-medium text-muted-foreground">
          Built-in defaults (always applied)
        </p>
        <DefaultTags items={WEBSITE_DEFAULT_EXCLUDE_PATHS} />
      </div>
    </FieldGroup>
  )
}
