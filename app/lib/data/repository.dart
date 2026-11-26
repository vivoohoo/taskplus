import 'dart:io';

import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import 'models.dart';

/// Every API call the app makes. Errors come out as [ApiException] with a readable message.
class Repository {
  Repository(this._api, {String Function(String)? absolute}) : _absolute = absolute ?? ((u) => u);
  final ApiClient _api;
  /// Turns a server path (/v1/files/raw/...) into a full address on the current server.
  final String Function(String) _absolute;
  Dio get _dio => _api.dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<ThreadSummary>> threads() => _call(() async =>
      [for (final t in (await _dio.get('/threads')).data['threads'] as List) ThreadSummary.fromJson(t as Map<String, dynamic>)]);

  Future<List<SearchResult>> search(String q) => _call(() async => [
        for (final r in (await _dio.get('/search', queryParameters: {'q': q})).data['results'] as List)
          SearchResult.fromJson(r as Map<String, dynamic>)
      ]);

  Future<ThreadSummary> openThread(String targetType, String targetId) => _call(() async => ThreadSummary.fromJson(
      (await _dio.post('/threads/open', data: {'targetType': targetType, 'targetId': targetId})).data['thread'] as Map<String, dynamic>));

  Future<({List<ChatItem> items, String? nextCursor})> messages(String threadId, {String? before}) => _call(() async {
        final r = await _dio.get('/threads/$threadId/messages', queryParameters: {'limit': 30, 'before': ?before});
        return (
          items: [for (final i in r.data['items'] as List) ChatItem.fromJson(i as Map<String, dynamic>)],
          nextCursor: r.data['nextCursor'] as String?,
        );
      });

  /// Idempotent on clientMsgId: sending again after a timeout never makes a second task.
  Future<ChatItem> send(Draft d, {String? audioKey, List<String> attachmentKeys = const []}) => _call(() async {
        final r = await _dio.post('/threads/${d.threadId}/messages', data: {
          'clientMsgId': d.clientMsgId,
          'kind': d.kind,
          if (d.bodyText != null && d.bodyText!.isNotEmpty) 'bodyText': d.bodyText,
          'audioKey': ?audioKey,
          'audioDurationS': ?d.audioDurationS,
          if (attachmentKeys.isNotEmpty) 'attachmentKeys': attachmentKeys,
          if (d.overrides.isNotEmpty) 'overrides': d.overrides,
          'taggedUserId': ?d.taggedUserId,
        });
        return ChatItem.fromJson(r.data as Map<String, dynamic>);
      });

  /// Presign, then PUT the file straight to storage. Returns the storage key.
  Future<String> upload(String threadId, File file, String mime, String purpose) => _call(() async {
        final size = await file.length();
        final p = (await _dio.post('/uploads/presign', data: {'threadId': threadId, 'mime': mime, 'sizeBytes': size, 'purpose': purpose})).data;
        await Dio().put(_absolute(p['url'] as String),
            data: file.openRead(),
            options: Options(headers: {...(p['headers'] as Map).cast<String, String>(), Headers.contentLengthHeader: size}));
        return p['key'] as String;
      });

  Future<String> fileUrl(String key) => _call(() async => _absolute((await _dio.get('/files/url', queryParameters: {'key': key})).data['url'] as String));

  Future<Task> accept(String taskId) => _task(() => _dio.post('/tasks/$taskId/accept'));
  Future<Task> reassign(String taskId, String assigneeId) => _task(() => _dio.post('/tasks/$taskId/reassign', data: {'assigneeId': assigneeId}));
  Future<Task> cancel(String taskId) => _task(() => _dio.post('/tasks/$taskId/cancel'));
  Future<Task> setStatus(String taskId, String status) => _task(() => _dio.post('/tasks/$taskId/status', data: {'status': status}));
  Future<Task> _task(Future<Response> Function() f) => _call(() async => Task.fromJson((await f()).data['task'] as Map<String, dynamic>));

  Future<({List<ChatItem> items, int? nextCursor})> tasks(String filter, {int cursor = 0}) => _call(() async {
        final r = await _dio.get('/tasks', queryParameters: {'filter': filter, 'cursor': cursor});
        return (
          items: [for (final i in r.data['items'] as List) ChatItem.fromJson(i as Map<String, dynamic>)],
          nextCursor: (r.data['nextCursor'] as num?)?.toInt(),
        );
      });

  Future<({int myPending, int overdue, int sentByMe})> counts() => _call(() async {
        final d = (await _dio.get('/tasks/counts')).data;
        return (myPending: (d['myPending'] as num).toInt(), overdue: (d['overdue'] as num).toInt(), sentByMe: ((d['sentByMe'] as num?) ?? 0).toInt());
      });

  Future<DepartmentInfo> department(String id) =>
      _call(() async => DepartmentInfo.fromJson((await _dio.get('/departments/$id')).data as Map<String, dynamic>));

  Future<Map<String, dynamic>> profile() => _call(() async => (await _dio.get('/me')).data as Map<String, dynamic>);

  Future<void> changePassword(String current, String next) => _call(() => _dio.post('/auth/password', data: {'current': current, 'password': next}));

  Future<void> registerDevice(String token, String platform) =>
      _call(() => _dio.post('/devices', data: {'fcmToken': token, 'platform': platform}));
}
