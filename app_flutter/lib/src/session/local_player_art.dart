import 'dart:convert';
import 'dart:typed_data';

import 'package:ik_runtime/ik_runtime.dart';

/// Browser-local player sprite override. Never part of the character save.
///
/// Other players keep seeing the bundled gender-presentation art. This device
/// stores the PNG beside the save, under a key the rules never read.
class LocalPlayerArt {
  LocalPlayerArt({this.storage, this._bytes});

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.local-player-png';

  static const int maxBytes = 400 * 1024;

  static const String tooLargeMessage = 'PNG must be 400 KB or smaller.';
  static const String notPngMessage = 'Choose a PNG file.';

  final SaveStorage? storage;
  Uint8List? _bytes;

  Uint8List? get bytes => _bytes;

  bool get hasOverride => _bytes != null;

  factory LocalPlayerArt.load(SaveStorage storage) {
    final encoded = storage.getItem(storageKey);
    if (encoded == null || encoded.isEmpty) {
      return LocalPlayerArt(storage: storage);
    }
    try {
      final bytes = base64Decode(encoded);
      if (!isPngBytes(bytes) || bytes.length > maxBytes) {
        return LocalPlayerArt(storage: storage);
      }
      return LocalPlayerArt(storage: storage, bytes: bytes);
    } on FormatException {
      return LocalPlayerArt(storage: storage);
    }
  }

  /// Keeps [bytes] when they are a PNG under the size cap; otherwise the reason.
  String? setPng(Uint8List bytes) {
    if (bytes.length > maxBytes) return tooLargeMessage;
    if (!isPngBytes(bytes)) return notPngMessage;
    _bytes = Uint8List.fromList(bytes);
    storage?.setItem(storageKey, base64Encode(_bytes!));
    return null;
  }

  void clear() {
    _bytes = null;
    storage?.removeItem(storageKey);
  }
}

/// PNG signature, the eight bytes every PNG starts with.
bool isPngBytes(Uint8List bytes) {
  const header = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < header.length) return false;
  for (var i = 0; i < header.length; i++) {
    if (bytes[i] != header[i]) return false;
  }
  return true;
}
