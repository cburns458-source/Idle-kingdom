import { describe, expect, it } from 'vitest'
import { playerArtStem, playerPortraitAssetPath } from './playerAssets'

describe('race and gender player assets', () => {
  it('maps each gender presentation to feminine or masculine plates', () => {
    expect(playerArtStem('RACE-0001', 'APR-0017')).toBe('player_human_feminine')
    expect(playerArtStem('RACE-0001', 'APR-0019')).toBe('player_human_feminine')
    expect(playerArtStem('RACE-0001', 'APR-0018')).toBe('player_human_masculine')
  })

  it('maps each launch race to its own stem', () => {
    expect(playerArtStem('RACE-0006', 'APR-0018')).toBe('player_dwarf_masculine')
    expect(playerArtStem('RACE-0007', 'APR-0017')).toBe('player_halfling_feminine')
  })

  it('falls back to human for unknown race ids', () => {
    expect(playerArtStem('RACE-MISSING', 'APR-0018')).toBe('player_human_masculine')
  })

  it('reads race and gender presentation from a PlayerSave value', () => {
    expect(
      playerPortraitAssetPath({
        raceId: 'RACE-0004',
        appearance: {
          skinTone: 'APR-0001',
          hairstyle: 'APR-0004',
          hairColor: 'APR-0007',
          expression: 'APR-0011',
          beard: 'APR-0014',
          genderPresentation: 'APR-0018',
        },
      } as const),
    ).toContain('player_orc_masculine')
  })
})
