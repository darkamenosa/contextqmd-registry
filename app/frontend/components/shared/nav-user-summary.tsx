import { Avatar, AvatarFallback } from "@/components/ui/avatar"

interface NavUserSummaryProps {
  email: string
  initials: string
  name: string
  compact?: boolean
}

export function NavUserSummary({
  email,
  initials,
  name,
  compact = false,
}: NavUserSummaryProps) {
  return (
    <>
      <Avatar
        className={
          compact
            ? "size-10 rounded-lg"
            : "size-10 rounded-lg transition-[width,height] group-data-[collapsible=icon]:size-8"
        }
      >
        <AvatarFallback className="rounded-lg bg-primary text-primary-foreground">
          {initials}
        </AvatarFallback>
      </Avatar>
      <div className="grid flex-1 text-left text-sm leading-tight">
        <span className="truncate font-medium">{name}</span>
        <span className="truncate text-xs">{email}</span>
      </div>
    </>
  )
}
