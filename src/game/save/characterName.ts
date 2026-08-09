import { CHARACTER_NAME_MAX_LENGTH } from './types'

export function normalizeCharacterName(raw: string): string | null {
  const trimmed = raw.trim().replace(/\s+/g, ' ')
  if (!trimmed) return null
  return trimmed.slice(0, CHARACTER_NAME_MAX_LENGTH)
}

export function isValidCharacterName(raw: string): boolean {
  return normalizeCharacterName(raw) != null
}
