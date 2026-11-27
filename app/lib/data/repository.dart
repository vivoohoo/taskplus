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

  Future<ThreadSummary> openThread(String targetType, [String? targetId]) => _call(() async => ThreadSummary.fromJson(
      (await _dio.post('/threads/open', data: {'targetType': targetType, 'targetId': ?targetId})).data['thread'] as Map<String, dynamic>));

  /// The chat to write in for a party: a person, a team, a department, or your private notes.
  Future<ThreadSummary> threadFor(String partyKey) {
    if (partyKey == 'self') return openThread('self');
    final id = partyKey.substring(2);
    return openThread(switch (partyKey[0]) { 'u' => 'user', 't' => 'team', _ => 'department' }, id);
  }

  // ---- Ornate's lists, timeline and bell ----
  Future<CaseList> cases(CaseQuery q) => _call(() async {
        final d = (await _dio.get('/cases', queryParameters: q.toQuery())).data as Map<String, dynamic>;
        final s = d['stats'] as Map?;
        return CaseList(
          rows: [for (final r in d['items'] as List) CaseRow.fromJson(r as Map<String, dynamic>)],
          grouped: d['grouped'] == true,
          stats: s == null ? null : (waiting: (s['waiting'] as num).toInt(), inProgress: (s['inProgress'] as num).toInt(), overdue: (s['overdue'] as num).toInt()),
        );
      });
  Future<({int my, int queue, int all})> caseCounts() => _call(() async {
        final d = (await _dio.get('/cases/counts')).data;
        return (my: (d['my'] as num).toInt(), queue: (d['queue'] as num).toInt(), all: (d['all'] as num).toInt());
      });
  Future<({Party? party, List<ChatItem> items})> timeline(String party) => _call(() async {
        final d = (await _dio.get('/timeline', queryParameters: {'party': party})).data;
        return (
          party: d['party'] == null ? null : Party.fromJson(d['party'] as Map<String, dynamic>),
          items: [for (final i in d['items'] as List) ChatItem.fromJson(i as Map<String, dynamic>)],
        );
      });
  Future<({int unread, List<AppNotification> items})> notifications() => _call(() async {
        final d = (await _dio.get('/notifications')).data;
        return (unread: (d['unread'] as num).toInt(), items: [for (final n in d['items'] as List) AppNotification.fromJson(n as Map<String, dynamic>)]);
      });
  Future<void> markNotificationRead(String id) => _call(() => _dio.post('/notifications/$id/read'));
  Future<void> markAllNotificationsRead() => _call(() => _dio.post('/notifications/read-all'));

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
          'replyToTaskId': ?d.replyToTaskId,
          'parentTaskId': ?d.parentTaskId,
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
  /// Any workflow action; `body` carries its reason, question, resolution, department, level or priority.
  Future<Task> action(String taskId, String action, [Map<String, dynamic> body = const {}]) =>
      _task(() => _dio.post('/tasks/$taskId/actions/$action', data: body));

  /// One task with this person's buttons (re-read after a live event).
  /// A task for its case page, with who is on the other side.
  Future<CaseRow> caseOf(String taskId) => _call(() async => CaseRow.fromJson((await _dio.get('/cases/$taskId')).data as Map<String, dynamic>));

  Future<ChatItem> task(String taskId) => _call(() async => ChatItem.fromJson((await _dio.get('/tasks/$taskId')).data as Map<String, dynamic>));

  Future<List<({String id, String name})>> departments() => _call(() async => [
        for (final d in (await _dio.get('/departments')).data['departments'] as List) (id: d['id'] as String, name: d['name'] as String)
      ]);

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

  // ---- people and settings ----
  Future<void> setAway(bool away) => _call(() => _dio.put('/me/away', data: {'away': away}));
  Future<void> setShift(int shift) => _call(() => _dio.put('/me/shift', data: {'shift': shift}));
  Future<Map<String, dynamic>> notificationSettings() => _call(() async => (await _dio.get('/me/notifications')).data as Map<String, dynamic>);
  Future<void> setMuted(List<String> muted) => _call(() => _dio.put('/me/notifications', data: {'muted': muted}));
  Future<List<Map<String, dynamic>>> holidays() => _call(() async => ((await _dio.get('/holidays')).data['holidays'] as List).cast<Map<String, dynamic>>());
  Future<void> addHoliday(String day, String name) => _call(() => _dio.post('/holidays', data: {'day': day, 'name': name}));
  Future<void> removeHoliday(String day) => _call(() => _dio.delete('/holidays/$day'));
  Future<Map<String, dynamic>> suggestions() => _call(() async => (await _dio.get('/suggestions')).data as Map<String, dynamic>);
  Future<void> suggest(String text) => _call(() => _dio.post('/suggestions', data: {'text': text}));
  Future<void> setSuggestionStatus(String id, String status) => _call(() => _dio.put('/suggestions/$id', data: {'status': status}));
  Future<List<String>> customers() => _call(() async => [for (final c in (await _dio.get('/customers')).data['customers'] as List) c['name'] as String]);
  Future<Map<String, dynamic>> history(String taskId) => _call(() async => (await _dio.get('/tasks/$taskId/history')).data as Map<String, dynamic>);
  Future<List<ChatItem>> searchTasks(String q) => _call(() async => [
        for (final i in (await _dio.get('/tasks/search', queryParameters: {'q': q})).data['items'] as List) ChatItem.fromJson(i as Map<String, dynamic>)
      ]);
  Future<Map<String, dynamic>> team() => _call(() async => (await _dio.get('/analytics/team')).data as Map<String, dynamic>);

  Future<void> registerDevice(String token, String platform) =>
      _call(() => _dio.post('/devices', data: {'fcmToken': token, 'platform': platform}));
}
