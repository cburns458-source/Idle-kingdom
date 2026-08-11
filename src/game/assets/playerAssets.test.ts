import { describe, expect, it } from 'vitest'
import {
  genderPresentationAssetPath,
  playerPortraitAssetPath,
  PLAYER_GENDER_ANDROGYNOUS_PATH,
  PLAYER_GENDER_FEMININE_PATH,
  PLAYER_GENDER_MASCULINE_PATH,
} from './playerAssets'

describe('gender presentation player assets', () => {
  it('maps each gender presentation option to its sprite', () => {
    expect(genderPresentationAssetPath('APR-0017')).toContain(PLAYER_GENDER_FEMININE_PATH)
    expect(genderPresentationAssetPath('APR-0019')).toContain(PLAYER_GENDER_ANDROGYNOUS_PATH)
    expect(genderPresentationAssetPath('APR-0018')).toContain(PLAYER_GENDER_MASCULINE_PATH)
  })

  it('falls back to feminine for unknown presentation ids', () => {
    expect(genderPresentationAssetPath('APR-MISSING')).toContain(PLAYER_GENDER_FEMININE_PATH)
  })

  it('reads gender presentation from a PlayerAppearance value', () => {
    expect(
      playerPortraitAssetPath({
        skinTone: 'APR-0001',
        hairstyle: 'APR-0004',
        hairColor: 'APR-0007',
        expression: 'APR-0011',
        beard: 'APR-0014',
        genderPresentation: 'APR-0018',
      }),
    ).toContain(PLAYER_GENDER_MASCULINE_PATH)
  })
})
