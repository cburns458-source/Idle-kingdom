import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';

enum AppearanceCategory {
  skinTone('skinTone', 'skin_tone', 'Skin tone'),
  hairstyle('hairstyle', 'hairstyle', 'Hairstyle'),
  hairColor('hairColor', 'hair_color', 'Hair color'),
  expression('expression', 'expression', 'Expression'),
  beard('beard', 'beard', 'Beard'),
  genderPresentation('genderPresentation', 'gender_presentation', 'Gender presentation');

  const AppearanceCategory(this.key, this.dataKey, this.label);

  /// Save-schema camelCase key.
  final String key;

  /// Category value in the AppearanceOptions table.
  final String dataKey;

  final String label;
}

/// Resolves a save-schema key (as listed in `appearanceCategories`) to its category.
AppearanceCategory? appearanceCategoryByKey(String key) {
  return AppearanceCategory.values.firstWhereOrNull((category) => category.key == key);
}

String appearanceCategoryLabel(AppearanceCategory category) => category.label;

/// Options for one category, in the table's sort order.
List<AppearanceOptionRow> appearanceOptions(GameDatabase db, AppearanceCategory category) {
  final rows = db.appearanceOptions
      .where((row) => row.raw['Category'] == category.dataKey)
      .toList();
  mergeSort(
    rows,
    compare: (a, b) => jsCompareThen(
      jsNumberOrZero(a.raw['Sort Order']) - jsNumberOrZero(b.raw['Sort Order']),
      () => 0,
    ),
  );
  return rows;
}

AppearanceOptionRow? appearanceOptionById(GameDatabase db, String optionId) {
  return db.appearanceOptions.firstWhereOrNull(
    (row) => row.raw['Appearance Option ID'] == optionId,
  );
}

bool isValidAppearanceOption(GameDatabase db, AppearanceCategory category, String optionId) {
  return appearanceOptions(db, category).any((row) => row.raw['Appearance Option ID'] == optionId);
}

/// The first option per category by sort order, falling back to the baselines.
PlayerAppearance defaultAppearance(GameDatabase db) {
  String pick(AppearanceCategory category, String fallback) {
    final first = appearanceOptions(db, category).firstOrNull;
    final optionId = first?.raw['Appearance Option ID'];
    return optionId is String ? optionId : fallback;
  }

  return PlayerAppearance(
    skinTone: pick(AppearanceCategory.skinTone, defaultSkinToneId),
    hairstyle: pick(AppearanceCategory.hairstyle, defaultHairstyleId),
    hairColor: pick(AppearanceCategory.hairColor, defaultHairColorId),
    expression: pick(AppearanceCategory.expression, defaultExpressionId),
    beard: pick(AppearanceCategory.beard, defaultBeardId),
    genderPresentation: pick(AppearanceCategory.genderPresentation, defaultGenderPresentationId),
  );
}

String appearanceSelection(PlayerAppearance appearance, AppearanceCategory category) {
  return switch (category) {
    AppearanceCategory.skinTone => appearance.skinTone,
    AppearanceCategory.hairstyle => appearance.hairstyle,
    AppearanceCategory.hairColor => appearance.hairColor,
    AppearanceCategory.expression => appearance.expression,
    AppearanceCategory.beard => appearance.beard,
    AppearanceCategory.genderPresentation => appearance.genderPresentation,
  };
}

/// Re-selectable freely: appearance carries no gameplay effect. Null when the
/// option does not belong to the category.
PlayerSave? setAppearanceOption(
  GameDatabase db,
  PlayerSave save,
  AppearanceCategory category,
  String optionId,
) {
  if (!isValidAppearanceOption(db, category, optionId)) return null;
  final appearance = switch (category) {
    AppearanceCategory.skinTone => save.appearance.copyWith(skinTone: optionId),
    AppearanceCategory.hairstyle => save.appearance.copyWith(hairstyle: optionId),
    AppearanceCategory.hairColor => save.appearance.copyWith(hairColor: optionId),
    AppearanceCategory.expression => save.appearance.copyWith(expression: optionId),
    AppearanceCategory.beard => save.appearance.copyWith(beard: optionId),
    AppearanceCategory.genderPresentation => save.appearance.copyWith(genderPresentation: optionId),
  };
  return save.copyWith(appearance: appearance);
}
