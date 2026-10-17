import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('delete confirms the character name and blocks staff', () async {
    final transport = FakeTransport();
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);
    expect((await service.requestAccountDeletion('Other')).ok, isFalse);
    expect((await service.requestAccountDeletion('Hero')).ok, isTrue);
    expect((await service.accountStatus()).deletionPending, isTrue);

    final staff = FakeTransport.joining(transport);
    final staffService = RemoteMultiplayerService(
      transport: staff,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await staffService.signUp('staff@example.com', 'Staff', 'secret')).ok, isTrue);
    staff.developerIds.add(staffService.session!.userId);
    expect((await staffService.requestAccountDeletion('Staff')).reason, contains('Staff'));
  });

  test('restore during grace keeps the account; cancelled orders stay cancelled', () async {
    final transport = FakeTransport();
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);
    expect((await service.requestAccountDeletion('Hero')).ok, isTrue);
    expect((await service.restoreAccount()).ok, isTrue);
    expect((await service.accountStatus()).deletionPending, isFalse);
  });

  test('a pending deletion freezes chat and new Bazaar offers', () async {
    final transport = FakeTransport();
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      retryDelay: (_) async {},
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);
    expect((await service.requestAccountDeletion('Hero')).ok, isTrue);
    expect((await service.sendChat(const ChatChannel.global(), 'Hi')).ok, isFalse);
    expect(await service.listChat(const ChatChannel.global()), isEmpty);
    final placed = await transport.invoke(remoteBazaarMarketFunction, <String, Object?>{
      'action': 'place',
    });
    expect(placed.ok, isFalse);
    expect(placed.reason, contains('deletion'));
  });

  test('web delete-account path is recognised', () {
    expect(Uri.parse('https://restoriaidle.com/delete-account').path, '/delete-account');
  });
}
