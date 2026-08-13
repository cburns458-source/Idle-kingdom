import { GUILD_EMBLEM_SYMBOLS, type GuildEmblemSymbol } from './types'

/**
 * The mark on a guild banner, as a path in a 24×24 box.
 *
 * Solid single-path shapes rather than emoji, so a banner reads the same at
 * badge size on every platform, and both clients draw the same outline from the
 * same string.
 */
export const GUILD_EMBLEM_SYMBOL_PATHS: Record<GuildEmblemSymbol, string> = {
  sword:
    'M14.5 2.2 21.8 9.5l-1.9 1.9-2.2-2.2-7.4 7.4 1.5 1.5-1.4 1.4-1.5-1.5-2.1 2.1H4.5v-2.3l2.1-2.1-1.5-1.5 1.4-1.4 1.5 1.5 7.4-7.4-2.2-2.2z',
  shield: 'M12 2.2 19.5 5v5.4c0 5.1-3.4 9.1-7.5 10.4C8 19.5 4.5 15.5 4.5 10.4V5z',
  tree:
    'M12 2.5c-2.6 0-5 2.1-5.4 5H5.2C3.4 7.5 2 9.2 2 11.3 2 13.5 3.7 15.3 5.8 15.3H7v2.2h3.2V21h3.6v-3.5H17v-2.2h1.1c2.2 0 4-1.8 4-4.1 0-2.1-1.5-3.8-3.4-4-0.2-3.2-2.7-5.7-5.7-5.7z',
  dragon:
    'M4 16.5c0-4.2 2.8-7.4 6.2-8.6L8.5 4.2 12 6.1l2.1-2.4L15.8 7c3.1 1.4 5.2 4.4 5.2 7.8 0 1.4-.4 2.7-1.1 3.8H19l1.5 2.7h-2.4L16.8 18H7.2l-1.3 2.5H3.5L5 17.8H4.8C4.3 17.1 4 16.8 4 16.5zm5.2-2.2c.7 0 1.2-.6 1.2-1.3S9.9 11.7 9.2 11.7 8 12.3 8 13s.5 1.3 1.2 1.3zm5.6 0c.7 0 1.2-.6 1.2-1.3s-.5-1.3-1.2-1.3-1.2.6-1.2 1.3.5 1.3 1.2 1.3z',
  star: 'm12 2.4 2.7 5.5 6.1.9-4.4 4.3 1 6.1L12 16.3 6.6 19.2l1-6.1L3.2 8.8l6.1-.9z',
  flame:
    'M12 2.2s3.4 3.1 3.4 6.4c0 1.2-.4 2.2-1.1 3 .8-.3 1.4-1 1.8-1.9.3 3.2-1.5 6.4-4.1 7.8-2.6-1.4-4.4-4.6-4.1-7.8.4.9 1 1.6 1.8 1.9-.7-.8-1.1-1.8-1.1-3C8.6 5.3 12 2.2 12 2.2z',
  moon:
    'M14.2 3.1A8.9 8.9 0 0 0 12 3C7 3 3 7 3 12s4 9 9 9 9-4 9-9c0-.7-.1-1.4-.3-2.1A6.7 6.7 0 0 1 14.2 3.1z',
  eagle: 'M12 4.2 14.2 8H19l-3.4 3.1L17.2 16 12 13.2 6.8 16l1.6-4.9L5 8h4.8zm0 10.2 1.4 4.4H10.6z',
  castle: 'M4 20V8l2-1V4h2v3h2V4h2v3h2V4h2v3l2 1v12h-5v-5H9v5zm7-9h2v2h-2z',
  gem:
    'M7.2 3.5h9.6L21 8.2 12 20.5 3 8.2zm1.3 1.8L6.2 8h2.7zm3.2 0v2.7h2.6V5.3zm4.8 0-1.6 2.7H17.8zM7.1 9.8l3.4 7.2L5.2 9.8zm5.6 7.2 3.4-7.2H9.3z',
  wolf:
    'm4.5 9 2.2-3.2L9 7.5 12 4.8l3 2.7 2.3-1.7L19.5 9l-1.2 2.1c.4 1 .7 2.1.7 3.2 0 3.4-2.7 5.7-7 5.7s-7-2.3-7-5.7c0-1.1.3-2.2.7-3.2zm4.8 3.2c.7 0 1.2.5 1.2 1.2S10 14.6 9.3 14.6s-1.2-.5-1.2-1.2.5-1.2 1.2-1.2zm5.4 0c.7 0 1.2.5 1.2 1.2s-.5 1.2-1.2 1.2-1.2-.5-1.2-1.2.5-1.2 1.2-1.2z',
  lion:
    'M12 3.2c3.8 0 6.8 2.4 6.8 6.1 0 1.3-.4 2.5-1.1 3.4l1.8 4.1h-2.5l-.9-2.1c-.9.5-2 1-3.1 1.2V19h-2v-3.1c-1.1-.2-2.2-.7-3.1-1.2l-.9 2.1H4.5l1.8-4.1C5.6 11.8 5.2 10.6 5.2 9.3 5.2 5.6 8.2 3.2 12 3.2zm-2.3 5.4a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4zm4.6 0a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4z',
}

/** The mark for [symbol], falling back to the first one for anything unknown. */
export function guildEmblemSymbolPath(symbol: string): string {
  const known = (GUILD_EMBLEM_SYMBOLS as readonly string[]).includes(symbol)
    ? (symbol as GuildEmblemSymbol)
    : GUILD_EMBLEM_SYMBOLS[0]
  return GUILD_EMBLEM_SYMBOL_PATHS[known]
}
