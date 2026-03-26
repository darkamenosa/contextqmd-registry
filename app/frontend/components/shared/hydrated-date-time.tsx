import {
  formatDateShort,
  formatDateShortUTC,
  formatDateTime,
  formatDateTimeUTC,
  formatTimeAgo,
} from "@/lib/format-date"
import { useHydrated } from "@/hooks/use-hydrated"

interface HydratedDateTimeProps {
  iso: string
  className?: string
}

interface HydratedTimeAgoProps extends HydratedDateTimeProps {
  includeMinutes?: boolean
}

export function HydratedDateTime({ iso, className }: HydratedDateTimeProps) {
  const hydrated = useHydrated()

  return (
    <time className={className} dateTime={iso}>
      {hydrated ? formatDateTime(iso) : formatDateTimeUTC(iso)}
    </time>
  )
}

export function HydratedDateShort({ iso, className }: HydratedDateTimeProps) {
  const hydrated = useHydrated()

  return (
    <time className={className} dateTime={iso}>
      {hydrated ? formatDateShort(iso) : formatDateShortUTC(iso)}
    </time>
  )
}

export function HydratedTimeAgo({
  iso,
  className,
  includeMinutes = false,
}: HydratedTimeAgoProps) {
  const hydrated = useHydrated()

  return (
    <time className={className} dateTime={iso}>
      {hydrated ? formatTimeAgo(iso, includeMinutes) : formatDateShortUTC(iso)}
    </time>
  )
}

export function HydratedCurrentYear() {
  return <>{new Date().getUTCFullYear()}</>
}
