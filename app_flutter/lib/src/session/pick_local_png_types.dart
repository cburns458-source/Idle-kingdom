import 'dart:typed_data';

/// Outcome of the file picker: bytes, a refusal, or the player walking away.
class PickedLocalPng {
  const PickedLocalPng.ok(Uint8List this.bytes) : error = null;

  const PickedLocalPng.failed(String this.error) : bytes = null;

  const PickedLocalPng.cancelled() : bytes = null, error = null;

  const PickedLocalPng.unavailable()
    : bytes = null,
      error = 'PNG upload is available in the web client.';

  final Uint8List? bytes;
  final String? error;
}
