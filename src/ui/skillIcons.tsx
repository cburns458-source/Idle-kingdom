import { skillAssetPath } from '../game/assets/skillAssets'

/** Pixel skill icon keyed by Skills.Internal Key. */
export function SkillIcon({ internalKey, title }: { internalKey: string; title: string }) {
  return (
    <span
      className="skill-icon skill-icon-pixel"
      style={{ backgroundImage: `url(${skillAssetPath(internalKey)})` }}
      title={title}
      aria-hidden
    />
  )
}
