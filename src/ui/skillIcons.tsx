import type { ReactNode } from 'react'

/** Bold, readable skill glyphs keyed by Skills.Internal Key. */
export function SkillIcon({ internalKey, title }: { internalKey: string; title: string }) {
  return (
    <span className={`skill-icon skill-icon-${internalKey}`} title={title} aria-hidden>
      {ICON_BY_KEY[internalKey] ?? <DefaultGlyph />}
    </span>
  )
}

const ICON_BY_KEY: Record<string, ReactNode> = {
  combat: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M18 3 28 13l-3 3-4-4-8 8 4 4-3 3-10-10 3-3 4 4 8-8-4-4z" />
      <path fill="currentColor" d="m7 22 3 3-5 5H2v-3z" />
    </svg>
  ),
  mining: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M14 2h4l1 10h6l-8 8-8-8h6z" />
      <path fill="currentColor" d="M8 22h16v3H8zm2 5h12v3H10z" />
    </svg>
  ),
  fishing: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M4 8h2v10c0 4 3 7 8 7s8-3 8-7h-4c0 2-2 3-4 3s-4-1-4-3V8h2l4-4h-8z" />
      <path fill="currentColor" d="M20 14c4 0 8 2 10 5-2 3-6 5-10 5-2 0-4-.4-6-1 2-3 5-9 6-9z" />
    </svg>
  ),
  harvesting: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M16 4c4 0 8 4 8 9 0 3-1 5-3 7l3 8h-4l-2-6h-4l-2 6h-4l3-8c-2-2-3-4-3-7 0-5 4-9 8-9z" />
    </svg>
  ),
  hunting: (
    <svg viewBox="0 0 32 32">
      <path
        fill="currentColor"
        d="M6 16c0-6 5-10 10-10s10 4 10 10-5 10-10 10c-2 0-4-.5-5.5-1.5L4 28l2.5-5.5C5 21 6 18.5 6 16zm10-6c-3.3 0-6 2.5-6 6s2.7 6 6 6 6-2.5 6-6-2.7-6-6-6z"
      />
    </svg>
  ),
  woodcutting: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M15 2h2v18h-2z" />
      <path fill="currentColor" d="M8 8c4-4 12-4 16 0-4 2-6 5-8 8-2-3-4-6-8-8z" />
      <path fill="currentColor" d="M10 22h12l2 8H8z" />
    </svg>
  ),
  cooking: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M8 10h16v2c0 5-3 8-8 8s-8-3-8-8z" />
      <path fill="currentColor" d="M14 20h4v8h-4zM10 6h2v3h-2zm5 0h2v3h-2zm5 0h2v3h-2z" />
    </svg>
  ),
  metallurgy: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M6 6h20v4H6zm2 6h16l-2 14H10z" />
      <path fill="currentColor" d="M12 4h8v3h-8z" />
    </svg>
  ),
  crafting: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M4 18 14 8l4 4-3 3 5 5-3 3-5-5-3 3z" />
      <path fill="currentColor" d="m18 6 8 8-3 3-8-8z" />
    </svg>
  ),
  alchemy: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M13 2h6v6l5 10c1 2 0 6-4 6h-8c-4 0-5-4-4-6l5-10z" />
      <circle cx="16" cy="20" r="2" fill="#3d2a1a" />
    </svg>
  ),
  smithing: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M4 20h24v4H4zm4-8 4-4h8l4 4v6H8z" />
      <path fill="currentColor" d="M14 4h4v6h-4z" />
    </svg>
  ),
  artisanry: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M8 26c0-8 4-14 8-18 4 4 8 10 8 18z" />
      <path fill="currentColor" d="M12 24h8v4h-8z" />
    </svg>
  ),
  arcana: (
    <svg viewBox="0 0 32 32">
      <path fill="currentColor" d="M16 2 18 12l10 2-10 2-2 10-2-10L4 14l10-2z" />
    </svg>
  ),
}

function DefaultGlyph() {
  return (
    <svg viewBox="0 0 32 32">
      <circle cx="16" cy="16" r="10" fill="currentColor" />
    </svg>
  )
}
