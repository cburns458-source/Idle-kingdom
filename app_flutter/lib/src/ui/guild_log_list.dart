import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'format.dart';

/// Newest-first guild log. One existing icon per entry kind.
class GuildLogList extends StatelessWidget {
  const GuildLogList({super.key, required this.entries, this.itemName});

  final List<GuildLogEntry> entries;
  final String Function(String itemId)? itemName;

  @override
  Widget build(BuildContext context) {
    final rows = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      key: const Key('guild-log-list'),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Padding(
          key: Key('guild-log-row-${row.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                guildLogKindIcon(row.kind),
                key: Key('guild-log-icon-${row.kind}'),
                size: 18,
                color: Palette.gold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guildLogLine(row, itemName: itemName),
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

IconData guildLogKindIcon(String kind) {
  return switch (kind) {
    guildLogKindTierComplete => Icons.flag,
    guildLogKindDonation => Icons.inventory_2,
    guildLogKindJoin => Icons.person_add,
    guildLogKindLeave => Icons.person_remove,
    guildLogKindRankChange => Icons.military_tech,
    _ => Icons.notes,
  };
}

/// Prefers Quest's stored line; falls back to the fields Sys already wrote.
String guildLogLine(GuildLogEntry row, {String Function(String itemId)? itemName}) {
  if (row.message.isNotEmpty) return row.message;
  switch (row.kind) {
    case guildLogKindDonation:
      final gold = row.gold > 0 ? '${formatThousands(row.gold)} gold' : '';
      final items = row.items
          .map(
            (item) =>
                '${formatThousands(item.quantity)} ${itemName?.call(item.itemId) ?? item.itemId}',
          )
          .join(', ');
      return [gold, items].where((part) => part.isNotEmpty).join(' · ');
    case guildLogKindJoin:
      return '${row.actorUsername} joined the guild.';
    case guildLogKindLeave:
      return '${row.actorUsername} left the guild.';
    case guildLogKindRankChange:
      return '${row.actorUsername} is now ${row.role ?? 'a member'}.';
    case guildLogKindTierComplete:
      return guildHallTierFinishLine(row.tierId ?? '') ?? row.tierId ?? '';
    default:
      return row.kind;
  }
}
