/** Bump when replacing files under /public/assets so browsers fetch new art. */
export const ASSET_CACHE_VERSION = 's16-gender-presentation-sprites'

export function withAssetVersion(path: string): string {
  if (!path) return path
  const separator = path.includes('?') ? '&' : '?'
  return `${path}${separator}v=${ASSET_CACHE_VERSION}`
}
