import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { isRemoteMultiplayerConfigured, supabaseConfig } from './config'
import { LocalMultiplayerBackend } from './localBackend'

let localBackend: LocalMultiplayerBackend | null = null
let supabase: SupabaseClient | null | undefined

export function getLocalBackend(): LocalMultiplayerBackend {
  if (!localBackend) localBackend = new LocalMultiplayerBackend()
  return localBackend
}

/** Prefer local demo backend unless Supabase env is configured. */
export function multiplayerMode(): 'local' | 'supabase' {
  return isRemoteMultiplayerConfigured() ? 'supabase' : 'local'
}

export function getSupabaseClient(): SupabaseClient | null {
  if (supabase !== undefined) return supabase
  const config = supabaseConfig()
  if (!config) {
    supabase = null
    return null
  }
  supabase = createClient(config.url, config.anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  })
  return supabase
}

export function resetMultiplayerClientsForTests(): void {
  localBackend = null
  supabase = undefined
}
