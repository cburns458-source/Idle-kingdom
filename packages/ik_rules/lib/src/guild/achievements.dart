import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import 'hall.dart';

/// Palette ids for banner fill and accent. Hex values are a UI choice.
const List<String> guildBannerPalette = <String>[
  'slate',
  'midnight',
  'wine',
  'rust',
  'ivory',
  'ash',
  'indigo',
  'ocean',
  'ember',
  'plum',
];

const String guildBannerDefaultBackground = 'slate';
const String guildBannerDefaultAccent = 'ivory';

const String guildBannerRewardEmblem = 'emblem';
const String guildBannerRewardBorder = 'border';

class GuildBanner {
  const GuildBanner({required this.background, required this.accent, this.emblem, this.border});

  final String background;
  final String accent;
  final String? emblem;
  final String? border;

  Map<String, Object?> toJson() => <String, Object?>{
    'background': background,
    'accent': accent,
    'emblem': emblem,
    'border': border,
  };
}

const GuildBanner defaultGuildBanner = GuildBanner(
  background: guildBannerDefaultBackground,
  accent: guildBannerDefaultAccent,
);

const num guildAchievementGold100k = 100000;
const num guildAchievementGold500k = 500000;
const num guildAchievementMaterials = 100000;
const num guildAchievementDonors10 = 10;
const num guildAchievementDonors25 = 25;

/// Hosted-save totalLevel gate. Count via [totalLevel] of the cloud save, never
/// the client-writable guild_members.total_level column.
const num guildAchievementMemberLevel = 500;
const num guildAchievementMembersAtLevel = 25;

/// Rising strength reads the hosted save, same as SQL bazaar_user_total_level.
/// A member with no save counts as 0. Do not use guild_members.total_level.
num guildMemberSaveTotalLevel(PlayerSave? save) => save == null ? 0 : totalLevel(save);

/// False once Rising strength is unlocked; skip the hosted-save member scan.
bool shouldCountRisingStrengthMembers(Map<String, String> unlocked) =>
    unlocked['gach_rising_strength'] == null;

const String guildAchievementKindHallTier = 'hall_tier';
const String guildAchievementKindGold = 'gold';
const String guildAchievementKindMaterials = 'materials';
const String guildAchievementKindDonors = 'donors';
const String guildAchievementKindMembersLevel = 'members_level';

class GuildAchievementDef {
  const GuildAchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.rewardKind,
    required this.rewardId,
    required this.kind,
    required this.target,
    this.tierId,
  });

  final String id;
  final String name;
  final String description;
  final String rewardKind;
  final String rewardId;
  final String kind;
  final num target;
  final String? tierId;
}

/// Guild-wide cosmetics. Quest owns the names and descriptions; keep them in
/// this list so they can edit one place.
const List<GuildAchievementDef> guildAchievements = <GuildAchievementDef>[
  GuildAchievementDef(
    id: 'gach_foundations',
    name: 'Foundations laid',
    description: 'Build the first tier of the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_foundations',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierBuild,
  ),
  GuildAchievementDef(
    id: 'gach_hall_2',
    name: 'Raised walls',
    description: 'Build tier 2 of the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_counting',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierBank,
  ),
  GuildAchievementDef(
    id: 'gach_hall_3',
    name: 'Under one roof',
    description: 'Build tier 3 of the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_boxing',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierBoxing,
  ),
  GuildAchievementDef(
    id: 'gach_hall_4',
    name: 'Banners high',
    description: 'Build tier 4 of the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_garden',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierGarden,
  ),
  GuildAchievementDef(
    id: 'gach_hall_arcana',
    name: 'Arcane corner',
    description: 'Build the Arcana station in the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_arcana',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierArcana,
  ),
  GuildAchievementDef(
    id: 'gach_hall_5',
    name: 'A hall fit for kings',
    description: 'Build tier 5 of the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_cage',
    kind: guildAchievementKindHallTier,
    target: 1,
    tierId: guildHallTierCage,
  ),
  GuildAchievementDef(
    id: 'gach_gold_100k',
    name: 'Deep pockets',
    description: 'Chip in 100,000 gold toward the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_pockets',
    kind: guildAchievementKindGold,
    target: guildAchievementGold100k,
  ),
  GuildAchievementDef(
    id: 'gach_gold_500k',
    name: 'Deeper pockets',
    description: 'Chip in 500,000 gold toward the guild hall.',
    rewardKind: guildBannerRewardEmblem,
    rewardId: 'emblem_deeper_pockets',
    kind: guildAchievementKindGold,
    target: guildAchievementGold500k,
  ),
  GuildAchievementDef(
    id: 'gach_materials',
    name: 'Stocked vault',
    description: 'Use 100,000 materials building the guild hall.',
    rewardKind: guildBannerRewardBorder,
    rewardId: 'border_vault',
    kind: guildAchievementKindMaterials,
    target: guildAchievementMaterials,
  ),
  // Vari: Many hands rules stay unchanged (gold chip-in or hall material donate).
  GuildAchievementDef(
    id: 'gach_donors_10',
    name: 'Many hands',
    description: 'Have 10 different members chip in.',
    rewardKind: guildBannerRewardBorder,
    rewardId: 'border_hands',
    kind: guildAchievementKindDonors,
    target: guildAchievementDonors10,
  ),
  GuildAchievementDef(
    id: 'gach_donors_25',
    name: 'More hands',
    description: 'Have 25 different members chip in.',
    rewardKind: guildBannerRewardBorder,
    rewardId: 'border_more_hands',
    kind: guildAchievementKindDonors,
    target: guildAchievementDonors25,
  ),
  // Vari: stays unlocked after members leave (unlock-once).
  GuildAchievementDef(
    id: 'gach_rising_strength',
    name: 'Rising strength',
    description: 'Have 25 members reach total level 500.',
    rewardKind: guildBannerRewardBorder,
    rewardId: 'border_strength',
    kind: guildAchievementKindMembersLevel,
    target: guildAchievementMembersAtLevel,
  ),
];

