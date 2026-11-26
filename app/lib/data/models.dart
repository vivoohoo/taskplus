/// API shapes (server/src/modules/dto.ts). Parsing only; no logic beyond small helpers.
class Attachment {
  Attachment({required this.key, required this.mime, required this.sizeBytes});
  final String key;
  final String mime;
  final int sizeBytes;
  bool get isImage => mime.startsWith('image/');
  factory Attachment.fromJson(Map<String, dynamic> j) =>
      Attachment(key: j['key'] as String, mime: j['mime'] as String, sizeBytes: (j['sizeBytes'] as num).toInt());
}

class Message {
  Message({
    required this.id, required this.threadId, required this.senderId, required this.clientMsgId, required this.kind,
    this.bodyText, this.audioKey, this.audioDurationS, this.transcript, this.attachments = const [], required this.createdAt, this.replyToTaskId,
  });
  final String id, threadId, senderId, clientMsgId, kind;
  final String? bodyText, audioKey, transcript;
  /// An answer or comment on an existing task (no task of its own).
  final String? replyToTaskId;
  final int? audioDurationS;
  final List<Attachment> attachments;
  final DateTime createdAt;

  Message copyWith({String? transcript}) => Message(
      id: id, threadId: threadId, senderId: senderId, clientMsgId: clientMsgId, kind: kind, bodyText: bodyText,
      audioKey: audioKey, audioDurationS: audioDurationS, transcript: transcript ?? this.transcript, attachments: attachments, createdAt: createdAt,
      replyToTaskId: replyToTaskId);

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        threadId: j['threadId'] as String,
        senderId: j['senderId'] as String,
        clientMsgId: j['clientMsgId'] as String,
        kind: j['kind'] as String,
        bodyText: j['bodyText'] as String?,
        audioKey: j['audioKey'] as String?,
        audioDurationS: (j['audioDurationS'] as num?)?.toInt(),
        transcript: j['transcript'] as String?,
        attachments: [for (final a in (j['attachments'] as List? ?? [])) Attachment.fromJson(a as Map<String, dynamic>)],
        createdAt: DateTime.parse(j['createdAt'] as String),
        replyToTaskId: j['replyToTaskId'] as String?,
      );
}

class Task {
  Task({
    required this.id, required this.messageId, required this.threadId, required this.priority, required this.status,
    required this.aiStatus, this.dueAt, required this.updatedAt,
    this.subject, this.module, this.customerName, this.customerPhone, this.customerLocation, this.licenseNo, this.details,
    this.assigneeId, this.taggedUserId, this.departmentId, this.aiError, this.warnings = const [], this.closedAt,
    this.actions = const [], this.clockState = 'not started', this.usedMs = 0, this.escalationLevel, this.resolution, this.customerInformed,
    this.reassignRequestedBy, this.requestKind,
  });
  /// The buttons this viewer gets (decided by the server).
  final List<String> actions;
  final String clockState;
  final int usedMs;
  final String? escalationLevel, resolution, customerInformed, reassignRequestedBy, requestKind;
  final String id, messageId, threadId, priority, status, aiStatus;
  final String? subject, module, customerName, customerPhone, customerLocation, licenseNo, details;
  final String? assigneeId, taggedUserId, departmentId, aiError;
  final List<String> warnings;
  /// Null while the clock is paused (waiting or blocked).
  final DateTime? dueAt;
  final DateTime updatedAt;
  final DateTime? closedAt;

