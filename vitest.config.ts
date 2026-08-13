import { defineConfig } from 'vitest/config'

// What is left under `src/` is the TypeScript rules the Dart port is recorded
// from, plus the harness that records them; there is no app to serve any more.
// The environment stays jsdom because the local multiplayer backend keeps its
// document in `localStorage`.
export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
  },
})