Map<String, GuildAchievementDef> get guildAchievementById => <String, GuildAchievementDef>{
  for (final row in guildAchievements) row.id: row,
};

List<String> get guildBannerEmblemIds => [
  for (final row in guildAchievements)
    if (row.rewardKind == guildBannerRewardEmblem) row.rewardId,
];

List<String> get guildBannerBorderIds => [
  for (final row in guildAchievements)
    if (row.rewardKind == guildBannerRewardBorder) row.rewardId,
];

class GuildAchievementSnapshot {
  const GuildAchievementSnapshot({
    required this.completedTiers,
    required this.goldContributed,
    this.goldContributedBy = const <String, num>{},
    this.donatedBy = const <String, bool>{},
    this.membersAtLevel500 = 0,
    this.unlocked = const <String, String>{},
  });

  final List<String> completedTiers;
  final num goldContributed;
  final Map<String, num> goldContributedBy;
  final Map<String, bool> donatedBy;
  final num membersAtLevel500;

  /// Achievement id to ISO unlocked_at.
  final Map<String, String> unlocked;
}

class GuildAchievementProgress {
  const GuildAchievementProgress({
    required this.id,
    required this.name,
    required this.description,
    required this.current,
    required this.target,
    required this.unlocked,
    this.unlockedAt,
    required this.rewardKind,
    required this.rewardId,
  });

  final String id;
  final String name;
  final String description;
  final num current;
  final num target;
  final bool unlocked;
  final String? unlockedAt;
  final String rewardKind;
  final String rewardId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'current': current,
    'target': target,
    'unlocked': unlocked,
    'unlockedAt': unlockedAt,
    'rewardKind': rewardKind,
    'rewardId': rewardId,
  };
}

class GuildAchievementEvaluation {
  const GuildAchievementEvaluation({
    required this.newlyUnlocked,
    required this.unlocked,
    required this.progress,
  });

  final List<String> newlyUnlocked;
  final Map<String, String> unlocked;
  final List<GuildAchievementProgress> progress;
}

bool guildMaySetBanner(String role) => role == 'leader' || role == 'officer';

const String guildBannerRoleRefusal = 'Only the guild leader or an officer can change the banner.';
const String guildBannerColourRefusal = 'That colour is not on the banner palette.';
const String guildBannerEmblemRefusal = 'That emblem is not unlocked.';
const String guildBannerBorderRefusal = 'That border is not unlocked.';

List<String> guildDonorIds({
  Map<String, num> goldContributedBy = const <String, num>{},
  Map<String, bool> donatedBy = const <String, bool>{},
}) {
  final ids = <String>{};
  for (final entry in goldContributedBy.entries) {
    if (entry.key.isNotEmpty && entry.value > 0) ids.add(entry.key);
  }
  for (final entry in donatedBy.entries) {
    if (entry.key.isNotEmpty && entry.value) ids.add(entry.key);
  }
  return ids.toList();
}

num guildAchievementCurrent(GuildAchievementDef def, GuildAchievementSnapshot snapshot) {
  switch (def.kind) {
    case guildAchievementKindHallTier:
      final tierId = def.tierId;
      if (tierId == null) return 0;
      return snapshot.completedTiers.contains(tierId) ? 1 : 0;
    case guildAchievementKindGold:
      return snapshot.goldContributed < 0 ? 0 : snapshot.goldContributed;
    case guildAchievementKindMaterials:
      return guildHallMaterialsSpent(snapshot.completedTiers);
    case guildAchievementKindDonors:
      return guildDonorIds(
        goldContributedBy: snapshot.goldContributedBy,
        donatedBy: snapshot.donatedBy,
      ).length;
    case guildAchievementKindMembersLevel:
      return snapshot.membersAtLevel500 < 0 ? 0 : snapshot.membersAtLevel500;
    default:
      return 0;
  }
}

