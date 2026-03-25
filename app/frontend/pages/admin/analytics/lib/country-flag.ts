export function flagFromIso2(code?: string): string {
  if (!code) return ""

  const iso2 = String(code).toUpperCase()
  if (!/^[A-Z]{2}$/.test(iso2)) return ""

  const regionalIndicatorA = 0x1f1e6
  return Array.from(iso2)
    .map((char) =>
      String.fromCodePoint(regionalIndicatorA + (char.charCodeAt(0) - 65))
    )
    .join("")
}
