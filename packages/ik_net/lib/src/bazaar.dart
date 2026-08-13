/// The Grand Bazaar notice board.
///
/// A post carries no rules — nothing in the game reads one — so it lives with
/// the backend that stores it rather than in `ik_rules`.
library;

typedef BazaarPostKind = String;

const String bazaarPostMessage = 'message';
const String bazaarPostRecruit = 'recruit';
const String bazaarPostTrade = 'trade';

const List<BazaarPostKind> bazaarPostKinds = <BazaarPostKind>[
  bazaarPostMessage,
  bazaarPostRecruit,
  bazaarPostTrade,
];

class BazaarPost {
  const BazaarPost({
    required this.id,
    required this.kind,
    required this.userId,
    required this.username,
    required this.body,
    required this.createdAt,
  });

  factory BazaarPost.fromJson(Map<String, Object?> json) => BazaarPost(
    id: json['id']! as String,
    kind: json['kind']! as String,
    userId: json['userId']! as String,
    username: json['username']! as String,
    body: json['body']! as String,
    createdAt: json['createdAt']! as String,
  );

  final String id;
  final BazaarPostKind kind;
  final String userId;
  final String username;
  final String body;
  final String createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'userId': userId,
    'username': username,
    'body': body,
    'createdAt': createdAt,
  };
}
