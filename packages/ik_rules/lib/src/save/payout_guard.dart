import 'generated/save_models.dart';

num _counter(num value) => value < 0 ? 0 : value.floor();

/// True when a client save tried to invent gold, a bounty claim, or PvP wins
/// relative to the hosted copy.
bool clientSaveRaisesPayouts(PlayerSave server, PlayerSave client) {
  if (client.gold > server.gold) return true;
  final allowed = server.bountyClaimedIds.toSet();
  if (client.bountyClaimedIds.any((id) => !allowed.contains(id))) return true;
  if (_counter(client.rankedPvpWins) > _counter(server.rankedPvpWins)) return true;
  if (_counter(client.rankedPvpLosses) > _counter(server.rankedPvpLosses)) return true;
  if (client.rankedPvpDayKey == server.rankedPvpDayKey) {
    if (_counter(client.rankedPvpFightsToday) > _counter(server.rankedPvpFightsToday)) return true;
  } else if (_counter(client.rankedPvpFightsToday) > 0 && server.rankedPvpDayKey != null) {
    return true;
  }
  return false;
}

/// Keeps the client's other progress, but puts gold, bounty claims, and PvP
/// win counters back to the server's values when the client raised them.
PlayerSave replaceUnauthorizedPayouts(PlayerSave server, PlayerSave client) {
  final allowed = server.bountyClaimedIds.toSet();
  var gold = client.gold;
  if (client.gold > server.gold) gold = server.gold;
  var rankedPvpWins = client.rankedPvpWins;
  if (_counter(client.rankedPvpWins) > _counter(server.rankedPvpWins)) {
    rankedPvpWins = server.rankedPvpWins;
  }
  var rankedPvpLosses = client.rankedPvpLosses;
  if (_counter(client.rankedPvpLosses) > _counter(server.rankedPvpLosses)) {
    rankedPvpLosses = server.rankedPvpLosses;
  }
  var rankedPvpDayKey = client.rankedPvpDayKey;
  var rankedPvpFightsToday = client.rankedPvpFightsToday;
  if (client.rankedPvpDayKey == server.rankedPvpDayKey) {
    if (_counter(client.rankedPvpFightsToday) > _counter(server.rankedPvpFightsToday)) {
      rankedPvpFightsToday = server.rankedPvpFightsToday;
    }
  } else if (_counter(client.rankedPvpFightsToday) > 0 && server.rankedPvpDayKey != null) {
    rankedPvpDayKey = server.rankedPvpDayKey;
    rankedPvpFightsToday = server.rankedPvpFightsToday;
  }
  return client.copyWith(
    gold: gold,
    bountyClaimedIds: client.bountyClaimedIds.where(allowed.contains).toList(),
    rankedPvpWins: rankedPvpWins,
    rankedPvpLosses: rankedPvpLosses,
    rankedPvpDayKey: rankedPvpDayKey,
    rankedPvpFightsToday: rankedPvpFightsToday,
  );
}
