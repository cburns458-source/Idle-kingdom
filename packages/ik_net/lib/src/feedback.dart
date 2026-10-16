/// In-game report / suggestion (ADM-04). Shared limits and validation for the
/// form, the fake transport, and the hosted submit-feedback function.
library;

/// Bug, suggestion, or a player report that also writes `chat_reports`.
const String feedbackKindBug = 'bug';
const String feedbackKindSuggestion = 'suggestion';
const String feedbackKindPlayer = 'player';

const List<String> feedbackKinds = <String>[
  feedbackKindBug,
  feedbackKindSuggestion,
  feedbackKindPlayer,
];

const String feedbackKindLabelBug = 'Bug';
const String feedbackKindLabelSuggestion = 'Suggestion';
const String feedbackKindLabelPlayer = 'Player';

/// `chat_cooldowns.channel_key` reused for feedback.
const String feedbackCooldownChannelKey = 'feedback';

const int feedbackTitleMinLength = 5;
const int feedbackTitleMaxLength = 80;
const int feedbackBodyMinLength = 10;
const int feedbackBodyMaxLength = 1000;

const int feedbackCooldownMs = 60000;
const int feedbackDailyCap = 5;
const int feedbackDailyWindowMs = 86400000;
const int feedbackGlobalPerMinute = 20;
const int feedbackContextMaxBytes = 2048;

const String feedbackSignInRequired = 'Sign in to send feedback.';
const String feedbackCooldownMessage = 'Slow down a moment before sending again.';
const String feedbackDailyCapMessage = 'You have sent enough reports today.';
const String feedbackUnknownKind = 'Choose Bug, Suggestion, or Player.';
const String feedbackPlayerMissing = 'Enter the player to report.';
const String feedbackSendFailed = 'Could not send that report.';

const String feedbackCodeCooldown = 'cooldown';
const String feedbackCodeDailyCap = 'daily_cap';

/// Context keys the client may send. Anything else is dropped server-side.
const Set<String> feedbackContextKeys = <String>{'build', 'platform', 'gameArea'};

class FeedbackRequest {
  const FeedbackRequest({
    required this.kind,
    required this.title,
    required this.body,
    this.targetUsername,
    this.reportReason,
    this.build,
    this.platform,
    this.gameArea,
  });

  final String kind;
  final String title;
  final String body;
  final String? targetUsername;
  final String? reportReason;
  final String? build;
  final String? platform;
  final String? gameArea;

  Map<String, Object?> toInvokeBody() => <String, Object?>{
    'kind': kind,
    'title': title,
    'body': body,
    if (targetUsername != null && targetUsername!.trim().isNotEmpty)
      'targetUsername': targetUsername!.trim(),
    if (reportReason != null && reportReason!.trim().isNotEmpty) 'reportReason': reportReason,
    'context': <String, Object?>{
      if (build != null && build!.trim().isNotEmpty) 'build': build!.trim(),
      if (platform != null && platform!.trim().isNotEmpty) 'platform': platform!.trim(),
      if (gameArea != null && gameArea!.trim().isNotEmpty) 'gameArea': gameArea!.trim(),
    },
  };
}

class FeedbackSubmitResult {
  const FeedbackSubmitResult.ok(this.id) : reason = null, retryAfterSeconds = null, code = null;

  const FeedbackSubmitResult.failed(this.reason, {this.retryAfterSeconds, this.code}) : id = null;

  final String? id;
  final String? reason;
  final int? retryAfterSeconds;
  final String? code;

  bool get ok => reason == null && id != null;
}

/// Trimmed title, or an error the form can show.
String? feedbackTitleError(String raw) {
  final title = raw.trim();
  if (title.length < feedbackTitleMinLength) return 'Summary is too short.';
  if (title.length > feedbackTitleMaxLength) return 'Summary is too long.';
  return null;
}

String? feedbackBodyError(String raw) {
  final body = raw.trim();
  if (body.length < feedbackBodyMinLength) return 'Details are too short.';
  if (body.length > feedbackBodyMaxLength) return 'Details are too long.';
  return null;
}

String? feedbackKindError(String raw) {
  if (feedbackKinds.contains(raw)) return null;
  return feedbackUnknownKind;
}

String? feedbackPlayerTargetError(String kind, String? targetUsername) {
  if (kind != feedbackKindPlayer) return null;
  final name = targetUsername?.trim() ?? '';
  if (name.length < 2) return feedbackPlayerMissing;
  if (name.length > 24) return 'That name is too long.';
  return null;
}

/// Client-side refusal before the wire, or null when the request may be sent.
String? feedbackRequestError(FeedbackRequest request) {
  return feedbackKindError(request.kind) ??
      feedbackTitleError(request.title) ??
      feedbackBodyError(request.body) ??
      feedbackPlayerTargetError(request.kind, request.targetUsername);
}

/// Stable hash input for dedupe. The hosted function SHA-256s this string.
String feedbackBodyHashInput(String kind, String title, String body, [String? targetUsername]) {
  final target = targetUsername?.trim().toLowerCase() ?? '';
  return '$kind\n${title.trim()}\n${body.trim()}${target.isEmpty ? '' : '\n$target'}';
}

String feedbackKindLabel(String kind) => switch (kind) {
  feedbackKindBug => feedbackKindLabelBug,
  feedbackKindSuggestion => feedbackKindLabelSuggestion,
  feedbackKindPlayer => feedbackKindLabelPlayer,
  _ => 'Other',
};

/// Send-button label while a cooldown or daily cap is running.
String feedbackSendLabel(int? retryAfterSeconds) {
  final seconds = retryAfterSeconds ?? 0;
  if (seconds <= 0) return 'Send';
  if (seconds < 60) return 'Send in ${seconds}s';
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return 'Send in ${minutes}m';
  final hours = (minutes / 60).ceil();
  return 'Send in ${hours}h';
}

FeedbackSubmitResult feedbackResultFromInvoke(Map<String, Object?>? data, String? reason) {
  if (reason != null && reason.isNotEmpty) {
    return FeedbackSubmitResult.failed(reason);
  }
  if (data == null) return const FeedbackSubmitResult.failed(feedbackSendFailed);
  final error = data['error'];
  if (error is String && error.isNotEmpty) {
    final retry = data['retryAfterSeconds'];
    final code = data['code'];
    return FeedbackSubmitResult.failed(
      error,
      retryAfterSeconds: retry is num ? retry.round() : null,
      code: code is String ? code : null,
    );
  }
  final id = data['id'];
  if (id is String && id.isNotEmpty) return FeedbackSubmitResult.ok(id);
  return const FeedbackSubmitResult.failed(feedbackSendFailed);
}
