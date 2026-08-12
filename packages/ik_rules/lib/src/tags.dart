/// Splits a `;`-separated capability or effect string into normalized tags.
///
/// Four TypeScript modules declare this helper privately and identically
/// (`autoEquip`, `spells`, `enchantments`, `potions/effects`); Dart keeps one
/// copy so a future change cannot drift between them.
List<String> capabilityTags(Object? effects) {
  if (effects is! String) return const <String>[];
  return effects
      .split(';')
      .map((part) => part.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}
