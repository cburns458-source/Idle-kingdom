/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    allowedHosts: [
      '9905a33ae163693b5fdd-pod-q43tqsu3czh65n2412nivrhhsi-5173.us6p.cursorvm.com',
      '9905a33ae163693b5fdd-pod-q43tqsu3czh65n24l2nivrhhsi-5173.us6p.cursorvm.com',
      '9905a33ae163693b5fdd-pod-fl3uvplwdben5orjx326gplsvu-5173.us6p.cursorvm.com',
    ],
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
})
