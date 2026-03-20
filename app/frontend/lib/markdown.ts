/** Strip inline HTML tags (especially img) from markdown source before rendering */
export function cleanMarkdown(markdown: string): string {
  return markdown.replace(/<img[^>]*>/gi, "").replace(/<br\s*\/?>/gi, "\n")
}
