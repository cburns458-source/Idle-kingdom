import { withAssetVersion } from './cacheBust'

/** Skill icons keyed by Skills.Internal Key. */

export function skillAssetPath(internalKey: string): string {
  const key = internalKey.trim().toLowerCase().replaceAll(' ', '_')
  return withAssetVersion(`/assets/icons/skills/skl_${key}.png`)
}
