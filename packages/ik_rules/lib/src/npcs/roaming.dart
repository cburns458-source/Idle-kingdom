import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';

/// Mountains, Deep Mines.
const List<String> masterDwarfRoute = <String>['LOC-0006', 'LOC-0011'];

/// Meadow, Ancient Forest, Gathering Outskirts, Mountains.
const List<String> quillRoute = <String>['LOC-0009', 'LOC-0018', 'LOC-0031', 'LOC-0006'];

const String _masterDwarfId = 'NPC-0003';
const String _quillId = 'NPC-0002';
const String dwarvenMiningMerchantId = 'NPC-0008';

const Map<String, List<String>> roamingRoutes = <String, List<String>>{
  _masterDwarfId: masterDwarfRoute,
  _quillId: quillRoute,
};

const int _uint32Mask = 0xFFFFFFFF;

/// UTC calendar day `YYYY-MM-DD` for [nowMs].
String roamingDayKey(num nowMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(nowMs.toInt(), isUtc: true);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

int _hashString(String input) {
  var hash = 2166136261;
  for (var i = 0; i < input.length; i += 1) {
    hash ^= input.codeUnitAt(i);
    hash = jsImul(hash, 16777619);
  }
  return hash & _uint32Mask;
}

/// One shared stop for the day, independent of yesterday's roll.
String roamingLocationFor(String npcId, List<String> route, num nowMs) {
  if (route.isEmpty) return '';
  final seed = _hashString('$npcId:${roamingDayKey(nowMs)}');
  return route[seed % route.length];
}

String npcLocationAt(NpcRow npc, num nowMs) {
  final npcId = npc.raw['NPC ID'];
  if (npcId is String) {
    final route = roamingRoutes[npcId];
    if (route != null) return roamingLocationFor(npcId, route, nowMs);
  }
  final locationId = npc.raw['Location ID'];
  return locationId is String ? locationId : '';
}

String masterDwarfLocationId(num nowMs) {
  return roamingLocationFor(_masterDwarfId, masterDwarfRoute, nowMs);
}

String quillLocationId(num nowMs) {
  return roamingLocationFor(_quillId, quillRoute, nowMs);
}

String locationDisplayName(GameDatabase db, String locationId) {
  final displayName = db.locations
      .firstWhereOrNull((row) => row.raw['Location ID'] == locationId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : locationId;
}
