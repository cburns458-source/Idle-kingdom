import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

String _smithingKind(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\bshield\b').hasMatch(n)) return 'shield';
  if (RegExp(r'\b(helmet|chestplate|platelegs|boots|gloves)\b').hasMatch(n)) return 'armor';
  if (RegExp(r'\b(pickaxe|hatchet|fishing rod|harpoon|axe)\b').hasMatch(n) &&
      !n.contains('battleaxe')) {
    return 'tool';
  }
  if (RegExp(r'\b(sword|dagger|warhammer|battleaxe|spear)\b').hasMatch(n)) return 'weapon';
  return 'other';
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('smithing tools and weapons drop leather straps; armor and shields keep them', () {
    final smithing = db.projects.where((row) => row.raw['Skill ID'] == 'SKL-0011');
    expect(smithing.any((row) => _smithingKind(row.displayName) == 'other'), isFalse);

    for (final project in smithing) {
      final kind = _smithingKind(project.displayName);
      final usesStraps = projectInputs(project).any((input) => input.itemId == 'ITEM-0084');
      if (kind == 'tool' || kind == 'weapon') {
        expect(usesStraps, isFalse, reason: project.displayName);
      } else {
        expect(usesStraps, isTrue, reason: project.displayName);
      }
    }
  });

  test('armor and shield smithing XP is 10% higher', () {
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0007').raw['XP Reward'], 2560);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0003').raw['XP Reward'], 4125);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0020').raw['XP Reward'], 2723);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0013').raw['XP Reward'], 7260);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0025').raw['XP Reward'], 8620);
    expect(db.projects.firstWhere((row) => row.projectId == 'PRJ-0113').raw['XP Reward'], 35822);
  });
}
