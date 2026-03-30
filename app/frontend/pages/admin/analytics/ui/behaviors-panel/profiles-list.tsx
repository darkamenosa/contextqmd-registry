import { formatDateTime } from "@/lib/format-date"
import VisitorAvatar from "@/components/analytics/visitor-avatar"

import type { ProfileListItem } from "../../types"
import {
  ProfileBrowserInline,
  ProfileCompactLocationText,
  ProfileCountryText,
  ProfileDeviceInline,
  ProfileOSInline,
  ProfileSourceInline,
} from "../profile/primitives"

export default function ProfilesList({
  profiles,
  onSelect,
}: {
  profiles: ProfileListItem[]
  onSelect: (profile: ProfileListItem) => void
}) {
  const recentActivityScaleMax = Math.max(
    0,
    ...profiles.flatMap((profile) => profile.recentActivity || [])
  )

  return (
    <div className="overflow-hidden rounded-md border border-border">
      <div className="hidden gap-3 border-b border-border px-4 py-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase sm:grid sm:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem]">
        <span>Visitor</span>
        <span>Source</span>
        <span className="text-right">Last seen</span>
      </div>
      <div className="divide-y divide-border">
        {profiles.map((profile) => (
          <ProfileRow
            key={profile.id}
            profile={profile}
            onSelect={onSelect}
            recentActivityScaleMax={recentActivityScaleMax}
          />
        ))}
      </div>
    </div>
  )
}

function RecentActivityStrip({
  activity,
  scaleMax,
}: {
  activity?: number[]
  scaleMax: number
}) {
  const counts = activity?.length
    ? activity
    : Array.from({ length: 7 }, () => 0)

  return (
    <div className="flex items-center justify-end gap-1" aria-hidden="true">
      {counts.map((count, index) => {
        const intensity =
          count > 0 && scaleMax > 0 ? 0.25 + 0.75 * (count / scaleMax) : 0.08

        return (
          <span
            key={index}
            className="size-2 rounded-full bg-foreground"
            style={{ opacity: intensity }}
            title={`${count} visit${count === 1 ? "" : "s"} in this recent slot`}
          />
        )
      })}
    </div>
  )
}

function ProfileRow({
  profile,
  onSelect,
  recentActivityScaleMax,
}: {
  profile: ProfileListItem
  onSelect: (profile: ProfileListItem) => void
  recentActivityScaleMax: number
}) {
  const hasCompactLocation = Boolean(
    profile.city || profile.region || profile.country || profile.countryCode
  )

  return (
    <button
      type="button"
      className="flex w-full flex-col gap-1 px-4 py-2.5 text-left transition hover:bg-muted/30 sm:grid sm:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem] sm:items-center sm:gap-3"
      onClick={() => onSelect(profile)}
    >
      <div className="flex min-w-0 items-center gap-2.5">
        <VisitorAvatar name={profile.name} size={36} />
        <div className="min-w-0">
          <div className="flex min-w-0 items-center gap-1.5">
            <ProfileCountryText
              country={profile.country}
              countryCode={profile.countryCode}
              className="shrink-0 text-sm font-medium text-foreground sm:hidden"
            />
            {profile.country || profile.countryCode ? (
              <span className="shrink-0 text-foreground sm:hidden">-</span>
            ) : null}
            <span className="truncate text-sm font-medium text-foreground">
              {profile.name}
            </span>
            {profile.identified && (
              <span className="inline-flex shrink-0 items-center rounded-full border border-emerald-200 bg-emerald-50 px-1.5 py-px text-[10px] font-medium text-emerald-700">
                User
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
            <ProfileCompactLocationText
              city={profile.city}
              region={profile.region}
              country={profile.country}
              countryCode={profile.countryCode}
              className="hidden sm:inline"
            />
            {profile.deviceType ? (
              <>
                {hasCompactLocation ? (
                  <span className="hidden text-border sm:inline">·</span>
                ) : null}
                <ProfileDeviceInline
                  deviceType={profile.deviceType}
                  iconClassName="size-3.5"
                />
              </>
            ) : null}
            {profile.os ? (
              <>
                {profile.deviceType ? (
                  <span className="text-border">·</span>
                ) : hasCompactLocation ? (
                  <span className="hidden text-border sm:inline">·</span>
                ) : null}
                <ProfileOSInline os={profile.os} iconClassName="size-3.5" />
              </>
            ) : null}
            {profile.browser ? (
              <>
                {profile.deviceType || profile.os ? (
                  <span className="text-border">·</span>
                ) : hasCompactLocation ? (
                  <span className="hidden text-border sm:inline">·</span>
                ) : null}
                <ProfileBrowserInline
                  browser={profile.browser}
                  iconClassName="size-3.5"
                />
              </>
            ) : null}
          </div>
          <div className="mt-0.5 flex items-center gap-2 text-xs text-muted-foreground sm:hidden">
            <ProfileSourceInline source={profile.source} />
            <span className="text-border">·</span>
            <span suppressHydrationWarning>
              {profile.lastSeenAt ? formatDateTime(profile.lastSeenAt) : "—"}
            </span>
          </div>
        </div>
      </div>
      <div className="hidden min-w-0 text-sm text-foreground sm:block">
        <ProfileSourceInline source={profile.source} />
      </div>
      <div className="hidden items-end sm:flex sm:flex-col sm:gap-1">
        <div
          className="text-right text-sm text-muted-foreground"
          suppressHydrationWarning
        >
          {profile.lastSeenAt ? formatDateTime(profile.lastSeenAt) : "—"}
        </div>
        <RecentActivityStrip
          activity={profile.recentActivity}
          scaleMax={recentActivityScaleMax}
        />
      </div>
    </button>
  )
}
