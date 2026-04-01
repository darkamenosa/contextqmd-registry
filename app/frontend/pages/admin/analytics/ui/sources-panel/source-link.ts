export function buildSourceExternalLink(name: string) {
  if (!name || name === "Direct / None" || name.startsWith("(")) return null

  return /^(https?:)?\/\//i.test(name)
    ? name.startsWith("http")
      ? name
      : `https:${name}`
    : `https://${name}`
}
