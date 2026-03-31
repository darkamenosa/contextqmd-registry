import type { ReactNode } from "react"
import type { ResolvedComponent } from "@inertiajs/react"

import PersistentLayout from "@/layouts/persistent-layout"

type PageModule = { default: ResolvedComponent }

// Eager-load public pages, lazy-load admin and app pages.
const publicPages = import.meta.glob<PageModule>(
  ["../pages/**/*.tsx", "!../pages/admin/**/*.tsx", "!../pages/app/**/*.tsx"],
  { eager: true }
)
const adminPages = import.meta.glob<PageModule>("../pages/admin/**/*.tsx")
const appPages = import.meta.glob<PageModule>("../pages/app/**/*.tsx")

const applyPersistentLayout = (pageComponent: ResolvedComponent) => {
  pageComponent.layout ||= (pageNode: ReactNode) => (
    <PersistentLayout>{pageNode}</PersistentLayout>
  )
  return pageComponent
}

export const resolvePage = (
  name: string
): ResolvedComponent | Promise<ResolvedComponent> => {
  const pagePath = `../pages/${name}.tsx`

  if (name.startsWith("admin/")) {
    const loadPage = adminPages[pagePath]
    if (!loadPage) {
      const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
      console.error(error.message)
      return Promise.reject(error)
    }
    return loadPage().then((pageModule) =>
      applyPersistentLayout(pageModule.default)
    )
  }

  if (name.startsWith("app/")) {
    const loadPage = appPages[pagePath]
    if (!loadPage) {
      const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
      console.error(error.message)
      return Promise.reject(error)
    }
    return loadPage().then((pageModule) =>
      applyPersistentLayout(pageModule.default)
    )
  }

  const page = publicPages[pagePath]
  if (!page) {
    const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
    console.error(error.message)
    throw error
  }
  return applyPersistentLayout(page.default)
}

export const titleTemplate = (title: string) =>
  title && title !== "ContextQMD" && !title.includes("ContextQMD")
    ? `${title} — ContextQMD`
    : title || "ContextQMD"

export const inertiaDefaults = {
  form: {
    forceIndicesArrayFormatInFormData: false,
  },
} as const
