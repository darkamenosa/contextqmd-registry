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
          if (id.indexOf('node_modules/three') !== -1 || id.indexOf('@react-three') !== -1) {
            return 'vendor-3d'
          }
          if (id.indexOf('chart.js') !== -1 || id.indexOf('react-chartjs-2') !== -1) {
            return 'vendor-charts'
          }
          if (id.indexOf('d3-geo') !== -1 || id.indexOf('topojson-client') !== -1) {
            return 'vendor-maps'
          }
          if (id.indexOf('react-day-picker') !== -1) {
            return 'vendor-date-picker'
          }
        },
      },
    },
  },
})
