import ReactDOMServer from "react-dom/server"
import { createInertiaApp } from "@inertiajs/react"
import createServer from "@inertiajs/react/server"

import { inertiaDefaults, resolvePage, titleTemplate } from "@/lib/inertia"

createServer((page) =>
  createInertiaApp({
    page,
    render: ReactDOMServer.renderToString,
    title: titleTemplate,
    resolve: resolvePage,
    setup: ({ App, props }) => <App {...props} />,
    defaults: inertiaDefaults,
  })
)
