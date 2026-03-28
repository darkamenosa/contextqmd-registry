import { Link2 } from "lucide-react"

import { cn } from "@/lib/utils"
import DeviceTypeIcon from "@/components/analytics/device-type-icon"

import { flagFromIso2 } from "../../lib/country-flag"
import { getBrowserIcon, getOSIcon } from "../../lib/device-visuals"
import { getSourceFaviconDomain } from "../../lib/source-visuals"
import { formatProfileLocation } from "./formatters"

export function ProfileLocationText({
  city,
  region,
  country,
  countryCode,
  order = "city-first",
  className,
}: {
  city?: string | null
  region?: string | null
  country?: string | null
  countryCode?: string | null
  order?: "city-first" | "country-first"
  className?: string
}) {
  const label = formatProfileLocation({ city, region, country }, order)
  const flag = flagFromIso2(countryCode ?? undefined)

  if (!label) return null

  return (
    <span className={className}>
      {flag ? `${flag} ` : ""}
      {label}
    </span>
  )
}

export function ProfileDeviceInline({
  deviceType,
  label,
  className,
  iconClassName,
  textClassName,
}: {
  deviceType?: string | null
  label?: string | null
  className?: string
  iconClassName?: string
  textClassName?: string
}) {
  if (!deviceType) return null

  return (
    <span className={cn("inline-flex items-center gap-1.5", className)}>
      <DeviceTypeIcon
        type={deviceType}
        className={cn("size-3.5", iconClassName)}
      />
      <span className={textClassName}>{label ?? deviceType}</span>
    </span>
  )
}

export function ProfileOSInline({
  os,
  className,
  iconClassName,
  textClassName,
}: {
  os?: string | null
  className?: string
  iconClassName?: string
  textClassName?: string
}) {
  if (!os) return null

  return (
    <span className={cn("inline-flex items-center gap-1.5", className)}>
      <img
        alt=""
        src={`/images/icon/os/${getOSIcon(os)}`}
        className={cn("size-4 shrink-0 object-contain", iconClassName)}
      />
      <span className={textClassName}>{os}</span>
    </span>
  )
}

export function ProfileBrowserInline({
  browser,
  className,
  iconClassName,
  textClassName,
}: {
  browser?: string | null
  className?: string
  iconClassName?: string
  textClassName?: string
}) {
  if (!browser) return null

  return (
    <span className={cn("inline-flex items-center gap-1.5", className)}>
      <img
        alt=""
        src={`/images/icon/browser/${getBrowserIcon(browser)}`}
        className={cn("size-4 shrink-0 object-contain", iconClassName)}
      />
      <span className={textClassName}>{browser}</span>
    </span>
  )
}

export function ProfileSourceInline({
  source,
  emptyLabel = "Direct/None",
  className,
  iconClassName,
  textClassName,
}: {
  source?: string | null
  emptyLabel?: string
  className?: string
  iconClassName?: string
  textClassName?: string
}) {
  const domain = source ? getSourceFaviconDomain(source) : null

  return (
    <span className={cn("inline-flex min-w-0 items-center gap-1.5", className)}>
      {domain ? (
        <img
          alt=""
          src={`/favicon/sources/${domain}`}
          className={cn("size-4 shrink-0 object-contain", iconClassName)}
        />
      ) : (
        <Link2
          className={cn("size-4 shrink-0 text-muted-foreground", iconClassName)}
        />
      )}
      <span className={cn("truncate", textClassName)}>
        {source || emptyLabel}
      </span>
    </span>
  )
}
