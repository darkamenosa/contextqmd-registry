import { Link } from "@inertiajs/react"
import { ArrowLeft, ExternalLink } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import PublicLayout from "@/layouts/public-layout"

interface LibraryDetail {
  namespace: string
  name: string
  displayName: string
  aliases: string[]
  homepageUrl: string | null
  defaultVersion: string | null
  licenseStatus: string | null
}

interface VersionItem {
  version: string
  channel: string
  generatedAt: string | null
  pageCount: number
}

interface Props {
  library: LibraryDetail
  versions: VersionItem[]
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

function ChannelBadge({ channel }: { channel: string }) {
  const variant =
    channel === "stable"
      ? "secondary"
      : channel === "latest"
        ? "default"
        : "outline"

  return <Badge variant={variant}>{channel}</Badge>
}

function formatDate(iso: string | null): string {
  if (!iso) return "-"
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

export default function LibraryShow({ library, versions }: Props) {
  const slug = `${library.namespace}/${library.name}`
  const apiEndpoint = `/api/v1/libraries/${slug}`

  return (
    <PublicLayout title={library.displayName}>
      <section className="mx-auto max-w-7xl px-4 pt-16 pb-12 sm:px-6 lg:px-8">
        {/* Back link */}
        <Button
          variant="ghost"
          size="sm"
          nativeButton={false}
          render={<Link href="/libraries" />}
          className="mb-6"
        >
          <ArrowLeft className="size-4" />
          Back to Libraries
        </Button>

        {/* Header */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
              {library.displayName}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">{slug}</p>
            <div className="mt-3 flex items-center gap-2">
              <LicenseBadge status={library.licenseStatus} />
              {library.defaultVersion && (
                <Badge variant="outline">v{library.defaultVersion}</Badge>
              )}
            </div>
          </div>
          {library.homepageUrl && (
            <Button variant="outline" nativeButton={false} render={<a href={library.homepageUrl} target="_blank" rel="noopener noreferrer" />}>
              <ExternalLink className="size-4" />
              Homepage
            </Button>
          )}
        </div>

        {/* Aliases */}
        {library.aliases.length > 0 && (
          <div className="mt-8">
            <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
              Aliases
            </h2>
            <div className="mt-2 flex flex-wrap gap-2">
              {library.aliases.map((alias) => (
                <Badge key={alias} variant="outline">
                  {alias}
                </Badge>
              ))}
            </div>
          </div>
        )}
      </section>

      {/* Versions table */}
      <section className="mx-auto max-w-7xl px-4 pb-12 sm:px-6 lg:px-8">
        <h2 className="text-lg font-semibold">Versions</h2>
        {versions.length === 0 ? (
          <p className="mt-4 text-sm text-muted-foreground">
            No versions have been published yet.
          </p>
        ) : (
          <div className="mt-4 rounded-xl border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Version</TableHead>
                  <TableHead>Channel</TableHead>
                  <TableHead>Generated</TableHead>
                  <TableHead className="text-right">Pages</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {versions.map((v) => (
                  <TableRow key={v.version}>
                    <TableCell className="font-medium">{v.version}</TableCell>
                    <TableCell>
                      <ChannelBadge channel={v.channel} />
                    </TableCell>
                    <TableCell>{formatDate(v.generatedAt)}</TableCell>
                    <TableCell className="text-right">{v.pageCount}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

      {/* API usage */}
      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        <h2 className="text-lg font-semibold">API Usage</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Access this library programmatically via the ContextQMD API.
        </p>
        <div className="mt-4 overflow-x-auto rounded-lg border bg-muted/30 px-4 py-3">
          <code className="text-sm">
            GET {apiEndpoint}
          </code>
        </div>
      </section>
    </PublicLayout>
  )
}
