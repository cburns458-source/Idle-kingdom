import { withAssetVersion } from './cacheBust'

export function critterAssetPath(internalKey: string): string {
  return withAssetVersion(`/assets/critters/crt_${internalKey}.webp`)
}
