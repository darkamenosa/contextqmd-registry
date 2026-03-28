/**
 * Deterministic illustrated avatar for anonymous visitors.
 * Uses DiceBear "notionists" style — Notion-like illustrated faces.
 */
import { useMemo } from "react"
import { createAvatar } from "@dicebear/core"
import * as notionists from "@dicebear/notionists"

export default function VisitorAvatar({
  name,
  size = 40,
}: {
  name: string
  size?: number
}) {
  const svg = useMemo(
    () =>
      createAvatar(notionists, {
        seed: name,
        radius: 50,
        backgroundColor: ["f3f0eb", "e8e4de", "f0ece6"],
      }).toString(),
    [name]
  )

  return (
    <div
      className="shrink-0 overflow-hidden rounded-full"
      style={{ width: size, height: size }}
      dangerouslySetInnerHTML={{ __html: svg }}
      aria-hidden="true"
    />
  )
}
