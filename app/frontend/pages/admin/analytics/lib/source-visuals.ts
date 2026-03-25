const FAVICON_DOMAIN_MAP: Record<string, string> = {
  Google: "google.com",
  Bing: "bing.com",
  DuckDuckGo: "duckduckgo.com",
  "Yahoo!": "yahoo.com",
  "Yahoo! Mail": "mail.yahoo.com",
  Baidu: "baidu.com",
  Yandex: "yandex.ru",
  AOL: "aol.com",
  Ask: "ask.com",
  Ecosia: "ecosia.org",
  Qwant: "qwant.com",
  Naver: "naver.com",
  Seznam: "seznam.cz",
  Sogou: "sogou.com",
  Startpage: "startpage.com",
  Brave: "search.brave.com",
  Perplexity: "perplexity.ai",
  ChatGPT: "chatgpt.com",
  Slack: "app.slack.com",
  "Product Hunt": "producthunt.com",
  "Microsoft Teams": "statics.teams.cdn.office.net",
  Wikipedia: "en.wikipedia.org",
  Facebook: "facebook.com",
  Instagram: "instagram.com",
  Twitter: "twitter.com",
  LinkedIn: "linkedin.com",
  Pinterest: "pinterest.com",
  Reddit: "reddit.com",
  YouTube: "youtube.com",
  TikTok: "tiktok.com",
  WhatsApp: "web.whatsapp.com",
  Telegram: "web.telegram.org",
  Snapchat: "snapchat.com",
  Threads: "threads.net",
  Discord: "discord.com",
  Quora: "quora.com",
  VK: "vk.com",
  Weibo: "weibo.com",
  GitHub: "github.com",
  StackOverflow: "stackoverflow.com",
  "Hacker News": "news.ycombinator.com",
  Gmail: "mail.google.com",
  "Outlook.com": "mail.live.com",
}

const SOURCE_DOMAIN_ALIASES: Record<string, string> = {
  google: "google.com",
  brave: "search.brave.com",
  chatgpt: "chatgpt.com",
  perplexity: "perplexity.ai",
  slack: "app.slack.com",
  producthunt: "producthunt.com",
  microsoftteams: "statics.teams.cdn.office.net",
  teams: "statics.teams.cdn.office.net",
  wikipedia: "en.wikipedia.org",
  discordapp: "discord.com",
  facebook: "facebook.com",
  github: "github.com",
  hackernews: "news.ycombinator.com",
  hn: "news.ycombinator.com",
  linkedin: "linkedin.com",
  reddit: "reddit.com",
  twitter: "x.com",
  x: "x.com",
  youtube: "youtube.com",
}

export function normalizeSourceKey(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "")
}

const NORMALIZED_FAVICON_DOMAIN_MAP: Record<string, string> = Object.entries(
  FAVICON_DOMAIN_MAP
).reduce(
  (acc, [label, domain]) => {
    acc[normalizeSourceKey(label)] = domain
    return acc
  },
  { ...SOURCE_DOMAIN_ALIASES }
)

export function sourceNeedsLightBackground(domain: string) {
  const sourceDomain = domain.toLowerCase()
  return sourceDomain.includes("github") || sourceDomain.includes("chatgpt.com")
}

export function getSourceFaviconDomain(name: string): string | null {
  const trimmedName = name.trim()
  const slug = trimmedName.toLowerCase()
  const normalizedName = normalizeSourceKey(trimmedName)

  if (!trimmedName || /^\(none\)$/i.test(trimmedName) || /direct/.test(slug)) {
    return null
  }

  if (FAVICON_DOMAIN_MAP[trimmedName]) {
    return FAVICON_DOMAIN_MAP[trimmedName]
  }

  if (NORMALIZED_FAVICON_DOMAIN_MAP[normalizedName]) {
    return NORMALIZED_FAVICON_DOMAIN_MAP[normalizedName]
  }

  try {
    let urlStr = trimmedName
    if (/^\/\//.test(urlStr)) urlStr = `https:${urlStr}`
    if (!/^https?:/i.test(urlStr) && /\./.test(urlStr)) {
      urlStr = `https://${urlStr}`
    }
    const url = new URL(urlStr)
    return url.hostname
  } catch {
    if (/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(trimmedName)) {
      return trimmedName.split("/")[0]
    }
  }

  return null
}
