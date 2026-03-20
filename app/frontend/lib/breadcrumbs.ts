export interface BreadcrumbItemData {
  label: string
  href?: string
}

function segmentLabel(segment: string): string {
  return segment
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

export function buildBreadcrumbs({
  path,
  basePath,
  rootLabel = "Dashboard",
}: {
  path: string
  basePath: string
  rootLabel?: string
}): BreadcrumbItemData[] {
  const stripped = path.replace(new RegExp(`^${basePath}/?`), "")

  if (!stripped || stripped === "dashboard") {
    return [{ label: rootLabel }]
  }

  const segments = stripped.split("/").filter(Boolean)

  return segments.map((segment, index) => ({
    label: segmentLabel(segment),
    href:
      index < segments.length - 1
        ? `${basePath}/${segments.slice(0, index + 1).join("/")}`
        : undefined,
  }))
}
