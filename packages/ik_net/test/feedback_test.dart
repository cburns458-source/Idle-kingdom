import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('form validation', () {
    test('title and body length bounds', () {
      expect(feedbackTitleError('abcd'), isNotNull);
      expect(feedbackTitleError('abcde'), isNull);
      expect(feedbackTitleError('x' * 80), isNull);
      expect(feedbackTitleError('x' * 81), isNotNull);
      expect(feedbackBodyError('123456789'), isNotNull);
      expect(feedbackBodyError('1234567890'), isNull);
      expect(feedbackBodyError('x' * 1000), isNull);
      expect(feedbackBodyError('x' * 1001), isNotNull);
    });

    test('kind and player target', () {
      expect(feedbackKindError('bug'), isNull);
      expect(feedbackKindError('suggestion'), isNull);
      expect(feedbackKindError('player'), isNull);
      expect(feedbackKindError('exploit'), isNotNull);
      expect(feedbackPlayerTargetError(feedbackKindBug, null), isNull);
      expect(feedbackPlayerTargetError(feedbackKindPlayer, ''), isNotNull);
      expect(feedbackPlayerTargetError(feedbackKindPlayer, 'Rival'), isNull);
    });

    test('request error and send label', () {
      expect(
        feedbackRequestError(
          const FeedbackRequest(kind: 'bug', title: 'Hey', body: 'Details that are long enough.'),
        ),
        isNotNull,
      );
      expect(
        feedbackRequestError(
          const FeedbackRequest(
            kind: 'bug',
            title: 'Combat stun lock',
            body: 'The goblin stun never ends after the second hit.',
          ),
        ),
        isNull,
      );
      expect(feedbackSendLabel(null), 'Send');
      expect(feedbackSendLabel(45), 'Send in 45s');
      expect(feedbackSendLabel(120), 'Send in 2m');
      expect(feedbackSendLabel(7200), 'Send in 2h');
    });
  });

  group('fake transport', () {
    FeedbackRequest valid({
      String kind = feedbackKindBug,
      String title = 'Combat stun lock',
      String body = 'The goblin stun never ends after the second hit.',
      String? target,
    }) {
      return FeedbackRequest(kind: kind, title: title, body: body, targetUsername: target);
    }

    Future<RemoteMultiplayerService> signedIn(FakeTransport transport) async {
      final service = RemoteMultiplayerService(
        transport: transport,
        storage: MemorySaveStorage(),
        retryDelay: (_) async {},
      );
      final result = await service.signUp('hero@example.com', 'Hero', 'secret');
      expect(result.ok, isTrue, reason: result.reason);
      return service;
    }

    test('signed-in submit returns an id', () async {
      final transport = FakeTransport();
      final hero = await signedIn(transport);
      final sent = await hero.submitFeedback(valid());
      expect(sent.ok, isTrue, reason: sent.reason);
      expect(sent.id, isNotEmpty);
      expect(transport.calls, contains('invoke:$remoteSubmitFeedbackFunction'));
      expect(transport.tables[RemoteTables.playerFeedback]!.single['title'], 'Combat stun lock');
    });

    test('unsigned invoke is refused', () async {
      final transport = FakeTransport();
      final service = RemoteMultiplayerService(
        transport: transport,
        storage: MemorySaveStorage(),
        retryDelay: (_) async {},
      );
      final sent = await service.submitFeedback(valid());
      expect(sent.ok, isFalse);
      expect(sent.reason, feedbackSignInRequired);
    });

    test('cooldown and daily cap', () async {
      var now = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
      final transport = FakeTransport(nowMs: () => now);
      final hero = await signedIn(transport);
      expect((await hero.submitFeedback(valid())).ok, isTrue);
      final cooled = await hero.submitFeedback(valid(title: 'A different summary here'));
      expect(cooled.ok, isFalse);
      expect(cooled.code, feedbackCodeCooldown);
      expect(cooled.retryAfterSeconds, greaterThan(0));

      now += feedbackCooldownMs + 1000;
      for (var i = 0; i < 4; i++) {
        now += feedbackCooldownMs + 1000;
        final more = await hero.submitFeedback(valid(title: 'Another report title $i'));
        expect(more.ok, isTrue, reason: more.reason);
      }
      now += feedbackCooldownMs + 1000;
      final capped = await hero.submitFeedback(valid(title: 'The sixth report title'));
      expect(capped.ok, isFalse);
      expect(capped.code, feedbackCodeDailyCap);
    });

    test('duplicate body returns the original id', () async {
      var now = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
      final transport = FakeTransport(nowMs: () => now);
      final hero = await signedIn(transport);
      final first = await hero.submitFeedback(valid());
      expect(first.ok, isTrue);
      now += feedbackCooldownMs + 1000;
      final second = await hero.submitFeedback(valid());
      expect(second.ok, isTrue);
      expect(second.id, first.id);
      expect(transport.tables[RemoteTables.playerFeedback]!.length, 1);
    });

    test('player report also writes chat_reports', () async {
      final transport = FakeTransport();
      final hero = await signedIn(transport);
      await transport.upsert(RemoteTables.profiles, <RemoteRow>[
        <String, Object?>{'user_id': 'usr_rival', 'username': 'Rival'},
      ]);
      final sent = await hero.submitFeedback(
        const FeedbackRequest(
          kind: feedbackKindPlayer,
          title: 'Spam in global chat',
          body: 'This player is advertising gold sales.',
          targetUsername: 'Rival',
          reportReason: reportReasonSpam,
        ),
      );
      expect(sent.ok, isTrue, reason: sent.reason);
      expect(transport.tables['chat_reports']!.single['reason'], reportReasonSpam);
    });

    test('client-side validation never hits the wire', () async {
      final transport = FakeTransport();
      final hero = await signedIn(transport);
      final sent = await hero.submitFeedback(
        const FeedbackRequest(kind: 'bug', title: 'Hey', body: 'Too short'),
      );
      expect(sent.ok, isFalse);
      expect(transport.calls, isNot(contains('invoke:$remoteSubmitFeedbackFunction')));
    });
  });
}
