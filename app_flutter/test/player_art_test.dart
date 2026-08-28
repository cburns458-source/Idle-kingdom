import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:ik_rules/ik_rules.dart';

void main() {
  test('playerAssetPath picks race and gender presentation', () {
    const look = PlayerAppearance(
      skinTone: 'APR-0001',
      hairstyle: 'APR-0004',
      hairColor: 'APR-0007',
      expression: 'APR-0011',
      beard: 'APR-0014',
      genderPresentation: 'APR-0018',
    );
    expect(
      playerAssetPath(look, raceId: 'RACE-0006'),
      'content/assets/player/player_dwarf_masculine.png',
    );
    expect(
      playerAssetPath(look.copyWith(genderPresentation: 'APR-0019'), raceId: 'RACE-0006'),
      'content/assets/player/player_dwarf_feminine.png',
    );
    expect(
      playerAssetPath(look, raceId: 'RACE-MISSING'),
      'content/assets/player/player_human_masculine.png',
    );
  });
}
