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
      <div className="grid grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem] gap-3 border-b border-border px-4 py-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase">
        <span>Visitor</span>
        <span>Source</span>
        <span className="text-right">Last seen</span>
      </div>
      <div className="divide-y divide-border">
        {profiles.map((profile) => (
          <button
            key={profile.id}
            type="button"
            className="grid w-full grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_10rem] items-center gap-3 px-4 py-2 text-left transition hover:bg-muted/30"
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
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <ProfileLocationText
                    city={profile.city}
                    region={profile.region}
                    country={profile.country}
                    countryCode={profile.countryCode}
                  />
                  {profile.deviceType ? (
                    <>
                      <span className="text-border">·</span>
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
              </div>
            </div>
            <div className="min-w-0 text-sm text-foreground">
              <ProfileSourceInline source={profile.source} />
            </div>
            <div className="text-right text-sm text-muted-foreground">
              {profile.lastSeenAt ? formatDateTime(profile.lastSeenAt) : "—"}
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
