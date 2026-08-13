/// The Grand Bazaar notice board.
///
/// A post carries no rules — nothing in the game reads one — so it lives with
/// the backend that stores it rather than in `ik_rules`.
library;

import 'moderation.dart';

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

/// As long as a notice may be, which is what every backend stores.
const int bazaarPostMaxLength = 240;

const String bazaarEmptyPost = 'Message is empty.';
const String bazaarUnknownKind = 'Unknown bazaar post kind.';

/// What a notice reads as once it has been accepted, or why it was not.
class PreparedBazaarPost {
  const PreparedBazaarPost.ok(String this.body) : reason = null;

  const PreparedBazaarPost.failed(this.reason) : body = null;

  final String? body;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'body': body}
      : <String, Object?>{'ok': false, 'reason': reason};
}

/// Cleans [body] for the board, or says why it cannot go up.
///
/// Shared because both backends have to agree: a post written against the local
/// board and the same post written against a hosted one should come out the same
/// length, with the same words masked. The cooldown is not decided here, since
/// that needs a clock and a record of the last post.
PreparedBazaarPost prepareBazaarPost(BazaarPostKind kind, String body) {
  final trimmedBody = body.trim();
  final trimmed = trimmedBody.length > bazaarPostMaxLength
      ? trimmedBody.substring(0, bazaarPostMaxLength)
      : trimmedBody;
  if (trimmed.isEmpty) return const PreparedBazaarPost.failed(bazaarEmptyPost);
  if (!bazaarPostKinds.contains(kind)) {
    return const PreparedBazaarPost.failed(bazaarUnknownKind);
  }
  return PreparedBazaarPost.ok(filterProfanity(trimmed));
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
