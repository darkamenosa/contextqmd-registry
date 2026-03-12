/**
 * Parses VitePress-style :::tabs container directives from markdown.
 *
 * Input format:
 *   :::tabs key:frameworks
 *   == Vue
 *   ```js
 *   // code
 *   ```
 *   == React
 *   ```jsx
 *   // code
 *   ```
 *   :::
 */

interface MarkdownSegment {
  type: "markdown"
  content: string
}

interface TabItem {
  name: string
  content: string
}

interface TabsSegment {
  type: "tabs"
  tabs: TabItem[]
}

export type ContentSegment = MarkdownSegment | TabsSegment

export function parseMarkdownWithTabs(md: string): ContentSegment[] {
  const segments: ContentSegment[] = []
  const lines = md.split("\n")
  let i = 0
  let currentMarkdown = ""

  while (i < lines.length) {
    const tabsMatch = lines[i].match(/^:::tabs\s*(.*)$/)

    if (tabsMatch) {
      if (currentMarkdown.trim()) {
        segments.push({ type: "markdown", content: currentMarkdown.trim() })
      }
      currentMarkdown = ""

      const tabs: TabItem[] = []
      let currentTab: TabItem | null = null
      i++

      while (i < lines.length && lines[i].trim() !== ":::") {
        const tabMatch = lines[i].match(/^==\s+(.+)$/)
        if (tabMatch) {
          if (currentTab) {
            tabs.push({
              name: currentTab.name,
              content: currentTab.content.trim(),
            })
          }
          currentTab = { name: tabMatch[1].trim(), content: "" }
        } else if (currentTab) {
          currentTab.content += lines[i] + "\n"
        }
        i++
      }

      if (currentTab) {
        tabs.push({ name: currentTab.name, content: currentTab.content.trim() })
      }

      if (tabs.length > 0) {
        segments.push({ type: "tabs", tabs })
      }

      i++ // skip closing :::
    } else {
      currentMarkdown += lines[i] + "\n"
      i++
    }
  }

  if (currentMarkdown.trim()) {
    segments.push({ type: "markdown", content: currentMarkdown.trim() })
  }

  return segments
}
