import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  test('keeps a project origin unchanged', () {
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co'),
      'https://abcd.supabase.co',
    );
  });

  test('strips the REST and Auth suffixes the dashboard copies', () {
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/rest/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/rest/v1/'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/auth/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/functions/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/storage/v1'),
      'https://abcd.supabase.co',
    );
  });

  test('explains the PostgREST invalid-path error', () {
    expect(
      friendlyRemoteError('Invalid path specified in request URL'),
      remoteInvalidBackendUrl,
    );
    expect(friendlyRemoteError('Invalid login credentials'), 'Invalid login credentials');
  });

  test('rejects a URL that is only a suffix after trim', () {
    expect(RemoteBackendConfig.from(url: '  ', anonKey: 'key'), isNull);
    expect(
      RemoteBackendConfig.from(url: 'https://abcd.supabase.co/rest/v1', anonKey: 'key')?.url,
      'https://abcd.supabase.co',
    );
  });
}
