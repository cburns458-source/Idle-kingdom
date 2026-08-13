/// Chat cooldown seconds per channel kind, enforced server-side when remote.
class ChatCooldownSeconds {
  const ChatCooldownSeconds._();

  static const num global = 30;
  static const num local = 10;
  static const num guild = 5;
  static const num dm = 2;
}

const num presenceTtlSeconds = 120;

/// Supabase project credentials. Absent means the local backend is in use.
class RemoteBackendConfig {
  const RemoteBackendConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  /// Both halves have to be present; a URL without a key cannot sign anyone in.
  static RemoteBackendConfig? from({String? url, String? anonKey}) {
    final cleanUrl = (url ?? '').trim();
    final cleanKey = (anonKey ?? '').trim();
    if (cleanUrl.isEmpty || cleanKey.isEmpty) return null;
    return RemoteBackendConfig(url: cleanUrl, anonKey: cleanKey);
  }
}