  bool isOverdue(DateTime now) => !const ['Closed', 'Completed', 'Verified', 'Rejected', 'Transferred', 'Cancelled'].contains(status) && dueAt != null && dueAt!.isBefore(now);
  bool hasWarning(String field) => warnings.any((w) => w.startsWith('$field:'));

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        messageId: j['messageId'] as String,
        threadId: j['threadId'] as String,
        priority: j['priority'] as String,
        status: j['status'] as String,
        aiStatus: j['aiStatus'] as String,
        dueAt: j['dueAt'] == null ? null : DateTime.parse(j['dueAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        subject: j['subject'] as String?,
        module: j['module'] as String?,
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        customerLocation: j['customerLocation'] as String?,
        licenseNo: j['licenseNo'] as String?,
        details: j['details'] as String?,
        assigneeId: j['assigneeId'] as String?,
        taggedUserId: j['taggedUserId'] as String?,
        departmentId: j['departmentId'] as String?,
        aiError: j['aiError'] as String?,
        warnings: [for (final w in (j['warnings'] as List? ?? [])) w as String],
        closedAt: j['closedAt'] == null ? null : DateTime.parse(j['closedAt'] as String),
        actions: [for (final a in (j['actions'] as List? ?? [])) a as String],
        clockState: (j['clock'] as Map?)?['state'] as String? ?? 'not started',
        usedMs: ((j['clock'] as Map?)?['usedMs'] as num?)?.toInt() ?? 0,
        escalationLevel: j['escalationLevel'] as String?,
        resolution: j['resolution'] as String?,
        customerInformed: j['customerInformed'] as String?,
        reassignRequestedBy: j['reassignRequestedBy'] as String?,
        requestKind: (j['request'] as Map?)?['kind'] as String?,
      );

  /// Events can arrive late or twice: keep whichever version is newest.
  static Task newest(Task? a, Task b) => a == null || !b.updatedAt.isBefore(a.updatedAt) ? (b.actions.isEmpty && a != null && !b.updatedAt.isAfter(a.updatedAt) ? a : b) : a;
}

class ChatItem {
  ChatItem({required this.message, this.task, this.pending = false, this.failed = false});
  final Message message;
  final Task? task;
  /// Still in the outbox, not yet confirmed by the server.
  final bool pending;
  final bool failed;
  factory ChatItem.fromJson(Map<String, dynamic> j) => ChatItem(
        message: Message.fromJson(j['message'] as Map<String, dynamic>),
        task: j['task'] == null ? null : Task.fromJson(j['task'] as Map<String, dynamic>),
      );
}

class ThreadSummary {
  ThreadSummary({required this.id, required this.type, required this.title, this.subtitle, this.departmentId,
      this.requesterId, this.lastText, this.lastAt, this.openTasks = 0});
  final String id, type, title;
  final String? subtitle, departmentId, requesterId, lastText;
  final DateTime? lastAt;
  final int openTasks;
  bool get isDepartment => type == 'department';
  factory ThreadSummary.fromJson(Map<String, dynamic> j) {
    final last = j['lastMessage'] as Map<String, dynamic>?;
    return ThreadSummary(
      id: j['id'] as String,
      type: j['type'] as String,
      title: j['title'] as String,
      subtitle: j['subtitle'] as String?,
      departmentId: j['departmentId'] as String?,
      requesterId: j['requesterId'] as String?,
      lastText: last == null ? null : (last['text'] as String?) ?? (last['kind'] == 'voice' ? 'Voice note' : 'Attachment'),
      lastAt: j['lastMessageAt'] == null ? null : DateTime.parse(j['lastMessageAt'] as String),
      openTasks: (j['openTasks'] as num?)?.toInt() ?? 0,
    );
  }
}

class SearchResult {
  SearchResult({required this.type, required this.id, required this.name, this.subtitle});
  final String type, id, name;
  final String? subtitle;
  factory SearchResult.fromJson(Map<String, dynamic> j) =>
      SearchResult(type: j['type'] as String, id: j['id'] as String, name: j['name'] as String, subtitle: j['subtitle'] as String?);
}

class Member {
  Member({required this.id, required this.name, required this.role});
  final String id, name, role;
  factory Member.fromJson(Map<String, dynamic> j) => Member(id: j['id'] as String, name: j['name'] as String, role: j['role'] as String);
}

class DepartmentInfo {
  DepartmentInfo({required this.id, required this.name, required this.modules, required this.members, this.headUserId});
  final String id, name;
  final String? headUserId;
  final List<String> modules;
  final List<Member> members;
  factory DepartmentInfo.fromJson(Map<String, dynamic> j) => DepartmentInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        headUserId: j['headUserId'] as String?,
        modules: [for (final m in j['modules'] as List) m as String],
        members: [for (final m in j['members'] as List) Member.fromJson(m as Map<String, dynamic>)],
      );
}

/// What the sender typed or recorded, before the server knows about it.
class Draft {
  Draft({required this.clientMsgId, required this.threadId, required this.kind, this.bodyText, this.audioPath,
      this.audioDurationS, this.attachmentPaths = const [], this.overrides = const {}, this.taggedUserId, this.replyToTaskId});
  final String clientMsgId, threadId, kind;
  final String? bodyText, audioPath, taggedUserId, replyToTaskId;
  final int? audioDurationS;
  final List<String> attachmentPaths;
  final Map<String, String> overrides;
}