({Set<String> emblems, Set<String> borders}) unlockedRewardIds(
  Iterable<String> unlockedAchievementIds,
) {
  final emblems = <String>{};
  final borders = <String>{};
  final byId = guildAchievementById;
  for (final id in unlockedAchievementIds) {
    final def = byId[id];
    if (def == null) continue;
    if (def.rewardKind == guildBannerRewardEmblem) {
      emblems.add(def.rewardId);
    } else {
      borders.add(def.rewardId);
    }
  }
  return (emblems: emblems, borders: borders);
}

GuildAchievementEvaluation evaluateGuildAchievements(
  GuildAchievementSnapshot snapshot,
  String nowIso,
) {
  final unlocked = <String, String>{...snapshot.unlocked};
  final newlyUnlocked = <String>[];
  final progress = <GuildAchievementProgress>[];
  for (final def in guildAchievements) {
    final current = guildAchievementCurrent(def, snapshot);
    final already = unlocked[def.id];
    if (already == null && current >= def.target) {
      unlocked[def.id] = nowIso;
      newlyUnlocked.add(def.id);
    }
    final unlockedAt = unlocked[def.id];
    progress.add(
      GuildAchievementProgress(
        id: def.id,
        name: def.name,
        description: def.description,
        current: current,
        target: def.target,
        unlocked: unlockedAt != null,
        unlockedAt: unlockedAt,
        rewardKind: def.rewardKind,
        rewardId: def.rewardId,
      ),
    );
  }
  return GuildAchievementEvaluation(
    newlyUnlocked: newlyUnlocked,
    unlocked: unlocked,
    progress: progress,
  );
}

class GuildBannerNormalizeResult {
  const GuildBannerNormalizeResult.ok(this.banner) : reason = null;

  const GuildBannerNormalizeResult.failed(this.reason) : banner = null;

  final GuildBanner? banner;
  final String? reason;

  bool get ok => reason == null;
}

/// Shape-only read for a stored banner. Unlock checks belong on set.
GuildBanner readGuildBanner(Object? raw) {
  final source = raw is Map ? raw : const <String, Object?>{};
  final backgroundRaw = source['background'];
  final accentRaw = source['accent'];
  final background = backgroundRaw is String && guildBannerPalette.contains(backgroundRaw)
      ? backgroundRaw
      : defaultGuildBanner.background;
  final accent = accentRaw is String && guildBannerPalette.contains(accentRaw)
      ? accentRaw
      : defaultGuildBanner.accent;
  final emblemRaw = source['emblem'];
  final borderRaw = source['border'];
  final emblem = emblemRaw is String && guildBannerEmblemIds.contains(emblemRaw) ? emblemRaw : null;
  final border = borderRaw is String && guildBannerBorderIds.contains(borderRaw) ? borderRaw : null;
  return GuildBanner(background: background, accent: accent, emblem: emblem, border: border);
}

GuildBannerNormalizeResult normalizeGuildBanner(
  Object? raw, [
  Iterable<String> unlockedAchievementIds = const <String>[],
]) {
  final source = raw is Map ? raw : const <String, Object?>{};
  final background = source['background'] ?? defaultGuildBanner.background;
  final accent = source['accent'] ?? defaultGuildBanner.accent;
  if (background is! String ||
      accent is! String ||
      !guildBannerPalette.contains(background) ||
      !guildBannerPalette.contains(accent)) {
    return const GuildBannerNormalizeResult.failed(guildBannerColourRefusal);
  }
  final emblemRaw = source['emblem'];
  final borderRaw = source['border'];
  final emblem = emblemRaw == null || emblemRaw == '' ? null : emblemRaw;
  final border = borderRaw == null || borderRaw == '' ? null : borderRaw;
  if (emblem != null && emblem is! String) {
    return const GuildBannerNormalizeResult.failed(guildBannerEmblemRefusal);
  }
  if (border != null && border is! String) {
    return const GuildBannerNormalizeResult.failed(guildBannerBorderRefusal);
  }
  final rewards = unlockedRewardIds(unlockedAchievementIds);
  final emblemId = emblem as String?;
  final borderId = border as String?;
  if (emblemId != null &&
      (!guildBannerEmblemIds.contains(emblemId) || !rewards.emblems.contains(emblemId))) {
    return const GuildBannerNormalizeResult.failed(guildBannerEmblemRefusal);
  }
  if (borderId != null &&
      (!guildBannerBorderIds.contains(borderId) || !rewards.borders.contains(borderId))) {
    return const GuildBannerNormalizeResult.failed(guildBannerBorderRefusal);
  }
  return GuildBannerNormalizeResult.ok(
    GuildBanner(background: background, accent: accent, emblem: emblemId, border: borderId),
  );
}

Map<String, bool> withGuildHallDonor(Map<String, bool> donatedBy, String userId) {
  if (userId.isEmpty || donatedBy[userId] == true) return donatedBy;
  return <String, bool>{...donatedBy, userId: true};
}
