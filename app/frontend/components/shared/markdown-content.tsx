import { useMemo } from "react"
import ReactMarkdown, { type Components } from "react-markdown"
import remarkGfm from "remark-gfm"

import { cleanMarkdown } from "@/lib/format-date"
import { slugify } from "@/lib/heading-slug"
import { parseMarkdownWithTabs } from "@/lib/parse-markdown-tabs"
import {
  Tabs,
  TabsList,
  TabsTrigger,
  TabsContent,
} from "@/components/ui/tabs"

const remarkPlugins = [remarkGfm]

const externalLink: Components["a"] = ({ href, children, ...props }) => (
  <a href={href} target="_blank" rel="noopener noreferrer" {...props}>
    {children}
  </a>
)

const fullComponents: Components = {
  img: () => null,
  a: externalLink,
  h1: ({ children, ...props }) => (
    <h1 id={slugify(children)} {...props}>
      {children}
    </h1>
  ),
  h2: ({ children, ...props }) => (
    <h2 id={slugify(children)} {...props}>
      {children}
    </h2>
  ),
  h3: ({ children, ...props }) => (
    <h3 id={slugify(children)} {...props}>
      {children}
    </h3>
  ),
}

const minimalComponents: Components = {
  img: () => null,
  a: externalLink,
}

function MarkdownBlock({
  content,
  headingIds,
}: {
  content: string
  headingIds: boolean
}) {
  return (
    <ReactMarkdown
      remarkPlugins={remarkPlugins}
      components={headingIds ? fullComponents : minimalComponents}
    >
      {cleanMarkdown(content)}
    </ReactMarkdown>
  )
}

interface MarkdownContentProps {
  content: string
  /** Generate anchor IDs on headings (for full-page view with TOC) */
  headingIds?: boolean
}

/**
 * Renders markdown with support for VitePress-style :::tabs directives.
 * Shared across all pages that display documentation content.
 */
export function MarkdownContent({
  content,
  headingIds = false,
}: MarkdownContentProps) {
  const segments = useMemo(() => parseMarkdownWithTabs(content), [content])

  return (
    <>
      {segments.map((segment, i) => {
        if (segment.type === "markdown") {
          return (
            <MarkdownBlock
              key={i}
              content={segment.content}
              headingIds={headingIds}
            />
          )
        }

        return (
          <Tabs key={i} defaultValue={0} className="my-4">
            <TabsList variant="line">
              {segment.tabs.map((tab, j) => (
                <TabsTrigger key={j} value={j}>
                  {tab.name}
                </TabsTrigger>
              ))}
            </TabsList>
            {segment.tabs.map((tab, j) => (
              <TabsContent key={j} value={j} className="pt-2">
                <MarkdownBlock content={tab.content} headingIds={false} />
              </TabsContent>
            ))}
          </Tabs>
        )
      })}
    </>
  )
}
