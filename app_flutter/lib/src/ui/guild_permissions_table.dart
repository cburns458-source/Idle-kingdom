import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';

const Map<String, String> guildPermissionActionLabels = <String, String>{
  guildPermissionDeposit: 'Deposit',
  guildPermissionWithdraw: 'Withdraw',
  guildPermissionMoveUpForGrabs: 'Move',
};

/// Ranks across, actions down. Leader-only edit; other ranks stay read-only.
class GuildPermissionsTable extends StatelessWidget {
  const GuildPermissionsTable({
    super.key,
    required this.table,
    required this.canEdit,
    required this.onChanged,
    this.rankLabels,
  });

  final GuildPermissionTable table;
  final bool canEdit;
  final ValueChanged<GuildPermissionTable> onChanged;
  final Map<GuildRankKey, String>? rankLabels;

  String _rankLabel(String rank) {
    final labels = rankLabels ?? defaultGuildRankLabels;
    return labels[rank] ?? rank;
  }

  void _toggle(String action, String rank, bool selected) {
    if (!canEdit || rank == 'leader') return;
    final current = [...table.ranksFor(action)];
    if (selected) {
      if (!current.contains(rank)) current.add(rank);
    } else {
      current.remove(rank);
    }
    if (!current.contains('leader')) current.insert(0, 'leader');
    onChanged(
      GuildPermissionTable(
        ranksByAction: <String, List<String>>{...table.ranksByAction, action: current},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Table(
      key: const Key('guild-permissions-table'),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{0: IntrinsicColumnWidth()},
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final rank in guildPermissionRanks)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(
                  _rankLabel(rank),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: GameFont.xs, fontWeight: FontWeight.w400),
                ),
              ),
          ],
        ),
        for (final action in guildPermissionActions)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                child: Text(
                  guildPermissionActionLabels[action] ?? action,
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
              ),
              for (final rank in guildPermissionRanks)
                Center(
                  child: Checkbox(
                    key: Key('guild-perm-$action-$rank'),
                    value: table.ranksFor(action).contains(rank) || rank == 'leader',
                    onChanged: !canEdit || rank == 'leader'
                        ? null
                        : (value) => _toggle(action, rank, value ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: const BorderSide(color: Palette.goldShade),
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return Palette.gold;
                      return Palette.panel;
                    }),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
