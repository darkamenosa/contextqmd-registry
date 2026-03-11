import { Badge } from "@/components/ui/badge"

export function LicenseBadge({ status }: { status: string | null }) {
  if (!status) return null

  const variant =
    status === "verified"
      ? "secondary"
      : status === "unclear"
        ? "outline"
        : "destructive"

  return <Badge variant={variant}>{status}</Badge>
}
