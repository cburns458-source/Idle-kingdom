import 'generated/rows.dart';
import 'validate.dart';

/// Items with a non-quest source the data cannot show, such as a grant written
/// in code (the Tanner, Botany notes, starter cosmetics). Listing one here stops
/// [validateTradeability] calling it quest-only.
const Set<String> tradeabilityCodeSourcedItemIds = <String>{};

final RegExp _itemIdPattern = RegExp(r'^ITEM-\d+$');
final RegExp _grantItemPattern = RegExp(r'grant_item:(ITEM-\d+)');

const String _questItemDropPurpose = 'Quest item drop';
const String _questCosmeticTag = 'quest';

extension ItemTradeability on ItemRow {
  /// False keeps the item off the Bazaar. Missing, null, or blank means true.
  ///
  /// Read from [raw] rather than the generated accessor so a blank cell from
  /// the sheet reads as the default instead of throwing.
  bool get isTradeable => raw['Tradeable'] != false;
}

/// Where each item can come from, split into quest rewards and everything else.
class ItemSources {
  ItemSources._(this.quest, this.other);

  /// Quest rewards: `Quests."Reward Item ID"`, reward tables with Purpose
  /// "Quest item drop", and cosmetics tagged `quest`.
  final Map<String, Set<String>> quest;

  /// Shops, drops, gathering, crafting, projects, starting items, dialogue
  /// grants, achievements, and non-quest cosmetic tags.
  final Map<String, Set<String>> other;

  bool isQuestOnly(String itemId) =>
      (quest[itemId]?.isNotEmpty ?? false) && (other[itemId]?.isEmpty ?? true);

  bool hasOtherSource(String itemId) => other[itemId]?.isNotEmpty ?? false;
}

/// Scans the data tables for every way an item can be obtained.
///
/// Retired rows are skipped. Sources that live only in code or Notes are not
/// visible here; see [tradeabilityCodeSourcedItemIds].
ItemSources scanItemSources(GameDatabase db) {
  final quest = <String, Set<String>>{};
  final other = <String, Set<String>>{};
  void add(Map<String, Set<String>> into, Object? itemId, String source) {
    if (itemId is! String || !_itemIdPattern.hasMatch(itemId)) return;
    into.putIfAbsent(itemId, () => <String>{}).add(source);
  }

  Iterable<Map<String, Object?>> live(String table) =>
      db.rowsOf(table).where((row) => row['Status'] != 'Retired');

  for (final shop in live('Shops')) {
    for (final entry in shop.entries) {
      final key = entry.key;
      if (key.startsWith('Entry ') && key.endsWith(' Item ID')) {
        add(other, entry.value, 'shop ${shop['Shop ID']}');
      }
    }
  }
  for (final reward in live('RewardEntries')) {
    final into = reward['Purpose'] == _questItemDropPurpose ? quest : other;
    add(into, reward['Reward ID / Value'], 'reward ${reward['Reward Table ID']}');
  }
  for (final recipe in live('Recipes')) {
    add(other, recipe['Output Item ID'], 'recipe ${recipe['Recipe ID']}');
  }
  for (final project in live('Projects')) {
    add(other, project['Output Item / Target ID'], 'project ${project['Project ID']}');
  }
  for (final action in live('Actions')) {
    if (action['Target Type'] == 'Item') {
      add(other, action['Target ID'], 'action ${action['Action ID']}');
    }
  }
  for (final starter in live('RaceStartingItems')) {
    add(other, starter['Item ID'], 'starting item ${starter['Race Starting Item ID']}');
  }
  for (final choice in live('DialogueChoices')) {
    final action = choice['Action'];
    if (action is! String) continue;
    for (final match in _grantItemPattern.allMatches(action)) {
      add(other, match.group(1), 'dialogue ${choice['Choice ID']}');
    }
  }
  for (final achievement in live('Achievements')) {
    add(other, achievement['Reward'], 'achievement ${achievement['Achievement ID']}');
  }
  for (final cosmetic in live('Cosmetics')) {
    final tags = cosmetic['Acquisition Tags'];
    if (tags is! String) continue;
    for (final tag in tags.split(RegExp('[;,]')).map((tag) => tag.trim())) {
      if (tag.isEmpty) continue;
      add(tag == _questCosmeticTag ? quest : other, cosmetic['Item ID'], 'cosmetic $tag');
    }
  }
  for (final row in live('Quests')) {
    add(quest, row['Reward Item ID'], 'quest ${row['Quest ID']}');
  }
  return ItemSources._(quest, other);
}

/// Checks the Items `Tradeable` column against where each item comes from.
///
/// Errors when the cell is not a boolean (blank is allowed and means true) and
/// when a quest-only item is tradeable. Warns when an untradeable item has a
/// non-quest source, since it may need re-classifying.
///
/// Kept apart from [validateDatabase] so the TypeScript parity fixtures for that
/// function stay as they are; the ik_content tests run it on the real database.
List<ValidationIssue> validateTradeability(
  GameDatabase db, {
  Set<String> codeSourcedItemIds = tradeabilityCodeSourcedItemIds,
}) {
  final issues = <ValidationIssue>[];
  final sources = scanItemSources(db);
  for (final item in db.items) {
    final itemId = item.itemId;
    final cell = item.raw['Tradeable'];
    if (cell != null && cell is! bool && cell != '') {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Items',
          id: itemId,
          message: 'Tradeable must be true, false, or blank',
        ),
      );
      continue;
    }
    final tradeable = item.isTradeable;
    if (tradeable && sources.isQuestOnly(itemId) && !codeSourcedItemIds.contains(itemId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Items',
          id: itemId,
          message:
              'Quest-only item must set Tradeable false '
              '(${sources.quest[itemId]!.join(', ')})',
        ),
      );
    }
    if (!tradeable && sources.hasOtherSource(itemId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.warning,
          table: 'Items',
          id: itemId,
          message:
              'Untradeable item has a non-quest source '
              '(${sources.other[itemId]!.join(', ')})',
        ),
      );
    }
  }
  return issues;
}
