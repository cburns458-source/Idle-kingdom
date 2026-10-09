import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;
  late CodexIndex codex;

  setUpAll(() {
    db = _db();
    codex = CodexIndex(db);
  });

  test('parses mixed text and item tokens', () {
    final segments = parseChatBodyWithDb(db, 'Bring @[ITEM-0003] and @[ITEM-0109] please');
    expect(segments, hasLength(5));
    expect(segments[0], isA<ChatTextSegment>());
    expect((segments[0] as ChatTextSegment).text, 'Bring ');
    expect(segments[1], isA<ChatItemRefSegment>());
    expect((segments[1] as ChatItemRefSegment).itemId, 'ITEM-0003');
    expect((segments[1] as ChatItemRefSegment).displayName, 'Copper Ore');
    expect((segments[1] as ChatItemRefSegment).known, isTrue);
    expect((segments[3] as ChatItemRefSegment).displayName, 'Bola');
  });

  test('unknown ids render as unavailable', () {
    final segments = parseChatBodyWithDb(db, 'See @[ITEM-999999]');
    final ref = segments.whereType<ChatItemRefSegment>().single;
    expect(ref.known, isFalse);
    expect(ref.displayName, 'Unavailable item');
  });

  test('malformed tokens stay plain text', () {
    final segments = parseChatBodyWithDb(db, 'Hi @[not-an-id] and @bare');
    expect(segments, hasLength(1));
    expect((segments.single as ChatTextSegment).text, 'Hi @[not-an-id] and @bare');
  });

  test('materializes unique display names and leaves ambiguous or unknown alone', () {
    expect(materializeAllItemMentions(db, 'Need @copper ore now'), contains('@[ITEM-0003]'));
    expect(materializeAllItemMentions(db, 'Toss a @bola please'), contains('@[ITEM-0109]'));
    expect(materializeAllItemMentions(db, 'Hello @nobody'), 'Hello @nobody');
    expect(materializeAllItemMentions(db, 'Already @[ITEM-0003] ok'), 'Already @[ITEM-0003] ok');
  });

  test('autocomplete filters by typed query', () {
    final rows = chatItemAutocomplete(codex, 'copper');
    expect(rows.map((row) => row.itemId), contains('ITEM-0003'));
    expect(rows.length, lessThanOrEqualTo(12));
  });

  test('sanitize drops forged item ids', () {
    final cleaned = sanitizeChatItemRefsWithDb(db, 'x @[ITEM-0003] y @[ITEM-999999] z');
    expect(cleaned, 'x @[ITEM-0003] y  z');
  });

  test('insert replaces an open @query', () {
    final result = insertChatItemRef('Need @cop', 9, 'ITEM-0003');
    expect(result.text, 'Need @[ITEM-0003]');
    expect(result.cursor, 'Need @[ITEM-0003]'.length);
  });
}
