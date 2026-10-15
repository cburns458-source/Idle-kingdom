import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  group('readChatTitle', () {
    test('keeps a trimmed string and drops empty or junk values', () {
      expect(readChatTitle('The Undying'), 'The Undying');
      expect(readChatTitle('  Sir  '), 'Sir');
      expect(readChatTitle(''), isNull);
      expect(readChatTitle('   '), isNull);
      expect(readChatTitle(null), isNull);
      expect(readChatTitle(12), isNull);
      expect(readChatTitle(true), isNull);
    });

    test('reads a PlayerTitle-shaped map without throwing', () {
      expect(
        readChatTitle(<String, Object?>{'text': 'The Undying', 'placement': 'suffix'}),
        'The Undying',
      );
      expect(readChatTitle(<String, Object?>{'title': 'Sir'}), 'Sir');
      expect(readChatTitle(<String, Object?>{'placement': 'suffix'}), isNull);
    });
  });

  group('chatTitleFromPayload', () {
    test('accepts the keys Game Systems may stamp, in order', () {
      expect(chatTitleFromPayload(<String, Object?>{'title': 'The Undying'}), 'The Undying');
      expect(chatTitleFromPayload(<String, Object?>{'titleText': 'Sir'}), 'Sir');
      expect(chatTitleFromPayload(<String, Object?>{'equipped_title': 'The Slayer'}), 'The Slayer');
      expect(chatTitleFromPayload(<String, Object?>{'senderTitle': '  '}), isNull);
      expect(chatTitleFromPayload(<String, Object?>{'title': 3, 'title_text': 'Sir'}), 'Sir');
    });
  });

  group('chatLineUsername', () {
    const untitled = ChatMessage(
      id: 'msg_1',
      channelKey: 'global',
      userId: 'usr_1',
      username: 'Vari',
      body: 'Hello',
      createdAt: '2026-08-12T21:00:00.000Z',
    );

    test('shows the title before the name, and the name alone when none', () {
      expect(chatLineUsername(untitled), 'Vari');
      expect(
        chatLineUsername(
          const ChatMessage(
            id: 'msg_1',
            channelKey: 'global',
            userId: 'usr_1',
            username: 'Vari',
            body: 'Hello',
            createdAt: '2026-08-12T21:00:00.000Z',
            title: 'The Undying',
          ),
        ),
        'The Undying Vari',
      );
      expect(
        chatLineUsername(
          const ChatMessage(
            id: 'msg_1',
            channelKey: 'global',
            userId: 'usr_1',
            username: 'Vari',
            body: 'Hello',
            createdAt: '2026-08-12T21:00:00.000Z',
            title: 'The Undying',
          ),
          showTitles: false,
        ),
        'Vari',
      );
    });

    test('keeps guild tags and rank marks around the titled name', () {
      expect(
        chatLineUsername(
          ChatMessage(
            id: 'msg_2',
            channelKey: 'global',
            userId: 'usr_1',
            username: 'Vari',
            body: 'Hello',
            createdAt: '2026-08-12T21:00:00.000Z',
            guildTag: 'DEV',
            title: 'The Undying',
          ),
        ),
        '[DEV] The Undying Vari',
      );
      expect(
        chatLineUsername(
          ChatMessage(
            id: 'msg_3',
            channelKey: 'guild:gld_1',
            userId: 'usr_1',
            username: 'Vari',
            body: 'Hello',
            createdAt: '2026-08-12T21:00:00.000Z',
            rankIcon: '★',
            title: 'The Undying',
          ),
        ),
        '★ The Undying Vari',
      );
    });
  });

  test('chatMessageFrom reads a title defensively', () {
    expect(
      chatMessageFrom(<String, Object?>{
        'id': 'msg_1',
        'channel_key': 'global',
        'user_id': 'usr_1',
        'username': 'Mira',
        'body': 'Hold',
        'created_at': '2026-08-12T21:00:00.000Z',
        'title': 'The Undying',
      }).title,
      'The Undying',
    );
    expect(
      chatMessageFromFunction(<String, Object?>{
        'id': 'msg_1',
        'channelKey': 'global',
        'userId': 'usr_1',
        'username': 'Mira',
        'body': 'Hold',
        'createdAt': '2026-08-12T21:00:00.000Z',
        'equippedTitle': <String, Object?>{'text': 'Sir', 'placement': 'prefix'},
      })?.title,
      'Sir',
    );
    expect(
      chatMessageFrom(<String, Object?>{
        'id': 'msg_1',
        'channel_key': 'global',
        'user_id': 'usr_1',
        'username': 'Mira',
        'body': 'Hold',
        'created_at': '2026-08-12T21:00:00.000Z',
        'title': 12,
      }).title,
      isNull,
    );
  });
}
