import type { ButtonHTMLAttributes } from "react"

export default function DetailsButton({
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      {...props}
      className={[
        "inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground transition hover:text-foreground focus:outline-2 focus:outline-primary",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {/* Magnifying glass (search/inspect) for "Details" */}
      <svg
        aria-hidden="true"
        className="size-4"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <circle cx="11" cy="11" r="7" />
        <line x1="21" y1="21" x2="16.65" y2="16.65" />
      </svg>
      {children ?? "Details"}
    </button>
  )
}
