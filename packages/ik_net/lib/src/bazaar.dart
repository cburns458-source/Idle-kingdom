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

const String bazaarBlurb = 'Market board for messages, recruitment, and trade notices.';
const String bazaarSignInNotice = 'Sign in to post.';
const String bazaarPlaceholder = 'Write a short notice…';

/// As long as a post can be, matching what the backend accepts.
const int bazaarBodyMaxLength = 240;

class BazaarKindOption {
  const BazaarKindOption({required this.kind, required this.label});

  final BazaarPostKind kind;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'label': label};
}

List<BazaarKindOption> bazaarKindOptions() => const <BazaarKindOption>[
  BazaarKindOption(kind: bazaarPostMessage, label: 'Message'),
  BazaarKindOption(kind: bazaarPostRecruit, label: 'Recruit'),
  BazaarKindOption(kind: bazaarPostTrade, label: 'Trade'),
];

/// One notice on the board.
class BazaarRowView {
  const BazaarRowView({required this.postId, required this.heading, required this.body});

  final String postId;

  /// `Rowan · trade`.
  final String heading;
  final String body;

  Map<String, Object?> toJson() => <String, Object?>{
    'postId': postId,
    'heading': heading,
    'body': body,
  };
}

/// The board newest first.
///
/// The backend hands posts back oldest first, which is the order a chat log
/// wants; a notice board reads the other way round.
List<BazaarRowView> bazaarRows(List<BazaarPost> posts) => posts.reversed
    .map(
      (post) => BazaarRowView(
        postId: post.id,
        heading: '${post.username} · ${post.kind}',
        body: post.body,
      ),
    )
    .toList();

const String bazaarEmptyHeading = 'Quiet for now';
const String bazaarEmptyBody = 'Be the first to post.';

const String bazaarPostedNotice = 'Posted to the Grand Bazaar.';
