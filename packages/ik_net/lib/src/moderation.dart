final RegExp _basicProfanity = RegExp(
  r'\b(fuck|shit|asshole|cunt|nigger|faggot)\b',
  caseSensitive: false,
);

/// Masks the words the shipped list covers, leaving length intact so the reader
/// can tell something was removed.
///
/// Kept apart from any one backend because everything a player writes goes
/// through it — chat, Bazaar notices — and a hosted backend has to mask the same
/// words as the local one.
String filterProfanity(String body) =>
    body.replaceAllMapped(_basicProfanity, (match) => '*' * match.group(0)!.length);
