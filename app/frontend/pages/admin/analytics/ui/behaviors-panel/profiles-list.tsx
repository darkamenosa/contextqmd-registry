import { formatDateTime } from "@/lib/format-date"
import VisitorAvatar from "@/components/analytics/visitor-avatar"

import type { ProfileListItem } from "../../types"
import {
  ProfileBrowserInline,
  ProfileDeviceInline,
  ProfileLocationText,
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
  return (
    <div className="overflow-hidden rounded-md border border-border">
      <div className="hidden gap-3 border-b border-border px-4 py-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase sm:grid sm:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem]">
        <span>Visitor</span>
        <span>Source</span>
        <span className="text-right">Last seen</span>
      </div>
      <div className="divide-y divide-border">
        {profiles.map((profile) => (
          <button
            key={profile.id}
            type="button"
            className="flex w-full flex-col gap-1 px-4 py-2.5 text-left transition hover:bg-muted/30 sm:grid sm:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem] sm:items-center sm:gap-3"
            onClick={() => onSelect(profile)}
          >
            <div className="flex min-w-0 items-center gap-2.5">
              <VisitorAvatar name={profile.name} size={36} />
              <div className="min-w-0">
                <div className="flex min-w-0 items-center gap-1.5">
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
                  <ProfileLocationText
                    city={profile.city}
                    region={profile.region}
                    country={profile.country}
                    countryCode={profile.countryCode}
                    className="hidden sm:inline"
                  />
                  {profile.deviceType ? (
                    <>
                      <span className="hidden text-border sm:inline">·</span>
                      <ProfileDeviceInline
                        deviceType={profile.deviceType}
                        iconClassName="size-3.5"
                      />
                    </>
                  ) : null}
                  {profile.os ? (
                    <>
                      <span className="text-border">·</span>
                      <ProfileOSInline
                        os={profile.os}
                        iconClassName="size-3.5"
                      />
                    </>
                  ) : null}
                  {profile.browser ? (
                    <>
                      <span className="text-border">·</span>
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
                  <span>
                    {profile.lastSeenAt
                      ? formatDateTime(profile.lastSeenAt)
                      : "—"}
                  </span>
                </div>
              </div>
            </div>
            <div className="hidden min-w-0 text-sm text-foreground sm:block">
              <ProfileSourceInline source={profile.source} />
            </div>
            <div className="hidden text-right text-sm text-muted-foreground sm:block">
              {profile.lastSeenAt ? formatDateTime(profile.lastSeenAt) : "—"}
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
