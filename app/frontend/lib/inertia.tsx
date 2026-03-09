import type { ReactNode } from "react"
import type { ResolvedComponent } from "@inertiajs/react"

import PersistentLayout from "@/layouts/persistent-layout"

type PageModule = { default: ResolvedComponent }

// Eager-load public pages, lazy-load admin and app pages
const publicPages = import.meta.glob<PageModule>(
  ["../pages/**/*.tsx", "!../pages/admin/**/*.tsx", "!../pages/app/**/*.tsx"],
  { eager: true }
)
const adminPages = import.meta.glob<PageModule>("../pages/admin/**/*.tsx")
const appPages = import.meta.glob<PageModule>("../pages/app/**/*.tsx")

const applyPersistentLayout = (pageModule: PageModule) => {
  pageModule.default.layout ||= (pageNode: ReactNode) => (
    <PersistentLayout>{pageNode}</PersistentLayout>
  )
  return pageModule
}

export const resolvePage = (name: string) => {
  const pagePath = `../pages/${name}.tsx`

  if (name.startsWith("admin/")) {
    const loadPage = adminPages[pagePath]
    if (!loadPage) {
      const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
      console.error(error.message)
      return Promise.reject(error)
    }
    return loadPage().then(applyPersistentLayout)
  }

  if (name.startsWith("app/")) {
    const loadPage = appPages[pagePath]
    if (!loadPage) {
      const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
      console.error(error.message)
      return Promise.reject(error)
    }
    return loadPage().then(applyPersistentLayout)
  }

  const page = publicPages[pagePath]
  if (!page) {
    const error = new Error(`Missing Inertia page component: '${name}.tsx'`)
    console.error(error.message)
    throw error
  }
  return applyPersistentLayout(page)
}

export const titleTemplate = (title: string) =>
  title ? `${title} - ContextQMD` : "ContextQMD"

export const inertiaDefaults = {
  form: {
    forceIndicesArrayFormatInFormData: false,
  },
  future: {
    useScriptElementForInitialPage: true,
    useDataInertiaHeadAttribute: true,
    useDialogForErrorModal: true,
    preserveEqualProps: true,
  },
} as const
