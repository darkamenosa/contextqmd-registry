import { useState, type ReactNode } from "react"
import { Mail } from "lucide-react"

import {
  getSourceFaviconDomain,
  normalizeSourceKey,
  sourceNeedsLightBackground,
} from "../../lib/source-visuals"

export function SourceIcon({ name }: { name: string }) {
  const [error, setError] = useState(false)
  const slug = name.toLowerCase()
  const normalizedName = normalizeSourceKey(name)

  const categoryEmojis: Record<string, string> = {
    "Direct / None": "↩️",
    "Organic Search": "🔍",
    "Organic Social": "👥",
    "Paid Search": "💰",
    Email: "✉️",
    Referral: "🔗",
  }

  const renderIconBadge = (icon: ReactNode, className: string) => (
    <span
      className={`flex size-6 items-center justify-center rounded-full ${className}`}
      aria-hidden
    >
      {icon}
    </span>
  )

  const knownLocalIcon = () => {
    if (
      normalizedName === "newsletter" ||
      normalizedName === "email" ||
      normalizedName === "emails"
    ) {
      return renderIconBadge(
        <Mail className="size-3.5" strokeWidth={2.1} />,
        "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300"
      )
    }
    return null
  }

  const fallbackEmoji = () => {
    if (slug.includes("google")) return "🔍"
    if (slug.includes("perplexity") || slug.includes("chatgpt")) return "🤖"
    if (slug.includes("facebook")) return "📘"
    if (slug.includes("twitter") || slug.includes("x.com")) return "🐦"
    if (slug.includes("github")) return "🐙"
    if (slug.includes("bing")) return "🅱️"
    if (slug.includes("brave")) return "🦁"
    if (slug.includes("duck")) return "🦆"
    if (slug.includes("slack")) return "💬"
    if (slug.includes("product hunt") || slug.includes("producthunt"))
      return "🚀"
    if (slug.includes("teams")) return "👥"
    if (slug.includes("wikipedia")) return "📚"
    if (slug.includes("email")) return "✉️"
    if (slug.includes("direct") || slug.includes("none")) return "↩️"
    if (slug.includes("linkedin")) return "💼"
    if (slug.includes("youtube")) return "📺"
    if (slug.includes("reddit")) return "🤖"
    if (slug.includes("instagram")) return "📷"
    if (slug.includes("search")) return "🔍"
    if (slug.includes("social")) return "👥"
    if (slug.includes("referral") || slug.includes("link")) return "🔗"
    return null
  }

  if (!name) {
    return fallbackBadge("#")
  }

  if (categoryEmojis[name]) {
    return (
      <span
        className="flex size-6 items-center justify-center text-lg"
        aria-hidden
      >
        {categoryEmojis[name]}
      </span>
    )
  }

  const localIcon = knownLocalIcon()
  if (localIcon) return localIcon

  if (error) {
    const emoji = fallbackEmoji()
    if (emoji) {
      return (
        <span
          className="flex size-6 items-center justify-center text-lg"
          aria-hidden
        >
          {emoji}
        </span>
      )
    }
    return fallbackBadge(name)
  }

  const domain = getSourceFaviconDomain(name)
  if (!domain) {
    const emoji = fallbackEmoji()
    return emoji ? (
      <span
        className="flex size-6 items-center justify-center text-lg"
        aria-hidden
      >
        {emoji}
      </span>
    ) : (
      fallbackBadge(name)
    )
  }

  return (
    <span className="flex size-6 items-center justify-center" aria-hidden>
      <img
        src={`/favicon/sources/${encodeURIComponent(name)}`}
        alt=""
        className={[
          "size-5 shrink-0 object-contain",
          sourceNeedsLightBackground(domain)
            ? "rounded-full border border-white/90 bg-white p-0.5"
            : "",
        ]
          .filter(Boolean)
          .join(" ")}
        onError={() => setError(true)}
        referrerPolicy="no-referrer"
      />
    </span>
  )
}

function fallbackBadge(value: string) {
  const badge = value.slice(0, 1).toUpperCase() || "#"
  const palette = [
    "bg-primary/10 text-primary",
    "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400",
    "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400",
    "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
    "bg-rose-100 text-rose-700 dark:bg-rose-900/30 dark:text-rose-400",
  ]
  const hash = value
    .split("")
    .reduce((acc, char) => acc + char.charCodeAt(0), 0)
  const classes = palette[hash % palette.length]

  return (
    <span
      className={`flex size-6 items-center justify-center rounded-full text-[10px] font-semibold ${classes}`}
      aria-hidden
    >
      {badge}
    </span>
  )
}
