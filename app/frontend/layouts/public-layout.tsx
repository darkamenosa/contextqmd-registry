import type { ReactNode } from "react"
import { Head } from "@inertiajs/react"

import { SiteFooter } from "@/components/site-footer"
import { SiteHeader } from "@/components/site-header"

interface PublicLayoutProps {
  children: ReactNode
  title?: string
  seo?: {
    title?: string
    description?: string
    image?: string
    url?: string
    type?: "website" | "article" | "product"
    noindex?: boolean
  }
  jsonLd?: object | object[]
  showHeader?: boolean
  showFooter?: boolean
}

const DEFAULT_SEO = {
  title: "ContextQMD",
  description:
    "Local-first documentation package system for CLI and MCP. Install, search, and retrieve version-aware docs for any library.",
  image: "/og-image.png",
} as const

export default function PublicLayout({
  children,
  title,
  seo,
  jsonLd,
  showHeader = true,
  showFooter = true,
}: PublicLayoutProps) {
  const seoTitle = seo?.title ?? title ?? DEFAULT_SEO.title
  const seoDescription = seo?.description ?? DEFAULT_SEO.description
  const seoImage = seo?.image ?? DEFAULT_SEO.image
  const seoUrl = seo?.url
  const seoType = seo?.type ?? "website"
  const noindex = seo?.noindex

  const jsonLdItems = jsonLd
    ? Array.isArray(jsonLd)
      ? jsonLd
      : [jsonLd]
    : null

  return (
    <>
      <Head title={seoTitle}>
        <meta
          head-key="description"
          name="description"
          content={seoDescription}
        />
        {seoUrl ? (
          <link head-key="canonical" rel="canonical" href={seoUrl} />
        ) : null}
        {noindex ? (
          <meta head-key="robots" name="robots" content="noindex, nofollow" />
        ) : null}

        {/* Open Graph */}
        <meta head-key="og:title" property="og:title" content={seoTitle} />
        <meta
          head-key="og:description"
          property="og:description"
          content={seoDescription}
        />
        <meta head-key="og:image" property="og:image" content={seoImage} />
        {seoUrl ? (
          <meta head-key="og:url" property="og:url" content={seoUrl} />
        ) : null}
        <meta head-key="og:type" property="og:type" content={seoType} />
        <meta
          head-key="og:site_name"
          property="og:site_name"
          content="ContextQMD"
        />

        {/* Twitter Card */}
        <meta
          head-key="twitter:card"
          name="twitter:card"
          content="summary_large_image"
        />
        <meta
          head-key="twitter:title"
          name="twitter:title"
          content={seoTitle}
        />
        <meta
          head-key="twitter:description"
          name="twitter:description"
          content={seoDescription}
        />
        <meta
          head-key="twitter:image"
          name="twitter:image"
          content={seoImage}
        />

        {jsonLdItems
          ? jsonLdItems.map((item, i) => (
              <script
                key={`ld-${i}`}
                head-key={`json-ld-${i}`}
                type="application/ld+json"
              >
                {JSON.stringify(item)}
              </script>
            ))
          : null}
      </Head>
      <div className="min-h-dvh bg-background text-foreground">
        {showHeader ? <SiteHeader /> : null}
        {children}
        {showFooter ? <SiteFooter /> : null}
      </div>
    </>
  )
}
