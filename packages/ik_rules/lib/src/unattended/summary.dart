import '../js_compat.dart';

/// What the "while you were away" panel reads, derived from a resolved absence.
///
/// The resolver writes one line per craft, which a long absence turns into pages
/// of the same sentence. Merging them is the difference between a summary and a
/// log, so it belongs with the rules rather than in whichever client draws it.

final RegExp _craftedLine = RegExp(
  r'^Crafted (\d+) (.+) \(\+(\d+(?:\.\d+)?) XP\)$',
  caseSensitive: false,
);

/// One line per crafted item, holding the totals and the order they arrived in.
///
/// Anything that is not a craft line is left exactly as the resolver wrote it,
/// and each item keeps the place its first line had, so the story of the absence
/// still reads in order. After crafts are merged, any other identical message is
/// collapsed to a single line with how many times it appeared.
List<String> consolidateAwayMessages(List<String> messages) {
  final totals = <String, _CraftTotal>{};
  final lines = <String?>[];

  for (final message in messages) {
    final match = _craftedLine.firstMatch(message);
    if (match == null) {
      lines.add(message);
      continue;
    }
    final quantity = num.parse(match.group(1)!);
    final name = match.group(2)!;
    final xp = num.parse(match.group(3)!);
    final existing = totals[name];
    if (existing != null) {
      existing.quantity += quantity;
      existing.xp += xp;
      continue;
    }
    totals[name] = _CraftTotal(quantity: quantity, xp: xp, slot: lines.length);
    lines.add(message);
  }

  for (final entry in totals.entries) {
    final total = entry.value;
    lines[total.slot] =
        'Crafted ${jsNumberToString(total.quantity)} ${entry.key} '
        '(+${jsNumberToString(total.xp)} XP)';
  }

  final crafted = lines.whereType<String>().toList();
  return _collapseRepeatedMessages(crafted);
}

/// Identical lines become one line with "… X times." keeping first-seen order.
List<String> _collapseRepeatedMessages(List<String> messages) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final message in messages) {
    final seen = counts[message];
    if (seen == null) {
      counts[message] = 1;
      order.add(message);
    } else {
      counts[message] = seen + 1;
    }
  }
  return [
    for (final message in order)
      if ((counts[message] ?? 1) <= 1) message else '$message … ${counts[message]} times.',
  ];
}

class _CraftTotal {
  _CraftTotal({required this.quantity, required this.xp, required this.slot});

  num quantity;
  num xp;

  /// Where the first line for this item sat, which is where the total goes.
  final int slot;
}
