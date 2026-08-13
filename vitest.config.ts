import { defineConfig } from 'vitest/config'

// What is left under `src/` is the TypeScript rules the Dart port is recorded
// from, plus the harness that records them; there is no app to serve any more.
// Only the local multiplayer backend needs a browser, and it asks for one
// itself, so the rest of the suite runs without paying for jsdom.
export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
  },
})
