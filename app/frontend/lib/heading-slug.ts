import type { ReactNode } from "react"

function extractText(node: ReactNode): string {
  if (typeof node === "string") return node
  if (typeof node === "number") return String(node)
  if (!node) return ""
  if (Array.isArray(node)) return node.map(extractText).join("")
  if (typeof node === "object" && "props" in node) {
    return extractText(
      (node as { props: { children?: ReactNode } }).props.children
    )
  }
  return ""
}

/** Convert React children to a URL-safe slug for heading anchor IDs */
export function slugify(children: ReactNode): string {
  return extractText(children)
    .toLowerCase()
    .replace(/[^\w]+/g, "-")
}
