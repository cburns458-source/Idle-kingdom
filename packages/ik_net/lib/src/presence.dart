import 'package:ik_rules/ik_rules.dart';

import 'types.dart';

/// The skill a presence row advertises.
///
/// Combat is the one every character has, so it is the default; a save without
/// it falls back to whatever skill comes first.
PresenceInput presenceFromSave(PlayerSave save) {
  final combat = save.skills.where((skill) => skill.skillId == 'SKL-0001').firstOrNull;
  final fallback = save.skills.isEmpty ? null : save.skills.first;
  final skill = combat ?? fallback;
  return PresenceInput(
    appearance: save.appearance,
    locationId: save.currentLocationId,
    currentActivityId: save.currentActivityId,
    skillId: skill?.skillId,
    skillLevel: skill?.level,
    outfitCosmeticId: save.cosmetics.equipped[outfitCosmeticSlotId],
    mountCosmeticId: save.cosmetics.equipped[petCosmeticSlotId],
  );
}

/// Stable Local-chat location key while anywhere on the Citadel sub-map.
String citadelChatLocationIdOf() => citadelChatLocationId;

String citadelLocationId() => citadelLocationIdValue;

String citadelLocalChannelKey() =>
    chatChannelKey(const ChatChannel.local(citadelChatLocationId));

/// What the Citadel tab shows above its visitor list.
class CitadelHubSummary {
  const CitadelHubSummary({
    required this.locationId,
    required this.chatChannel,
    required this.visitorCount,
    required this.note,
  });

  final String locationId;
  final String chatChannel;
  final int visitorCount;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
    'locationId': locationId,
    'chatChannel': chatChannel,
    'visitorCount': visitorCount,
    'note': note,
  };
}

CitadelHubSummary citadelHubSummary(int visitorCount) => CitadelHubSummary(
  locationId: citadelLocationIdValue,
  chatChannel: citadelLocalChannelKey(),
  visitorCount: visitorCount,
  note: 'Shared Citadel hub. Local chat is one room across every Citadel district.',
);
