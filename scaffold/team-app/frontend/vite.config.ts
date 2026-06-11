import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // Base path is injected at build time via VITE_BASE_PATH env var (set in Dockerfile ARG)
  base: process.env.VITE_BASE_PATH ?? '/',
  server: {
    proxy: {
      // In local dev, proxy API calls to the backend
      '/api': { target: 'http://localhost:8000', rewrite: path => path.replace(/^\/api/, '') },
    },
  },
})
