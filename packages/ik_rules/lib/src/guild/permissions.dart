const List<String> guildPermissionActions = <String>['deposit', 'withdraw', 'move_up_for_grabs'];

const String guildPermissionDeposit = 'deposit';
const String guildPermissionWithdraw = 'withdraw';
const String guildPermissionMoveUpForGrabs = 'move_up_for_grabs';

const List<String> guildPermissionRanks = <String>[
  'leader',
  'officer',
  'veteran',
  'member',
  'recruit',
];

/// Ranks that may perform each action when a guild has not set its own table.
const Map<String, List<String>> defaultGuildPermissionRanks = <String, List<String>>{
  guildPermissionDeposit: <String>['leader', 'officer', 'veteran', 'member', 'recruit'],
  guildPermissionWithdraw: <String>['leader', 'officer'],
  guildPermissionMoveUpForGrabs: <String>['leader', 'officer'],
};

class GuildPermissionTable {
  const GuildPermissionTable({required this.ranksByAction});

  final Map<String, List<String>> ranksByAction;

  List<String> ranksFor(String action) =>
      ranksByAction[action] ?? defaultGuildPermissionRanks[action] ?? const <String>[];

  Map<String, Object?> toJson() => <String, Object?>{
    for (final action in guildPermissionActions) action: ranksFor(action),
  };
}

GuildPermissionTable defaultGuildPermissionTable() => GuildPermissionTable(
  ranksByAction: <String, List<String>>{
    for (final entry in defaultGuildPermissionRanks.entries) entry.key: [...entry.value],
  },
);

GuildPermissionTable normalizeGuildPermissionTable(Object? raw) {
  final defaults = defaultGuildPermissionTable();
  if (raw is! Map) return defaults;
  final next = <String, List<String>>{
    for (final entry in defaults.ranksByAction.entries) entry.key: [...entry.value],
  };
  for (final action in guildPermissionActions) {
    final value = raw[action];
    if (value is! List) continue;
    final ranks = value.whereType<String>().toList();
    next[action] = guildPermissionRanks.where(ranks.contains).toList();
  }
  return GuildPermissionTable(ranksByAction: next);
}

const num guildBankTotalLevelRequired = 200;

const String guildBankLevelWithdrawRefusal =
    'Reach total level 200 to withdraw from the guild bank.';

/// One server-side check used by hall, bank, and settings commands.
///
/// The leader always may. Everyone else reads the per-rank table the leader set.
bool guildMay(String role, String action, [GuildPermissionTable? table]) {
  if (role == 'leader') return true;
  final allowed = (table ?? defaultGuildPermissionTable()).ranksFor(action);
  return allowed.contains(role);
}

bool guildMayWithdrawAtLevel(num totalLevel) => totalLevel >= guildBankTotalLevelRequired;
