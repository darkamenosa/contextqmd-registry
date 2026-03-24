import ReactDOMServer from "react-dom/server"
import { createInertiaApp } from "@inertiajs/react"
import createServer from "@inertiajs/react/server"

import { inertiaDefaults, resolvePage, titleTemplate } from "@/lib/inertia"

createServer((page) =>
  createInertiaApp({
    page,
    render: ReactDOMServer.renderToString,
    title: titleTemplate,
    // Keep SSR and CSR on the same page-resolution strategy:
    // public pages eager, admin/app pages lazy.
    resolve: resolvePage,
    setup: ({ App, props }) => <App {...props} />,
    defaults: inertiaDefaults,
  })
)
