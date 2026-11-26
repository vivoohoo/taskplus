import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers dio requests from a handler: (method, path, json body, headers) -> (status, json).
class FakeApi implements HttpClientAdapter {
  FakeApi(this.handle);
  final (int, Object?) Function(String method, String path, Map<String, dynamic>? body, Map<String, dynamic> headers) handle;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Map<String, dynamic>? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((b) => b).toList();
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    final path = o.path.startsWith('http') ? Uri.parse(o.path).path : o.path;
    calls.add('${o.method} $path');
    final (status, json) = handle(o.method, path.replaceFirst('/v1', ''), body, o.headers);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}
