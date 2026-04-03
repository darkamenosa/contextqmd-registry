import { useCallback, useMemo, useRef, useState } from "react"
import ReactMarkdown, { type Components } from "react-markdown"
import rehypeHighlight from "rehype-highlight"
import remarkGfm from "remark-gfm"

import "highlight.js/styles/github-dark.min.css"

import { slugify } from "@/lib/heading-slug"
import { cleanMarkdown } from "@/lib/markdown"
import { parseMarkdownWithTabs } from "@/lib/parse-markdown-tabs"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"

const remarkPlugins = [remarkGfm]
const rehypePlugins = [rehypeHighlight]

function CodeBlockCopyButton({
  preRef,
}: {
  preRef: React.RefObject<HTMLPreElement | null>
}) {
  const [copied, setCopied] = useState(false)

  const handleCopy = useCallback(async () => {
    const text = preRef.current?.textContent ?? ""
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }, [preRef])

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="absolute top-2 right-2 rounded-md bg-zinc-800 px-2 py-1 text-xs text-zinc-400 opacity-0 transition-opacity group-hover:opacity-100 hover:bg-zinc-700 hover:text-zinc-200"
    >
      {copied ? "Copied!" : "Copy"}
    </button>
  )
}

function CodeBlock({ children, ...props }: React.ComponentProps<"pre">) {
  const ref = useRef<HTMLPreElement>(null)

  // Extract language from the code child's className
  const codeChild = Array.isArray(children)
    ? children.find(
        (c): c is React.ReactElement =>
          typeof c === "object" && c !== null && "props" in c
      )
    : typeof children === "object" && children !== null && "props" in children
      ? children
      : null
  const className =
    (codeChild as React.ReactElement<{ className?: string }>)?.props
      ?.className ?? ""
  const lang = className.replace(/^.*language-/, "").split(/\s/)[0]

  return (
    <div className="group relative">
      {lang && (
        <span className="absolute top-2 left-3 text-[10px] font-medium tracking-wider text-zinc-500 uppercase">
          {lang}
        </span>
      )}
      <CodeBlockCopyButton preRef={ref} />
      <pre ref={ref} {...props} className={lang ? "!pt-8" : undefined}>
        {children}
      </pre>
    </div>
  )
}

const externalLink: Components["a"] = ({ href, children, ...props }) => (
  <a href={href} target="_blank" rel="noopener noreferrer" {...props}>
    {children}
  </a>
)

const fullComponents: Components = {
  img: () => null,
  a: externalLink,
  pre: CodeBlock,
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
  pre: CodeBlock,
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
      rehypePlugins={rehypePlugins}
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
