import '../json_support.dart';

const List<String> guildLogKinds = <String>[
  'tier_complete',
  'donation',
  'join',
  'leave',
  'rank_change',
];

const String guildLogKindTierComplete = 'tier_complete';
const String guildLogKindDonation = 'donation';
const String guildLogKindJoin = 'join';
const String guildLogKindLeave = 'leave';
const String guildLogKindRankChange = 'rank_change';

class GuildLogDonationItem {
  const GuildLogDonationItem({required this.itemId, required this.quantity});

  factory GuildLogDonationItem.fromJson(Map<String, Object?> json) => GuildLogDonationItem(
    itemId: json['itemId'] as String? ?? '',
    quantity: json['quantity'] is num ? json['quantity']! as num : 0,
  );

  final String itemId;
  final num quantity;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'quantity': quantity};
}

class GuildLogEntry {
  const GuildLogEntry({
    required this.id,
    required this.guildId,
    required this.kind,
    required this.createdAt,
    required this.actorUsername,
    required this.message,
    this.actorUserId,
    this.role,
    this.targetUserId,
    this.targetUsername,
    this.tierId,
    this.gold = 0,
    this.items = const <GuildLogDonationItem>[],
  });

  factory GuildLogEntry.fromJson(Map<String, Object?> json) => GuildLogEntry(
    id: json['id'] as String? ?? '',
    guildId: json['guildId'] as String? ?? json['guild_id'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
    actorUsername: json['actorUsername'] as String? ?? json['actor_username'] as String? ?? '',
    message: json['message'] as String? ?? '',
    actorUserId: json['actorUserId'] as String? ?? json['actor_user_id'] as String?,
    role: json['role'] as String?,
    targetUserId: json['targetUserId'] as String? ?? json['target_user_id'] as String?,
    targetUsername: json['targetUsername'] as String? ?? json['target_username'] as String?,
    tierId: json['tierId'] as String? ?? json['tier_id'] as String?,
    gold: json['gold'] is num ? json['gold']! as num : 0,
    items: json['items'] is List
        ? (json['items']! as List)
              .where((row) => row is Map)
              .map((row) => GuildLogDonationItem.fromJson(asJsonMap(row)))
              .toList()
        : const <GuildLogDonationItem>[],
  );

  final String id;
  final String guildId;
  final String kind;
  final String createdAt;
  final String? actorUserId;
  final String actorUsername;
  final String? role;
  final String? targetUserId;
  final String? targetUsername;
  final String? tierId;
  final String message;
  final num gold;
  final List<GuildLogDonationItem> items;

  GuildLogEntry copyWith({num? gold, List<GuildLogDonationItem>? items, String? message}) =>
      GuildLogEntry(
        id: id,
        guildId: guildId,
        kind: kind,
        createdAt: createdAt,
        actorUserId: actorUserId,
        actorUsername: actorUsername,
        role: role,
        targetUserId: targetUserId,
        targetUsername: targetUsername,
        tierId: tierId,
        message: message ?? this.message,
        gold: gold ?? this.gold,
        items: items ?? this.items,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'guildId': guildId,
    'kind': kind,
    'createdAt': createdAt,
    'actorUserId': actorUserId,
    'actorUsername': actorUsername,
    'role': role,
    'targetUserId': targetUserId,
    'targetUsername': targetUsername,
    'tierId': tierId,
    'message': message,
    'gold': gold,
    'items': items.map((row) => row.toJson()).toList(),
  };
}

class GuildLogDonationMerge {
  const GuildLogDonationMerge.merged(this.entry) : merged = true;

  const GuildLogDonationMerge.kept() : merged = false, entry = null;

  final bool merged;
  final GuildLogEntry? entry;
}

/// Consecutive donation batches from one player merge into one line.
GuildLogDonationMerge mergeGuildLogDonation(GuildLogEntry? newest, GuildLogEntry incoming) {
  if (newest == null ||
      newest.kind != guildLogKindDonation ||
      incoming.kind != guildLogKindDonation) {
    return const GuildLogDonationMerge.kept();
  }
  if (newest.actorUserId != incoming.actorUserId || newest.actorUserId == null) {
    return const GuildLogDonationMerge.kept();
  }
  return GuildLogDonationMerge.merged(
    newest.copyWith(
      gold: newest.gold + incoming.gold,
      items: mergeDonationItems(newest.items, incoming.items),
      message: incoming.message.isEmpty ? newest.message : incoming.message,
    ),
  );
}

List<GuildLogDonationItem> mergeDonationItems(
  List<GuildLogDonationItem> existing,
  List<GuildLogDonationItem> added,
) {
  final next = <GuildLogDonationItem>[
    for (final row in existing) GuildLogDonationItem(itemId: row.itemId, quantity: row.quantity),
  ];
  for (final row in added) {
    final at = next.indexWhere((entry) => entry.itemId == row.itemId);
    if (at < 0) {
      next.add(row);
    } else {
      next[at] = GuildLogDonationItem(
        itemId: row.itemId,
        quantity: next[at].quantity + row.quantity,
      );
    }
  }
  return next;
}
