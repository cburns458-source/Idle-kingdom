import type { LocationRow } from '../data/types'

/** Map IDs that must not show this location, from Hidden On Map IDs. */
export function hiddenMapIdsFor(location: LocationRow): string[] {
  const raw = location['Hidden On Map IDs']
  if (typeof raw !== 'string' || !raw.trim()) return []
  return raw
    .split(';')
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
}

export function locationHiddenOnMap(location: LocationRow, mapId: string): boolean {
  return hiddenMapIdsFor(location).includes(mapId)
}

/** Gateway nodes use Map Node Name on a child sub-map. */
export function mapNodeLabel(location: LocationRow, browseMapId: string): string {
  const mapId = location['Map ID']
  const nodeName = location['Map Node Name']
  if (nodeName && mapId && browseMapId !== mapId) return nodeName
  return location['Display Name']
}
