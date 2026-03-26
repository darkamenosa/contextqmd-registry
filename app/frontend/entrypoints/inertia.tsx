import { StrictMode } from "react"
import { createRoot, hydrateRoot } from "react-dom/client"
import { createInertiaApp } from "@inertiajs/react"

import { inertiaDefaults, resolvePage, titleTemplate } from "@/lib/inertia"

void createInertiaApp({
  title: titleTemplate,
  progress: { color: "#171717" },
  resolve: resolvePage,
  setup({ el, App, props }) {
    if (el) {
      const app = (
        <StrictMode>
          <App {...props} />
        </StrictMode>
      )

      if (el.hasAttribute("data-server-rendered")) {
        hydrateRoot(el, app)
      } else {
        createRoot(el).render(app)
      }
    } else {
      console.error("Missing root element.")
    }
  },
  defaults: inertiaDefaults,
}).catch((error) => {
  if (document.getElementById("app")) {
    throw error
  } else {
    console.error(
      "Missing root element.\n\n" +
        "If you see this error, it probably means you loaded Inertia.js on non-Inertia pages.\n" +
        'Consider moving <%= vite_typescript_tag "inertia.tsx" %> to the Inertia-specific layout instead.'
    )
  }
})
