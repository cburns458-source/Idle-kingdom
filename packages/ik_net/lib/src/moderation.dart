final RegExp _basicProfanity = RegExp(
  r'\b(fuck|shit|asshole|cunt|nigger|faggot)\b',
  caseSensitive: false,
);

final RegExp _slurs = RegExp(r'\b(nigger|faggot)\b', caseSensitive: false);

/// Masks the words the shipped list covers, leaving length intact so the reader
/// can tell something was removed.
///
/// Kept apart from any one backend because a client-side filter and the Bazaar
/// both use it, and a hosted backend has to mask the same words as the local one.
String filterProfanity(String body) =>
    body.replaceAllMapped(_basicProfanity, (match) => '*' * match.group(0)!.length);

/// Slurs are not a display toggle: sending one disables chat for that account.
bool containsSlur(String body) => _slurs.hasMatch(body);

/// What sendChat says after a slur, and on every later send from that account.
const String chatDisabledNotice = 'Chat has been disabled.';
