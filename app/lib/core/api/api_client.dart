import 'package:dio/dio.dart';

import '../auth/token_store.dart';

/// Error from the API, in its standard shape { error: { code, message } }.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int? status;
  final String code;
  final String message;

  factory ApiException.from(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final err = data is Map ? data['error'] : null;
      if (err is Map) return ApiException(e.response?.statusCode, '${err['code']}', '${err['message']}');
      return ApiException(e.response?.statusCode, 'NETWORK', 'No connection. Check your internet and try again.');
    }
    return ApiException(null, 'UNKNOWN', 'Something went wrong. Try again.');
  }

  @override
  String toString() => message;
}

/// dio with the access token on every call. On a 401 it refreshes once (shared by all calls
/// waiting at that moment) and retries; if refreshing fails, [onSignedOut] runs.
class ApiClient {
  ApiClient({required String baseUrl, required this.tokens, required this.onSignedOut, HttpClientAdapter? adapter})
      : dio = Dio(BaseOptions(baseUrl: '$baseUrl/v1', connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20))) {
    _plain = Dio(dio.options);
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _plain.httpClientAdapter = adapter;
    }
    dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _addToken, onError: _refreshOn401));
  }

  final Dio dio;
  /// No interceptors: used for the refresh call and the retry, so their errors can't wait on the
  /// queued error handler that is waiting for them.
  late final Dio _plain;
  final TokenStore tokens;
  final void Function() onSignedOut;
  Future<bool>? _refreshing;

  Future<void> _addToken(RequestOptions o, RequestInterceptorHandler h) async {
    final t = await tokens.read();
    if (t != null && o.extra['noAuth'] != true) o.headers['authorization'] = 'Bearer ${t.access}';
    h.next(o);
  }

  Future<void> _refreshOn401(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    if (e.response?.statusCode != 401 || o.extra['noAuth'] == true || o.extra['retried'] == true) return h.next(e);
    // Another call may already have refreshed while this one waited in the queue: then just retry.
    final sentWith = o.headers['authorization'];
    final current = await tokens.read();
    final alreadyNew = current != null && sentWith != 'Bearer ${current.access}';
    final ok = alreadyNew || await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    if (!ok) {
      onSignedOut();
      return h.next(e);
    }
    final t = await tokens.read();
    o.headers['authorization'] = 'Bearer ${t!.access}';
    o.extra['retried'] = true;
    try {
      h.resolve(await _plain.fetch(o));
    } on DioException catch (err) {
      h.next(err);
    }
  }

  Future<bool> _refresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final r = await _plain.post('/auth/refresh', data: {'refreshToken': t.refresh});
      await tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
      return true;
    } on DioException {
      await tokens.clear();
      return false;
    }
  }
}
