import 'package:flutter_test/flutter_test.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/token_store.dart';

import 'helpers/fake_api.dart';

void main() {
  test('on 401 refreshes once for parallel calls, then retries them', () async {
    final tokens = MemoryTokenStore();
    await tokens.save('old', 'r1');
    var refreshes = 0;
    final api = FakeApi((method, path, body, headers) {
      if (path == '/auth/refresh') {
        refreshes++;
        return (200, {'accessToken': 'new', 'refreshToken': 'r2'});
      }
      return headers['authorization'] == 'Bearer new' ? (200, {'ok': true}) : (401, {'error': {'code': 'UNAUTHORIZED', 'message': 'Sign in again.'}});
    });
    final client = ApiClient(baseUrl: 'http://x', tokens: tokens, onSignedOut: () {}, adapter: api);

    final results = await Future.wait([client.dio.get('/me'), client.dio.get('/threads')]);
    expect(results.map((r) => r.data['ok']), [true, true]);
    expect(refreshes, 1);
    expect((await tokens.read())!.refresh, 'r2');
  });

  test('signs out when the refresh token is refused', () async {
    final tokens = MemoryTokenStore();
    await tokens.save('old', 'bad');
    var signedOut = false;
    final client = ApiClient(baseUrl: 'http://x', tokens: tokens, onSignedOut: () => signedOut = true,
        adapter: FakeApi((m, p, b, h) => (401, {'error': {'code': 'UNAUTHORIZED', 'message': 'Sign in again.'}})));

    await expectLater(client.dio.get('/me'), throwsA(anything));
    expect(signedOut, isTrue);
    expect(await tokens.read(), isNull);
  });

  test('turns API errors into their message', () {
    expect(ApiException.from(Exception()).message, 'Something went wrong. Try again.');
  });
}
