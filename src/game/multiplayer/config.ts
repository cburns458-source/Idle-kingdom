/** Supabase project credentials (optional). When missing, local demo backend is used. */
export function supabaseConfig(): { url: string; anonKey: string } | null {
  const url = String(import.meta.env.VITE_SUPABASE_URL ?? '').trim()
  const anonKey = String(import.meta.env.VITE_SUPABASE_ANON_KEY ?? '').trim()
  if (!url || !anonKey) return null
  return { url, anonKey }
}

export function isRemoteMultiplayerConfigured(): boolean {
  return supabaseConfig() != null
}

/** Chat cooldown seconds by channel kind (server-enforced when remote). */
export const CHAT_COOLDOWN_SECONDS = {
  global: 30,
  local: 10,
  guild: 5,
  dm: 2,
} as const

/** Heartbeat window: a presence row newer than this is Online. */
export const PRESENCE_TTL_SECONDS = 120

/** How long a closed-client presence stays visible as Away on Nearby. */
export const PRESENCE_AWAY_TTL_SECONDS = 24 * 60 * 60
