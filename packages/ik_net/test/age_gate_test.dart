import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  final asOf = DateTime.utc(2026, 10, 17);

  test('chat turns on at 13 and stays off until the birthday', () {
    expect(accountAgeYears(2013, 10, asOf), 13);
    expect(accountAgeYears(2013, 11, asOf), 12);
    expect(chatAllowedFromAge(answered: true, birthYear: 2013, birthMonth: 10, asOf: asOf), isTrue);
    expect(
      chatAllowedFromAge(answered: true, birthYear: 2013, birthMonth: 11, asOf: asOf),
      isFalse,
    );
  });

  test('a year-only answer cannot unlock chat early', () {
    expect(accountAgeYears(2013, null, asOf), 12);
    expect(chatAllowedFromAge(answered: true, birthYear: 2013, asOf: asOf), isFalse);
  });

  test('birthday rollover unlocks chat without a new answer', () {
    // A known month uses the 1st, so October 2013 turns 13 on 1 Oct 2026.
    expect(
      chatAllowedFromAge(
        answered: true,
        birthYear: 2013,
        birthMonth: 10,
        asOf: DateTime.utc(2026, 9, 30),
      ),
      isFalse,
    );
    expect(
      chatAllowedFromAge(
        answered: true,
        birthYear: 2013,
        birthMonth: 10,
        asOf: DateTime.utc(2026, 10, 1),
      ),
      isTrue,
    );
  });

  test('unanswered accounts and 0-12 store bands are refused', () {
    expect(chatAllowedFromAge(answered: false, birthYear: 2000, birthMonth: 1), isFalse);
    expect(storeBandAllowsChat('0-12'), isFalse);
    expect(storeBandAllowsChat('13-15'), isTrue);
    expect(needsBirthMonth(2013, asOf), isTrue);
  });

  test('hosted send-chat, reads, and friend requests all 403 when chat is off', () async {
    final transport = FakeTransport();
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);
    transport.setAccountStatus(service.session!.userId, const AccountSocialStatus.unanswered());

    final sent = await service.sendChat(const ChatChannel.global(), 'Hi');
    expect(sent.ok, isFalse);
    expect(sent.reason, ageGateError);
    expect(await service.listChat(const ChatChannel.global()), isEmpty);
    expect(await service.listDirectMessages(), isEmpty);

    transport.seedAccount(email: 'rival@example.com', username: 'Rival', userId: 'usr_rival');
    expect((await service.sendFriendRequest('usr_rival')).reason, ageGateError);

    expect((await service.reportPlayer('usr_rival', reportReasonSpam)).ok, isTrue);
    expect((await service.ignorePlayer('usr_rival')).ok, isTrue);
  });

  test('an age answer is locked after the first write', () async {
    final transport = FakeTransport();
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);
    transport.setAccountStatus(service.session!.userId, const AccountSocialStatus.unanswered());
    expect((await service.setAccountAge(birthYear: 2000, birthMonth: 1)).ok, isTrue);
    expect((await service.setAccountAge(birthYear: 2015, birthMonth: 1)).ok, isFalse);
    final status = await service.accountStatus();
    expect(status.ageAnswered, isTrue);
    expect(status.chatAllowed, isTrue);
  });
}
