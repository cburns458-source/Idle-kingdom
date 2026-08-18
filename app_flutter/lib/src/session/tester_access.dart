/// Shared tester passkey for the closed test launch.
///
/// Empty means the gate is off. Change the string to rotate the key; devices
/// that unlocked the old one have to enter the new one. This is only a latch
/// in the client — it keeps casual visitors out, not a determined reader of
/// the web build.
const String testerPasskey = 'restoria-testers';

/// Where this device notes that the current passkey was accepted.
const String testerAccessStorageKey = 'idle-kingdoms.client.tester-access';

/// True while a passkey is configured and this device has not entered it.
bool testerPasskeyRequired(String? stored) => testerPasskey.isNotEmpty && stored != testerPasskey;

bool matchesTesterPasskey(String raw) => raw.trim().toLowerCase() == testerPasskey.toLowerCase();
