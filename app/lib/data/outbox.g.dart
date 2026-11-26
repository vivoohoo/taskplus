// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox.dart';

// ignore_for_file: type=lint
class $OutboxRowsTable extends OutboxRows
    with TableInfo<$OutboxRowsTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientMsgIdMeta = const VerificationMeta(
    'clientMsgId',
  );
  @override
  late final GeneratedColumn<String> clientMsgId = GeneratedColumn<String>(
    'client_msg_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyTextMeta = const VerificationMeta(
    'bodyText',
  );
  @override
  late final GeneratedColumn<String> bodyText = GeneratedColumn<String>(
    'body_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioDurationSMeta = const VerificationMeta(
    'audioDurationS',
  );
  @override
  late final GeneratedColumn<int> audioDurationS = GeneratedColumn<int>(
    'audio_duration_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentPathsMeta = const VerificationMeta(
    'attachmentPaths',
  );
  @override
  late final GeneratedColumn<String> attachmentPaths = GeneratedColumn<String>(
    'attachment_paths',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _overridesMeta = const VerificationMeta(
    'overrides',
  );
  @override
  late final GeneratedColumn<String> overrides = GeneratedColumn<String>(
    'overrides',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _taggedUserIdMeta = const VerificationMeta(
    'taggedUserId',
  );
  @override
  late final GeneratedColumn<String> taggedUserId = GeneratedColumn<String>(
    'tagged_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioKeyMeta = const VerificationMeta(
    'audioKey',
  );
  @override
  late final GeneratedColumn<String> audioKey = GeneratedColumn<String>(
    'audio_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentKeysMeta = const VerificationMeta(
    'attachmentKeys',
  );
  @override
  late final GeneratedColumn<String> attachmentKeys = GeneratedColumn<String>(
    'attachment_keys',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientMsgId,
    threadId,
    kind,
    bodyText,
    audioPath,
    audioDurationS,
    attachmentPaths,
    overrides,
    taggedUserId,
    audioKey,
    attachmentKeys,
    status,
    error,
    attempts,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_msg_id')) {
      context.handle(
        _clientMsgIdMeta,
        clientMsgId.isAcceptableOrUnknown(
          data['client_msg_id']!,
          _clientMsgIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientMsgIdMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('body_text')) {
      context.handle(
        _bodyTextMeta,
        bodyText.isAcceptableOrUnknown(data['body_text']!, _bodyTextMeta),
      );
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('audio_duration_s')) {
      context.handle(
        _audioDurationSMeta,
        audioDurationS.isAcceptableOrUnknown(
          data['audio_duration_s']!,
          _audioDurationSMeta,
        ),
      );
    }
    if (data.containsKey('attachment_paths')) {
      context.handle(
        _attachmentPathsMeta,
        attachmentPaths.isAcceptableOrUnknown(
          data['attachment_paths']!,
          _attachmentPathsMeta,
        ),
      );
    }
    if (data.containsKey('overrides')) {
      context.handle(
        _overridesMeta,
        overrides.isAcceptableOrUnknown(data['overrides']!, _overridesMeta),
      );
    }
    if (data.containsKey('tagged_user_id')) {
      context.handle(
        _taggedUserIdMeta,
        taggedUserId.isAcceptableOrUnknown(
          data['tagged_user_id']!,
          _taggedUserIdMeta,
        ),
      );
    }
    if (data.containsKey('audio_key')) {
      context.handle(
        _audioKeyMeta,
        audioKey.isAcceptableOrUnknown(data['audio_key']!, _audioKeyMeta),
      );
    }
    if (data.containsKey('attachment_keys')) {
      context.handle(
        _attachmentKeysMeta,
        attachmentKeys.isAcceptableOrUnknown(
          data['attachment_keys']!,
          _attachmentKeysMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientMsgId};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      clientMsgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_msg_id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      bodyText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_text'],
      ),
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      audioDurationS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_duration_s'],
      ),
      attachmentPaths: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_paths'],
      )!,
      overrides: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overrides'],
      )!,
      taggedUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tagged_user_id'],
      ),
      audioKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_key'],
      ),
      attachmentKeys: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_keys'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxRowsTable createAlias(String alias) {
    return $OutboxRowsTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final String clientMsgId;
  final String threadId;
  final String kind;
  final String? bodyText;
  final String? audioPath;
  final int? audioDurationS;
  final String attachmentPaths;
  final String overrides;
  final String? taggedUserId;

  /// Storage keys of files already uploaded, so a retry doesn't upload again.
  final String? audioKey;
  final String attachmentKeys;

  /// queued | failed (the server refused it; shown with a retry option)
  final String status;
  final String? error;
  final int attempts;
  final DateTime createdAt;
  const OutboxRow({
    required this.clientMsgId,
    required this.threadId,
    required this.kind,
    this.bodyText,
    this.audioPath,
    this.audioDurationS,
    required this.attachmentPaths,
    required this.overrides,
    this.taggedUserId,
    this.audioKey,
    required this.attachmentKeys,
    required this.status,
    this.error,
    required this.attempts,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_msg_id'] = Variable<String>(clientMsgId);
    map['thread_id'] = Variable<String>(threadId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || bodyText != null) {
      map['body_text'] = Variable<String>(bodyText);
    }
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    if (!nullToAbsent || audioDurationS != null) {
      map['audio_duration_s'] = Variable<int>(audioDurationS);
    }
    map['attachment_paths'] = Variable<String>(attachmentPaths);
    map['overrides'] = Variable<String>(overrides);
    if (!nullToAbsent || taggedUserId != null) {
      map['tagged_user_id'] = Variable<String>(taggedUserId);
    }
    if (!nullToAbsent || audioKey != null) {
      map['audio_key'] = Variable<String>(audioKey);
    }
    map['attachment_keys'] = Variable<String>(attachmentKeys);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['attempts'] = Variable<int>(attempts);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return OutboxRowsCompanion(
      clientMsgId: Value(clientMsgId),
      threadId: Value(threadId),
      kind: Value(kind),
      bodyText: bodyText == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyText),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      audioDurationS: audioDurationS == null && nullToAbsent
          ? const Value.absent()
          : Value(audioDurationS),
      attachmentPaths: Value(attachmentPaths),
      overrides: Value(overrides),
      taggedUserId: taggedUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(taggedUserId),
      audioKey: audioKey == null && nullToAbsent
          ? const Value.absent()
          : Value(audioKey),
      attachmentKeys: Value(attachmentKeys),
      status: Value(status),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      attempts: Value(attempts),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      clientMsgId: serializer.fromJson<String>(json['clientMsgId']),
      threadId: serializer.fromJson<String>(json['threadId']),
      kind: serializer.fromJson<String>(json['kind']),
      bodyText: serializer.fromJson<String?>(json['bodyText']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      audioDurationS: serializer.fromJson<int?>(json['audioDurationS']),
      attachmentPaths: serializer.fromJson<String>(json['attachmentPaths']),
      overrides: serializer.fromJson<String>(json['overrides']),
      taggedUserId: serializer.fromJson<String?>(json['taggedUserId']),
      audioKey: serializer.fromJson<String?>(json['audioKey']),
      attachmentKeys: serializer.fromJson<String>(json['attachmentKeys']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String?>(json['error']),
      attempts: serializer.fromJson<int>(json['attempts']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientMsgId': serializer.toJson<String>(clientMsgId),
      'threadId': serializer.toJson<String>(threadId),
      'kind': serializer.toJson<String>(kind),
      'bodyText': serializer.toJson<String?>(bodyText),
      'audioPath': serializer.toJson<String?>(audioPath),
      'audioDurationS': serializer.toJson<int?>(audioDurationS),
      'attachmentPaths': serializer.toJson<String>(attachmentPaths),
      'overrides': serializer.toJson<String>(overrides),
      'taggedUserId': serializer.toJson<String?>(taggedUserId),
      'audioKey': serializer.toJson<String?>(audioKey),
      'attachmentKeys': serializer.toJson<String>(attachmentKeys),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String?>(error),
      'attempts': serializer.toJson<int>(attempts),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxRow copyWith({
    String? clientMsgId,
    String? threadId,
    String? kind,
    Value<String?> bodyText = const Value.absent(),
    Value<String?> audioPath = const Value.absent(),
    Value<int?> audioDurationS = const Value.absent(),
    String? attachmentPaths,
    String? overrides,
    Value<String?> taggedUserId = const Value.absent(),
    Value<String?> audioKey = const Value.absent(),
    String? attachmentKeys,
    String? status,
    Value<String?> error = const Value.absent(),
    int? attempts,
    DateTime? createdAt,
  }) => OutboxRow(
    clientMsgId: clientMsgId ?? this.clientMsgId,
    threadId: threadId ?? this.threadId,
    kind: kind ?? this.kind,
    bodyText: bodyText.present ? bodyText.value : this.bodyText,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    audioDurationS: audioDurationS.present
        ? audioDurationS.value
        : this.audioDurationS,
    attachmentPaths: attachmentPaths ?? this.attachmentPaths,
    overrides: overrides ?? this.overrides,
    taggedUserId: taggedUserId.present ? taggedUserId.value : this.taggedUserId,
    audioKey: audioKey.present ? audioKey.value : this.audioKey,
    attachmentKeys: attachmentKeys ?? this.attachmentKeys,
    status: status ?? this.status,
    error: error.present ? error.value : this.error,
    attempts: attempts ?? this.attempts,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxRow copyWithCompanion(OutboxRowsCompanion data) {
    return OutboxRow(
      clientMsgId: data.clientMsgId.present
          ? data.clientMsgId.value
          : this.clientMsgId,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      kind: data.kind.present ? data.kind.value : this.kind,
      bodyText: data.bodyText.present ? data.bodyText.value : this.bodyText,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      audioDurationS: data.audioDurationS.present
          ? data.audioDurationS.value
          : this.audioDurationS,
      attachmentPaths: data.attachmentPaths.present
          ? data.attachmentPaths.value
          : this.attachmentPaths,
      overrides: data.overrides.present ? data.overrides.value : this.overrides,
      taggedUserId: data.taggedUserId.present
          ? data.taggedUserId.value
          : this.taggedUserId,
      audioKey: data.audioKey.present ? data.audioKey.value : this.audioKey,
      attachmentKeys: data.attachmentKeys.present
          ? data.attachmentKeys.value
          : this.attachmentKeys,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('threadId: $threadId, ')
          ..write('kind: $kind, ')
          ..write('bodyText: $bodyText, ')
          ..write('audioPath: $audioPath, ')
          ..write('audioDurationS: $audioDurationS, ')
          ..write('attachmentPaths: $attachmentPaths, ')
          ..write('overrides: $overrides, ')
          ..write('taggedUserId: $taggedUserId, ')
          ..write('audioKey: $audioKey, ')
          ..write('attachmentKeys: $attachmentKeys, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientMsgId,
    threadId,
    kind,
    bodyText,
    audioPath,
    audioDurationS,
    attachmentPaths,
    overrides,
    taggedUserId,
    audioKey,
    attachmentKeys,
    status,
    error,
    attempts,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.clientMsgId == this.clientMsgId &&
          other.threadId == this.threadId &&
          other.kind == this.kind &&
          other.bodyText == this.bodyText &&
          other.audioPath == this.audioPath &&
          other.audioDurationS == this.audioDurationS &&
          other.attachmentPaths == this.attachmentPaths &&
          other.overrides == this.overrides &&
          other.taggedUserId == this.taggedUserId &&
          other.audioKey == this.audioKey &&
          other.attachmentKeys == this.attachmentKeys &&
          other.status == this.status &&
          other.error == this.error &&
          other.attempts == this.attempts &&
          other.createdAt == this.createdAt);
}

class OutboxRowsCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> clientMsgId;
  final Value<String> threadId;
  final Value<String> kind;
  final Value<String?> bodyText;
  final Value<String?> audioPath;
  final Value<int?> audioDurationS;
  final Value<String> attachmentPaths;
  final Value<String> overrides;
  final Value<String?> taggedUserId;
  final Value<String?> audioKey;
  final Value<String> attachmentKeys;
  final Value<String> status;
  final Value<String?> error;
  final Value<int> attempts;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OutboxRowsCompanion({
    this.clientMsgId = const Value.absent(),
    this.threadId = const Value.absent(),
    this.kind = const Value.absent(),
    this.bodyText = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.audioDurationS = const Value.absent(),
    this.attachmentPaths = const Value.absent(),
    this.overrides = const Value.absent(),
    this.taggedUserId = const Value.absent(),
    this.audioKey = const Value.absent(),
    this.attachmentKeys = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxRowsCompanion.insert({
    required String clientMsgId,
    required String threadId,
    required String kind,
    this.bodyText = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.audioDurationS = const Value.absent(),
    this.attachmentPaths = const Value.absent(),
    this.overrides = const Value.absent(),
    this.taggedUserId = const Value.absent(),
    this.audioKey = const Value.absent(),
    this.attachmentKeys = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : clientMsgId = Value(clientMsgId),
       threadId = Value(threadId),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<String>? clientMsgId,
    Expression<String>? threadId,
    Expression<String>? kind,
    Expression<String>? bodyText,
    Expression<String>? audioPath,
    Expression<int>? audioDurationS,
    Expression<String>? attachmentPaths,
    Expression<String>? overrides,
    Expression<String>? taggedUserId,
    Expression<String>? audioKey,
    Expression<String>? attachmentKeys,
    Expression<String>? status,
    Expression<String>? error,
    Expression<int>? attempts,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientMsgId != null) 'client_msg_id': clientMsgId,
      if (threadId != null) 'thread_id': threadId,
      if (kind != null) 'kind': kind,
      if (bodyText != null) 'body_text': bodyText,
      if (audioPath != null) 'audio_path': audioPath,
      if (audioDurationS != null) 'audio_duration_s': audioDurationS,
      if (attachmentPaths != null) 'attachment_paths': attachmentPaths,
      if (overrides != null) 'overrides': overrides,
      if (taggedUserId != null) 'tagged_user_id': taggedUserId,
      if (audioKey != null) 'audio_key': audioKey,
      if (attachmentKeys != null) 'attachment_keys': attachmentKeys,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (attempts != null) 'attempts': attempts,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxRowsCompanion copyWith({
    Value<String>? clientMsgId,
    Value<String>? threadId,
    Value<String>? kind,
    Value<String?>? bodyText,
    Value<String?>? audioPath,
    Value<int?>? audioDurationS,
    Value<String>? attachmentPaths,
    Value<String>? overrides,
    Value<String?>? taggedUserId,
    Value<String?>? audioKey,
    Value<String>? attachmentKeys,
    Value<String>? status,
    Value<String?>? error,
    Value<int>? attempts,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OutboxRowsCompanion(
      clientMsgId: clientMsgId ?? this.clientMsgId,
      threadId: threadId ?? this.threadId,
      kind: kind ?? this.kind,
      bodyText: bodyText ?? this.bodyText,
      audioPath: audioPath ?? this.audioPath,
      audioDurationS: audioDurationS ?? this.audioDurationS,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      overrides: overrides ?? this.overrides,
      taggedUserId: taggedUserId ?? this.taggedUserId,
      audioKey: audioKey ?? this.audioKey,
      attachmentKeys: attachmentKeys ?? this.attachmentKeys,
      status: status ?? this.status,
      error: error ?? this.error,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientMsgId.present) {
      map['client_msg_id'] = Variable<String>(clientMsgId.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (bodyText.present) {
      map['body_text'] = Variable<String>(bodyText.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (audioDurationS.present) {
      map['audio_duration_s'] = Variable<int>(audioDurationS.value);
    }
    if (attachmentPaths.present) {
      map['attachment_paths'] = Variable<String>(attachmentPaths.value);
    }
    if (overrides.present) {
      map['overrides'] = Variable<String>(overrides.value);
    }
    if (taggedUserId.present) {
      map['tagged_user_id'] = Variable<String>(taggedUserId.value);
    }
    if (audioKey.present) {
      map['audio_key'] = Variable<String>(audioKey.value);
    }
    if (attachmentKeys.present) {
      map['attachment_keys'] = Variable<String>(attachmentKeys.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRowsCompanion(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('threadId: $threadId, ')
          ..write('kind: $kind, ')
          ..write('bodyText: $bodyText, ')
          ..write('audioPath: $audioPath, ')
          ..write('audioDurationS: $audioDurationS, ')
          ..write('attachmentPaths: $attachmentPaths, ')
          ..write('overrides: $overrides, ')
          ..write('taggedUserId: $taggedUserId, ')
          ..write('audioKey: $audioKey, ')
          ..write('attachmentKeys: $attachmentKeys, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$OutboxDb extends GeneratedDatabase {
  _$OutboxDb(QueryExecutor e) : super(e);
  $OutboxDbManager get managers => $OutboxDbManager(this);
  late final $OutboxRowsTable outboxRows = $OutboxRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [outboxRows];
}

typedef $$OutboxRowsTableCreateCompanionBuilder = OutboxRowsCompanion Function({
  required String clientMsgId,
  required String threadId,
  required String kind,
  Value<String?> bodyText,
  Value<String?> audioPath,
  Value<int?> audioDurationS,
  Value<String> attachmentPaths,
  Value<String> overrides,
  Value<String?> taggedUserId,
  Value<String?> audioKey,
  Value<String> attachmentKeys,
  Value<String> status,
  Value<String?> error,
  Value<int> attempts,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$OutboxRowsTableUpdateCompanionBuilder = OutboxRowsCompanion Function({
  Value<String> clientMsgId,
  Value<String> threadId,
  Value<String> kind,
  Value<String?> bodyText,
  Value<String?> audioPath,
  Value<int?> audioDurationS,
  Value<String> attachmentPaths,
  Value<String> overrides,
  Value<String?> taggedUserId,
  Value<String?> audioKey,
  Value<String> attachmentKeys,
  Value<String> status,
  Value<String?> error,
  Value<int> attempts,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$OutboxRowsTableFilterComposer
    extends Composer<_$OutboxDb, $OutboxRowsTable> {
  $$OutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientMsgId => $composableBuilder(
    column: $table.clientMsgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioDurationS => $composableBuilder(
    column: $table.audioDurationS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentPaths => $composableBuilder(
    column: $table.attachmentPaths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overrides => $composableBuilder(
    column: $table.overrides,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taggedUserId => $composableBuilder(
    column: $table.taggedUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioKey => $composableBuilder(
    column: $table.audioKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentKeys => $composableBuilder(
    column: $table.attachmentKeys,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxRowsTableOrderingComposer
    extends Composer<_$OutboxDb, $OutboxRowsTable> {
  $$OutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientMsgId => $composableBuilder(
    column: $table.clientMsgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioDurationS => $composableBuilder(
    column: $table.audioDurationS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentPaths => $composableBuilder(
    column: $table.attachmentPaths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overrides => $composableBuilder(
    column: $table.overrides,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taggedUserId => $composableBuilder(
    column: $table.taggedUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioKey => $composableBuilder(
    column: $table.audioKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentKeys => $composableBuilder(
    column: $table.attachmentKeys,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxRowsTableAnnotationComposer
    extends Composer<_$OutboxDb, $OutboxRowsTable> {
  $$OutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientMsgId => $composableBuilder(
    column: $table.clientMsgId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get bodyText =>
      $composableBuilder(column: $table.bodyText, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<int> get audioDurationS => $composableBuilder(
    column: $table.audioDurationS,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentPaths => $composableBuilder(
    column: $table.attachmentPaths,
    builder: (column) => column,
  );

  GeneratedColumn<String> get overrides =>
      $composableBuilder(column: $table.overrides, builder: (column) => column);

  GeneratedColumn<String> get taggedUserId => $composableBuilder(
    column: $table.taggedUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioKey =>
      $composableBuilder(column: $table.audioKey, builder: (column) => column);

  GeneratedColumn<String> get attachmentKeys => $composableBuilder(
    column: $table.attachmentKeys,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxRowsTableTableManager
    extends
        RootTableManager<
          _$OutboxDb,
          $OutboxRowsTable,
          OutboxRow,
          $$OutboxRowsTableFilterComposer,
          $$OutboxRowsTableOrderingComposer,
          $$OutboxRowsTableAnnotationComposer,
          $$OutboxRowsTableCreateCompanionBuilder,
          $$OutboxRowsTableUpdateCompanionBuilder,
          (OutboxRow, BaseReferences<_$OutboxDb, $OutboxRowsTable, OutboxRow>),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxRowsTableTableManager(_$OutboxDb db, $OutboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientMsgId = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> bodyText = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int?> audioDurationS = const Value.absent(),
                Value<String> attachmentPaths = const Value.absent(),
                Value<String> overrides = const Value.absent(),
                Value<String?> taggedUserId = const Value.absent(),
                Value<String?> audioKey = const Value.absent(),
                Value<String> attachmentKeys = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxRowsCompanion(
                clientMsgId: clientMsgId,
                threadId: threadId,
                kind: kind,
                bodyText: bodyText,
                audioPath: audioPath,
                audioDurationS: audioDurationS,
                attachmentPaths: attachmentPaths,
                overrides: overrides,
                taggedUserId: taggedUserId,
                audioKey: audioKey,
                attachmentKeys: attachmentKeys,
                status: status,
                error: error,
                attempts: attempts,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientMsgId,
                required String threadId,
                required String kind,
                Value<String?> bodyText = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int?> audioDurationS = const Value.absent(),
                Value<String> attachmentPaths = const Value.absent(),
                Value<String> overrides = const Value.absent(),
                Value<String?> taggedUserId = const Value.absent(),
                Value<String?> audioKey = const Value.absent(),
                Value<String> attachmentKeys = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => OutboxRowsCompanion.insert(
                clientMsgId: clientMsgId,
                threadId: threadId,
                kind: kind,
                bodyText: bodyText,
                audioPath: audioPath,
                audioDurationS: audioDurationS,
                attachmentPaths: attachmentPaths,
                overrides: overrides,
                taggedUserId: taggedUserId,
                audioKey: audioKey,
                attachmentKeys: attachmentKeys,
                status: status,
                error: error,
                attempts: attempts,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxRowsTable, OutboxRow>(table),
                  BaseReferences<_$OutboxDb, $OutboxRowsTable, OutboxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$OutboxDb,
      $OutboxRowsTable,
      OutboxRow,
      $$OutboxRowsTableFilterComposer,
      $$OutboxRowsTableOrderingComposer,
      $$OutboxRowsTableAnnotationComposer,
      $$OutboxRowsTableCreateCompanionBuilder,
      $$OutboxRowsTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$OutboxDb, $OutboxRowsTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;

class $OutboxDbManager {
  final _$OutboxDb _db;
  $OutboxDbManager(this._db);
  $$OutboxRowsTableTableManager get outboxRows =>
      $$OutboxRowsTableTableManager(_db, _db.outboxRows);
}
