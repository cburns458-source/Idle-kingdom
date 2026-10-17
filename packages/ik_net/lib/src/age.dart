/// Chat age-gate. Threshold is 13. Age never blocks play.
library;

const int chatAgeThreshold = 13;
const String ageGateCode = 'age_gate';
const String ageGateError = 'Chat is not available for this account.';

const List<String> storeAgeBands = <String>['0-12', '13-15', '16-17', '18+'];

bool isStoreAgeBand(String value) => storeAgeBands.contains(value);

bool storeBandAllowsChat(String band) => band == '13-15' || band == '16-17' || band == '18+';

/// Years old on [asOf]. A missing month is treated as 1 January.
int? accountAgeYears(int? birthYear, int? birthMonth, [DateTime? asOf]) {
  if (birthYear == null) return null;
  final now = asOf ?? DateTime.now().toUtc();
  final month = birthMonth ?? 1;
  final anniversary = DateTime.utc(now.year, month, 1);
  var years = now.year - birthYear;
  if (now.isBefore(anniversary)) years -= 1;
  return years;
}

String ageBandFromYears(int? years) {
  if (years == null) return 'unknown';
  if (years < 13) return '0-12';
  if (years < 16) return '13-15';
  if (years < 18) return '16-17';
  return '18+';
}

bool chatAllowedFromAge({
  required bool answered,
  int? birthYear,
  int? birthMonth,
  String? ageBand,
  DateTime? asOf,
}) {
  if (!answered) return false;
  if (birthYear != null) {
    return (accountAgeYears(birthYear, birthMonth, asOf) ?? 0) >= chatAgeThreshold;
  }
  return storeBandAllowsChat(ageBand ?? '');
}

bool needsBirthMonth(int birthYear, [DateTime? asOf]) {
  final youngest = accountAgeYears(birthYear, 12, asOf);
  final oldest = accountAgeYears(birthYear, 1, asOf);
  if (youngest == null || oldest == null) return true;
  return youngest < chatAgeThreshold + 1 && oldest >= chatAgeThreshold - 1;
}

/// A store-declared range from Apple or Google.
///
/// Client submission of [band] is disabled until there is a server-verifiable
/// source. Only an in-game birth year is accepted from players.
class StoreAgeSignal {
  const StoreAgeSignal({required this.band, required this.platform});

  final String band;
  final String platform;
}

/// Asks the installed store for a declared age range. Unused: clients cannot
/// write `store_signal` until a server-verifiable source exists.
abstract class AgeSignalSource {
  Future<StoreAgeSignal?> requestDeclaredAge();
}

/// Default source: no native plugin is wired, so every platform falls back.
class FallbackAgeSignalSource implements AgeSignalSource {
  const FallbackAgeSignalSource();

  @override
  Future<StoreAgeSignal?> requestDeclaredAge() async => null;
}

/// Social flags the client is allowed to see. Birth dates stay on the server.
class AccountSocialStatus {
  const AccountSocialStatus({
    required this.ageAnswered,
    required this.chatAllowed,
    this.deletionPending = false,
    this.deletionPurgeAt,
  });

  const AccountSocialStatus.playable()
    : ageAnswered = true,
      chatAllowed = true,
      deletionPending = false,
      deletionPurgeAt = null;

  const AccountSocialStatus.unanswered()
    : ageAnswered = false,
      chatAllowed = false,
      deletionPending = false,
      deletionPurgeAt = null;

  final bool ageAnswered;
  final bool chatAllowed;
  final bool deletionPending;
  final DateTime? deletionPurgeAt;

  bool get needsAgeAnswer => !ageAnswered;

  AccountSocialStatus copyWith({
    bool? ageAnswered,
    bool? chatAllowed,
    bool? deletionPending,
    DateTime? deletionPurgeAt,
  }) => AccountSocialStatus(
    ageAnswered: ageAnswered ?? this.ageAnswered,
    chatAllowed: chatAllowed ?? this.chatAllowed,
    deletionPending: deletionPending ?? this.deletionPending,
    deletionPurgeAt: deletionPurgeAt ?? this.deletionPurgeAt,
  );

  factory AccountSocialStatus.fromJson(Map<String, Object?> json) {
    final purge = json['deletion_purge_at'];
    return AccountSocialStatus(
      ageAnswered: json['age_answered'] == true,
      chatAllowed: json['chat_allowed'] == true,
      deletionPending: json['deletion_pending'] == true,
      deletionPurgeAt: purge is String && purge.isNotEmpty ? DateTime.tryParse(purge) : null,
    );
  }
}
