import inertia from '@inertiajs/vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    inertia({
      ssr: 'ssr/ssr.tsx',
    }),
    react(),
    tailwindcss(),
  ],
  build: {
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (
            id.includes("/node_modules/chart.js/") ||
            id.includes("/node_modules/react-chartjs-2/")
          ) {
            return 'vendor-charts'
          }
          if (
            id.includes("/node_modules/d3-geo/") ||
            id.includes("/node_modules/topojson-client/")
          ) {
            return 'vendor-maps'
          }
        },
      },
    },
  },
})
