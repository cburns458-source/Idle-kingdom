import type { SaveStorage } from '../game/save/saveStore'

export function createMemoryStorage(initial: Record<string, string> = {}): SaveStorage {
  const map = new Map<string, string>(Object.entries(initial))
  return {
    getItem(key) {
      return map.has(key) ? map.get(key)! : null
    },
    setItem(key, value) {
      map.set(key, value)
    },
    removeItem(key) {
      map.delete(key)
    },
  }
}
