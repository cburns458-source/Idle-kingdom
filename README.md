# Idle Kingdom

A small idle / incremental kingdom-building game built with **React + TypeScript + Vite**.

Collect taxes by hand, then buy buildings (farms, mines, castles, …) that
generate gold automatically. Progress is saved to `localStorage`.

## Tech stack

- [Vite](https://vitejs.dev/) — dev server & build
- [React 18](https://react.dev/) + TypeScript
- [Vitest](https://vitest.dev/) + Testing Library — unit & component tests
- [ESLint](https://eslint.org/) — linting

## Getting started

Requires Node.js 20+ (Node 22 recommended) and npm.

```bash
npm install       # install dependencies
npm run dev       # start the dev server at http://localhost:5173
```

## Available scripts

| Command          | Description                                  |
| ---------------- | -------------------------------------------- |
| `npm run dev`    | Start the Vite dev server (port 5173).       |
| `npm run build`  | Type-check and build for production.          |
| `npm run preview`| Preview the production build (port 4173).     |
| `npm run lint`   | Run ESLint over the project.                  |
| `npm test`       | Run the unit & component test suite once.     |
| `npm run test:watch` | Run tests in watch mode.                  |

## Project structure

```
src/
  game/        Pure, framework-agnostic game logic (+ unit tests)
    buildings.ts   Building definitions
    engine.ts      State transitions: buy, click, tick, costs
    format.ts      Number formatting helpers
    types.ts       Shared types
  hooks/
    useGame.ts   React hook wiring the engine to a game loop + persistence
  App.tsx        UI
  main.tsx       Entry point
```

The game logic in `src/game` is kept as pure functions so it can be tested
without a DOM.
