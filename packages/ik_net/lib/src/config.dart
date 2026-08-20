/// Chat cooldown seconds per channel kind, enforced server-side when remote.
class ChatCooldownSeconds {
  const ChatCooldownSeconds._();

  static const num global = 30;
  static const num local = 10;
  static const num guild = 5;
  static const num dm = 2;
}

/// Heartbeat window: a presence row newer than this is Online.
const num presenceTtlSeconds = 120;

/// How long a closed-client presence stays visible as Away on Nearby.
const num presenceAwayTtlSeconds = 24 * 60 * 60;

/// Supabase project credentials. Absent means the local backend is in use.
class RemoteBackendConfig {
  const RemoteBackendConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  /// Both halves have to be present; a URL without a key cannot sign anyone in.
  static RemoteBackendConfig? from({String? url, String? anonKey}) {
    final cleanUrl = normalizeRemoteBackendUrl(url);
    final cleanKey = (anonKey ?? '').trim();
    if (cleanUrl.isEmpty || cleanKey.isEmpty) return null;
    return RemoteBackendConfig(url: cleanUrl, anonKey: cleanKey);
  }
}

/// Project origin only. Dashboard "API URL" values that include `/rest/v1` or
/// `/auth/v1` make every client call a doubled path and Auth returns
/// "Invalid path specified in request URL".
String normalizeRemoteBackendUrl(String? url) {
  var clean = (url ?? '').trim();
  if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
  const suffixes = <String>['/rest/v1', '/auth/v1', '/functions/v1', '/storage/v1'];
  for (final suffix in suffixes) {
    if (clean.toLowerCase().endsWith(suffix)) {
      clean = clean.substring(0, clean.length - suffix.length);
      if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
      break;
    }
  }
  return clean;
}
