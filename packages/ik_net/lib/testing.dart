/// Stand-ins a test uses in place of a real backend.
///
/// Kept out of `ik_net.dart` so nothing shipped can reach for them by accident,
/// and shared rather than duplicated so both clients test the remote service
/// against the same idea of what a backend does.
library;

export 'src/fake_transport.dart';
