/// Item references embedded in chat bodies as `@[ITEM-0123]`.
///
/// The token carries a stable id. Display names are resolved at render time from
/// Codex / game data, so renamed items stay linked and forged HTML never runs.
library;

import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Matches a stored item reference. The id must look like a real item id.
final RegExp chatItemRefPattern = RegExp(r'@\[(ITEM-\d+)\]');

final RegExp _itemIdToken = RegExp(r'^ITEM-\d+$', caseSensitive: false);
final RegExp _wordChar = RegExp(r'[A-Za-z0-9]');

/// One piece of a chat body after reference parsing.
sealed class ChatBodySegment {
  const ChatBodySegment();
}

class ChatTextSegment extends ChatBodySegment {
  const ChatTextSegment(this.text);

  final String text;
}

class ChatItemRefSegment extends ChatBodySegment {
  const ChatItemRefSegment({required this.itemId, required this.displayName, required this.known});

  final String itemId;
  final String displayName;
  final bool known;
}

/// True when [raw] looks like a legitimate item id from the game database.
bool isValidChatItemId(String raw) => RegExp(r'^ITEM-\d+$').hasMatch(raw);

/// Splits [body] into plain text and item-reference segments.
///
/// Unknown or malformed ids become unavailable item chips rather than links.
List<ChatBodySegment> parseChatBody(
  String body, {
  required String? Function(String itemId) nameOf,
}) {
  if (body.isEmpty) return const <ChatBodySegment>[];
  final out = <ChatBodySegment>[];
  var cursor = 0;
  for (final match in chatItemRefPattern.allMatches(body)) {
    if (match.start > cursor) {
      out.add(ChatTextSegment(body.substring(cursor, match.start)));
    }
    final itemId = match.group(1)!;
    final name = nameOf(itemId);
    out.add(
      ChatItemRefSegment(
        itemId: itemId,
        displayName: name ?? 'Unavailable item',
        known: name != null,
      ),
    );
    cursor = match.end;
  }
  if (cursor < body.length) {
    out.add(ChatTextSegment(body.substring(cursor)));
  }
  return out;
}

List<ChatBodySegment> parseChatBodyWithDb(GameDatabase db, String body) {
  final names = <String, String>{
    for (final item in db.items)
      if (item.itemId.isNotEmpty) item.itemId: item.displayName,
  };
  return parseChatBody(body, nameOf: (id) => names[id]);
}

/// Codex entries whose display name contains [query] after an `@` trigger.
List<CodexItemEntry> chatItemAutocomplete(CodexIndex codex, String query, {int limit = 12}) {
  final rows = codex.itemsMatching(query: query);
  if (rows.length <= limit) return rows;
  return rows.take(limit).toList();
}

/// Resolves a typed name or id to at most one item id.
///
/// Exact display-name match (case-insensitive) wins. Ambiguous names return null
/// so the message stays plain text.
String? resolveExactItemName(GameDatabase db, String typedName) {
  final needle = typedName.trim();
  if (needle.isEmpty) return null;
  if (_itemIdToken.hasMatch(needle)) {
    final id = needle.toUpperCase();
    if (db.items.any((item) => item.itemId == id)) return id;
    return null;
  }
  final lower = needle.toLowerCase();
  final matches = db.items
      .where((item) => item.displayName.toLowerCase() == lower)
      .map((item) => item.itemId)
      .toSet();
  if (matches.length == 1) return matches.single;
  return null;
}

bool _hasWordBoundary(String rest, int end) {
  if (end >= rest.length) return true;
  return !_wordChar.hasMatch(rest[end]);
}

/// Converts `@Name` / `@ITEM-####` mentions into `@[ITEM-…]` tokens when unique.
String materializeAllItemMentions(GameDatabase db, String body) {
  final names = <({String name, String itemId})>[
    for (final item in db.items) (name: item.displayName, itemId: item.itemId),
  ]..sort((a, b) => b.name.length.compareTo(a.name.length));

  final buffer = StringBuffer();
  var i = 0;
  while (i < body.length) {
    if (body.codeUnitAt(i) == 0x40 /* @ */ ) {
      final token = chatItemRefPattern.matchAsPrefix(body, i);
      if (token != null) {
        buffer.write(token.group(0));
        i = token.end;
        continue;
      }

      final rest = body.substring(i + 1);
      final idMatch = RegExp(r'^(ITEM-\d+)', caseSensitive: false).matchAsPrefix(rest);
      if (idMatch != null && _hasWordBoundary(rest, idMatch.end)) {
        final id = idMatch.group(1)!.toUpperCase();
        if (db.items.any((item) => item.itemId == id)) {
          buffer.write('@[$id]');
          i += 1 + idMatch.end;
          continue;
        }
      }

      String? bestId;
      var bestLen = 0;
      final tied = <String>{};
      for (final row in names) {
        final name = row.name;
        if (name.isEmpty || rest.length < name.length) continue;
        if (rest.substring(0, name.length).toLowerCase() != name.toLowerCase()) continue;
        if (!_hasWordBoundary(rest, name.length)) continue;
        if (name.length > bestLen) {
          bestLen = name.length;
          bestId = row.itemId;
          tied
            ..clear()
            ..add(row.itemId);
        } else if (name.length == bestLen) {
          tied.add(row.itemId);
        }
      }
      if (bestId != null && tied.length == 1) {
        buffer.write('@[$bestId]');
        i += 1 + bestLen;
        continue;
      }
    }
    buffer.writeCharCode(body.codeUnitAt(i));
    i += 1;
  }
  return buffer.toString();
}

/// Drops item tokens whose ids are not present in [validIds].
String sanitizeChatItemRefs(String body, Set<String> validIds) {
  return body.replaceAllMapped(chatItemRefPattern, (match) {
    final itemId = match.group(1)!;
    return validIds.contains(itemId) ? match.group(0)! : '';
  });
}

String sanitizeChatItemRefsWithDb(GameDatabase db, String body) {
  final valid = <String>{for (final item in db.items) item.itemId};
  return sanitizeChatItemRefs(body, valid);
}

/// The label shown for a reference chip.
String chatItemRefLabel(ChatItemRefSegment segment) =>
    segment.known ? segment.displayName : 'Unavailable item';

/// Inserts `@[itemId]` at [cursor], replacing an open `@query` mention when present.
({String text, int cursor}) insertChatItemRef(String text, int cursor, String itemId) {
  if (!isValidChatItemId(itemId)) return (text: text, cursor: cursor);
  final safeCursor = cursor.clamp(0, text.length);
  final before = text.substring(0, safeCursor);
  final after = text.substring(safeCursor);
  final at = before.lastIndexOf('@');
  final open = at >= 0 && !before.substring(at).contains(']');
  final prefix = open ? before.substring(0, at) : before;
  final token = '@[$itemId]';
  final next = '$prefix$token$after';
  return (text: next, cursor: prefix.length + token.length);
}
