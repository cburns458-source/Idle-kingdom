/// Conversions used by the generated save models.
///
/// Deliberately strict: a save that reaches these helpers has already been
/// migrated, so a wrong shape is a bug worth surfacing rather than papering over.
Map<String, Object?> asJsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Expected a JSON object, got ${value.runtimeType}');
}

/// Converts a nullable nested object, keeping null as null.
T? mapOrNull<T>(Object? value, T Function(Map<String, Object?> json) fromJson) {
  if (value == null) return null;
  return fromJson(asJsonMap(value));
}

List<T> listOf<T>(Object? value, T Function(Object? entry) convert) {
  if (value is! List) {
    throw FormatException('Expected a JSON array, got ${value.runtimeType}');
  }
  return value.map(convert).toList();
}

Map<String, T> mapOf<T>(Object? value, T Function(Object? value) convert) {
  final source = asJsonMap(value);
  return <String, T>{for (final entry in source.entries) entry.key: convert(entry.value)};
}
