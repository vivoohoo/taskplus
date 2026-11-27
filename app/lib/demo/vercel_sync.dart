// The demo's shared data on Vercel: /api/state on the same site (see api/state.js at the repo root).
import 'package:dio/dio.dart';

import 'demo_backend.dart';

class VercelSync implements DemoSync {
  VercelSync(this._dio);
  final Dio _dio;

  /// Null when this site has no /api/state (claude.ai, a local copy) or no database is connected.
  static Future<VercelSync?> connect() async {
    final dio = Dio(BaseOptions(baseUrl: Uri.base.resolve('/api/state').toString(), connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10), validateStatus: (s) => s != null && s < 500 && s != 404 && s != 405));
    try {
      final r = await dio.get('');
      return r.statusCode == 200 && r.data is Map ? VercelSync(dio) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({int version, Map<String, dynamic>? data})> get() async {
    final r = (await _dio.get('')).data as Map;
    return (version: (r['version'] as num).toInt(), data: (r['data'] as Map?)?.cast<String, dynamic>());
  }

  @override
  Future<({bool ok, int version, Map<String, dynamic>? data})> put(int version, Map<String, dynamic> data) async {
    final r = await _dio.put('', data: {'version': version, 'data': data});
    final b = r.data as Map;
    return (ok: r.statusCode == 200, version: (b['version'] as num).toInt(), data: (b['data'] as Map?)?.cast<String, dynamic>());
  }

  @override
  Future<void> reset() => _dio.delete('');
}
