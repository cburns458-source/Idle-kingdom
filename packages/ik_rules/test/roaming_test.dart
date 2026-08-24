import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  final day = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
  final sameDayEvening = DateTime.utc(2026, 1, 1, 23, 59, 59, 999).millisecondsSinceEpoch;
  final nextDay = DateTime.utc(2026, 1, 2).millisecondsSinceEpoch;

  test('shares one Master Dwarf stop for the UTC day', () {
    final morning = masterDwarfLocationId(day);
    expect(masterDwarfRoute, contains(morning));
    expect(masterDwarfLocationId(sameDayEvening), morning);
    expect(roamingLocationFor(masterDwarfId, masterDwarfRoute, day), morning);
    expect(roamingDayKey(day), '2026-01-01');
    expect(roamingDayKey(sameDayEvening), '2026-01-01');
    expect(roamingDayKey(nextDay), '2026-01-02');
  });

  test('rolls each UTC day independently and can stay put', () {
    final stops = <String>[
      for (var index = 0; index < 400; index += 1) masterDwarfLocationId(day + index * 86400000),
    ];
    expect(stops.toSet().length, masterDwarfRoute.length);
    expect(stops.indexed.any((entry) => entry.$1 > 0 && entry.$2 == stops[entry.$1 - 1]), isTrue);
  });

  test('lists the dwarf only at today’s stop', () {
    final today = masterDwarfLocationId(day);
    for (final locationId in masterDwarfRoute) {
      final ids = npcsAtLocation(db, locationId, day).map((npc) => npc.npcId).toList();
      if (locationId == today) {
        expect(ids, contains(masterDwarfId));
      } else {
        expect(ids, isNot(contains(masterDwarfId)));
      }
    }
  });

  test('lets the mining merchant name today’s stop', () {
    final merchant = db.npcs.firstWhere((npc) => npc.npcId == dwarvenMiningMerchantId);
    final save = createNewSave(db, day);
    final conversation = npcConversation(db, save, merchant, day);
    final place = locationDisplayName(db, masterDwarfLocationId(day));
    expect(conversation.whereabouts?.label, 'Ask where the Master Dwarf is');
    expect(conversation.whereabouts?.line, 'The Master Dwarf is at the $place today.');
  });
}
