import type { ComponentProps, ReactNode } from "react"
import { Code2, FileText, GitBranch, Globe } from "lucide-react"

export { Code2, FileText, GitBranch, Globe }

export function GitHubIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  )
}

export function GitLabIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M8 14.5L10.9 5.27H5.1L8 14.5z" />
      <path d="M8 14.5L5.1 5.27H1.22L8 14.5z" opacity={0.7} />
      <path
        d="M1.22 5.27L.34 7.98c-.08.24.01.5.22.64L8 14.5 1.22 5.27z"
        opacity={0.5}
      />
      <path d="M1.22 5.27h3.88L3.56.44c-.09-.28-.49-.28-.58 0L1.22 5.27z" />
      <path d="M8 14.5l2.9-9.23h3.88L8 14.5z" opacity={0.7} />
      <path
        d="M14.78 5.27l.88 2.71c.08.24-.01.5-.22.64L8 14.5l6.78-9.23z"
        opacity={0.5}
      />
      <path d="M14.78 5.27H10.9l1.56-4.83c.09-.28.49-.28.58 0l1.74 4.83z" />
    </svg>
  )
}

export function BitbucketIcon(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" {...props}>
      <path d="M.778 1.212a.768.768 0 00-.768.892l2.17 13.203a1.043 1.043 0 001.032.893h9.863a.768.768 0 00.768-.645l2.17-13.451a.768.768 0 00-.768-.892H.778zm9.14 9.59H6.166L5.347 5.54h5.39l-.82 5.263z" />
    </svg>
  )
}

interface SourceTypeConfig {
  label: string
  icon: ReactNode
}

// eslint-disable-next-line react-refresh/only-export-components
export function getSourceTypeConfig(
  sourceType: string,
  size = "size-3.5",
): SourceTypeConfig {
  switch (sourceType) {
    case "github":
    case "github_markdown":
      return { label: "GitHub", icon: <GitHubIcon className={size} /> }
    case "gitlab":
      return { label: "GitLab", icon: <GitLabIcon className={size} /> }
    case "bitbucket":
      return { label: "Bitbucket", icon: <BitbucketIcon className={size} /> }
    case "git":
      return { label: "Git", icon: <GitBranch className={size} /> }
    case "website":
      return { label: "Website", icon: <Globe className={size} /> }
    case "llms_txt":
    case "llms_full_txt":
      return { label: "llms.txt", icon: <FileText className={size} /> }
    case "openapi":
      return { label: "OpenAPI", icon: <Code2 className={size} /> }
    default:
      return { label: sourceType || "Unknown", icon: <Globe className={size} /> }
  }
}

export function SourceTypeIcon({
  sourceType,
  size = "size-3.5",
  showLabel = false,
  className = "",
}: {
  sourceType: string | null
  size?: string
  showLabel?: boolean
  className?: string
}) {
  if (!sourceType) return null
  const config = getSourceTypeConfig(sourceType, size)
  return (
    <span
      className={`inline-flex items-center gap-1.5 ${className}`}
      title={config.label}
    >
      {config.icon}
      {showLabel && <span className="text-xs">{config.label}</span>}
    </span>
  )
}
