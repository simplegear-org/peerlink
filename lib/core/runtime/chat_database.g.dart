// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_database.dart';

// ignore_for_file: type=lint
class $ChatSummariesTable extends ChatSummaries
    with TableInfo<$ChatSummariesTable, ChatSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _messagesLoadedMeta = const VerificationMeta(
    'messagesLoaded',
  );
  @override
  late final GeneratedColumn<bool> messagesLoaded = GeneratedColumn<bool>(
    'messages_loaded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("messages_loaded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasMoreMessagesMeta = const VerificationMeta(
    'hasMoreMessages',
  );
  @override
  late final GeneratedColumn<bool> hasMoreMessages = GeneratedColumn<bool>(
    'has_more_messages',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_more_messages" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastMessageJsonMeta = const VerificationMeta(
    'lastMessageJson',
  );
  @override
  late final GeneratedColumn<String> lastMessageJson = GeneratedColumn<String>(
    'last_message_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerId,
    name,
    unreadCount,
    messagesLoaded,
    hasMoreMessages,
    lastMessageJson,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('messages_loaded')) {
      context.handle(
        _messagesLoadedMeta,
        messagesLoaded.isAcceptableOrUnknown(
          data['messages_loaded']!,
          _messagesLoadedMeta,
        ),
      );
    }
    if (data.containsKey('has_more_messages')) {
      context.handle(
        _hasMoreMessagesMeta,
        hasMoreMessages.isAcceptableOrUnknown(
          data['has_more_messages']!,
          _hasMoreMessagesMeta,
        ),
      );
    }
    if (data.containsKey('last_message_json')) {
      context.handle(
        _lastMessageJsonMeta,
        lastMessageJson.isAcceptableOrUnknown(
          data['last_message_json']!,
          _lastMessageJsonMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerId};
  @override
  ChatSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSummary(
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      messagesLoaded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}messages_loaded'],
      )!,
      hasMoreMessages: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_more_messages'],
      )!,
      lastMessageJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_json'],
      ),
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      ),
    );
  }

  @override
  $ChatSummariesTable createAlias(String alias) {
    return $ChatSummariesTable(attachedDatabase, alias);
  }
}

class ChatSummary extends DataClass implements Insertable<ChatSummary> {
  final String peerId;
  final String name;
  final int unreadCount;
  final bool messagesLoaded;
  final bool hasMoreMessages;
  final String? lastMessageJson;
  final int? updatedAtMs;
  const ChatSummary({
    required this.peerId,
    required this.name,
    required this.unreadCount,
    required this.messagesLoaded,
    required this.hasMoreMessages,
    this.lastMessageJson,
    this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_id'] = Variable<String>(peerId);
    map['name'] = Variable<String>(name);
    map['unread_count'] = Variable<int>(unreadCount);
    map['messages_loaded'] = Variable<bool>(messagesLoaded);
    map['has_more_messages'] = Variable<bool>(hasMoreMessages);
    if (!nullToAbsent || lastMessageJson != null) {
      map['last_message_json'] = Variable<String>(lastMessageJson);
    }
    if (!nullToAbsent || updatedAtMs != null) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs);
    }
    return map;
  }

  ChatSummariesCompanion toCompanion(bool nullToAbsent) {
    return ChatSummariesCompanion(
      peerId: Value(peerId),
      name: Value(name),
      unreadCount: Value(unreadCount),
      messagesLoaded: Value(messagesLoaded),
      hasMoreMessages: Value(hasMoreMessages),
      lastMessageJson: lastMessageJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageJson),
      updatedAtMs: updatedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAtMs),
    );
  }

  factory ChatSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSummary(
      peerId: serializer.fromJson<String>(json['peerId']),
      name: serializer.fromJson<String>(json['name']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      messagesLoaded: serializer.fromJson<bool>(json['messagesLoaded']),
      hasMoreMessages: serializer.fromJson<bool>(json['hasMoreMessages']),
      lastMessageJson: serializer.fromJson<String?>(json['lastMessageJson']),
      updatedAtMs: serializer.fromJson<int?>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerId': serializer.toJson<String>(peerId),
      'name': serializer.toJson<String>(name),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'messagesLoaded': serializer.toJson<bool>(messagesLoaded),
      'hasMoreMessages': serializer.toJson<bool>(hasMoreMessages),
      'lastMessageJson': serializer.toJson<String?>(lastMessageJson),
      'updatedAtMs': serializer.toJson<int?>(updatedAtMs),
    };
  }

  ChatSummary copyWith({
    String? peerId,
    String? name,
    int? unreadCount,
    bool? messagesLoaded,
    bool? hasMoreMessages,
    Value<String?> lastMessageJson = const Value.absent(),
    Value<int?> updatedAtMs = const Value.absent(),
  }) => ChatSummary(
    peerId: peerId ?? this.peerId,
    name: name ?? this.name,
    unreadCount: unreadCount ?? this.unreadCount,
    messagesLoaded: messagesLoaded ?? this.messagesLoaded,
    hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
    lastMessageJson: lastMessageJson.present
        ? lastMessageJson.value
        : this.lastMessageJson,
    updatedAtMs: updatedAtMs.present ? updatedAtMs.value : this.updatedAtMs,
  );
  ChatSummary copyWithCompanion(ChatSummariesCompanion data) {
    return ChatSummary(
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      name: data.name.present ? data.name.value : this.name,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      messagesLoaded: data.messagesLoaded.present
          ? data.messagesLoaded.value
          : this.messagesLoaded,
      hasMoreMessages: data.hasMoreMessages.present
          ? data.hasMoreMessages.value
          : this.hasMoreMessages,
      lastMessageJson: data.lastMessageJson.present
          ? data.lastMessageJson.value
          : this.lastMessageJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSummary(')
          ..write('peerId: $peerId, ')
          ..write('name: $name, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('messagesLoaded: $messagesLoaded, ')
          ..write('hasMoreMessages: $hasMoreMessages, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerId,
    name,
    unreadCount,
    messagesLoaded,
    hasMoreMessages,
    lastMessageJson,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSummary &&
          other.peerId == this.peerId &&
          other.name == this.name &&
          other.unreadCount == this.unreadCount &&
          other.messagesLoaded == this.messagesLoaded &&
          other.hasMoreMessages == this.hasMoreMessages &&
          other.lastMessageJson == this.lastMessageJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class ChatSummariesCompanion extends UpdateCompanion<ChatSummary> {
  final Value<String> peerId;
  final Value<String> name;
  final Value<int> unreadCount;
  final Value<bool> messagesLoaded;
  final Value<bool> hasMoreMessages;
  final Value<String?> lastMessageJson;
  final Value<int?> updatedAtMs;
  final Value<int> rowid;
  const ChatSummariesCompanion({
    this.peerId = const Value.absent(),
    this.name = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.messagesLoaded = const Value.absent(),
    this.hasMoreMessages = const Value.absent(),
    this.lastMessageJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatSummariesCompanion.insert({
    required String peerId,
    required String name,
    this.unreadCount = const Value.absent(),
    this.messagesLoaded = const Value.absent(),
    this.hasMoreMessages = const Value.absent(),
    this.lastMessageJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerId = Value(peerId),
       name = Value(name);
  static Insertable<ChatSummary> custom({
    Expression<String>? peerId,
    Expression<String>? name,
    Expression<int>? unreadCount,
    Expression<bool>? messagesLoaded,
    Expression<bool>? hasMoreMessages,
    Expression<String>? lastMessageJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerId != null) 'peer_id': peerId,
      if (name != null) 'name': name,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (messagesLoaded != null) 'messages_loaded': messagesLoaded,
      if (hasMoreMessages != null) 'has_more_messages': hasMoreMessages,
      if (lastMessageJson != null) 'last_message_json': lastMessageJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatSummariesCompanion copyWith({
    Value<String>? peerId,
    Value<String>? name,
    Value<int>? unreadCount,
    Value<bool>? messagesLoaded,
    Value<bool>? hasMoreMessages,
    Value<String?>? lastMessageJson,
    Value<int?>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ChatSummariesCompanion(
      peerId: peerId ?? this.peerId,
      name: name ?? this.name,
      unreadCount: unreadCount ?? this.unreadCount,
      messagesLoaded: messagesLoaded ?? this.messagesLoaded,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      lastMessageJson: lastMessageJson ?? this.lastMessageJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (messagesLoaded.present) {
      map['messages_loaded'] = Variable<bool>(messagesLoaded.value);
    }
    if (hasMoreMessages.present) {
      map['has_more_messages'] = Variable<bool>(hasMoreMessages.value);
    }
    if (lastMessageJson.present) {
      map['last_message_json'] = Variable<String>(lastMessageJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSummariesCompanion(')
          ..write('peerId: $peerId, ')
          ..write('name: $name, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('messagesLoaded: $messagesLoaded, ')
          ..write('hasMoreMessages: $hasMoreMessages, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    peerId,
    timestampMs,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final int id;
  final String messageId;
  final String peerId;
  final int timestampMs;
  final String payloadJson;
  const ChatMessage({
    required this.id,
    required this.messageId,
    required this.peerId,
    required this.timestampMs,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_id'] = Variable<String>(messageId);
    map['peer_id'] = Variable<String>(peerId);
    map['timestamp_ms'] = Variable<int>(timestampMs);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      messageId: Value(messageId),
      peerId: Value(peerId),
      timestampMs: Value(timestampMs),
      payloadJson: Value(payloadJson),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<int>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageId': serializer.toJson<String>(messageId),
      'peerId': serializer.toJson<String>(peerId),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  ChatMessage copyWith({
    int? id,
    String? messageId,
    String? peerId,
    int? timestampMs,
    String? payloadJson,
  }) => ChatMessage(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    peerId: peerId ?? this.peerId,
    timestampMs: timestampMs ?? this.timestampMs,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('peerId: $peerId, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, messageId, peerId, timestampMs, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.peerId == this.peerId &&
          other.timestampMs == this.timestampMs &&
          other.payloadJson == this.payloadJson);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<int> id;
  final Value<String> messageId;
  final Value<String> peerId;
  final Value<int> timestampMs;
  final Value<String> payloadJson;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.payloadJson = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String messageId,
    required String peerId,
    required int timestampMs,
    required String payloadJson,
  }) : messageId = Value(messageId),
       peerId = Value(peerId),
       timestampMs = Value(timestampMs),
       payloadJson = Value(payloadJson);
  static Insertable<ChatMessage> custom({
    Expression<int>? id,
    Expression<String>? messageId,
    Expression<String>? peerId,
    Expression<int>? timestampMs,
    Expression<String>? payloadJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (peerId != null) 'peer_id': peerId,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (payloadJson != null) 'payload_json': payloadJson,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? messageId,
    Value<String>? peerId,
    Value<int>? timestampMs,
    Value<String>? payloadJson,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      peerId: peerId ?? this.peerId,
      timestampMs: timestampMs ?? this.timestampMs,
      payloadJson: payloadJson ?? this.payloadJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('peerId: $peerId, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChatDatabase extends GeneratedDatabase {
  _$ChatDatabase(QueryExecutor e) : super(e);
  $ChatDatabaseManager get managers => $ChatDatabaseManager(this);
  late final $ChatSummariesTable chatSummaries = $ChatSummariesTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chatSummaries,
    chatMessages,
  ];
}

typedef $$ChatSummariesTableCreateCompanionBuilder =
    ChatSummariesCompanion Function({
      required String peerId,
      required String name,
      Value<int> unreadCount,
      Value<bool> messagesLoaded,
      Value<bool> hasMoreMessages,
      Value<String?> lastMessageJson,
      Value<int?> updatedAtMs,
      Value<int> rowid,
    });
typedef $$ChatSummariesTableUpdateCompanionBuilder =
    ChatSummariesCompanion Function({
      Value<String> peerId,
      Value<String> name,
      Value<int> unreadCount,
      Value<bool> messagesLoaded,
      Value<bool> hasMoreMessages,
      Value<String?> lastMessageJson,
      Value<int?> updatedAtMs,
      Value<int> rowid,
    });

class $$ChatSummariesTableFilterComposer
    extends Composer<_$ChatDatabase, $ChatSummariesTable> {
  $$ChatSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get messagesLoaded => $composableBuilder(
    column: $table.messagesLoaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasMoreMessages => $composableBuilder(
    column: $table.hasMoreMessages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSummariesTableOrderingComposer
    extends Composer<_$ChatDatabase, $ChatSummariesTable> {
  $$ChatSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get messagesLoaded => $composableBuilder(
    column: $table.messagesLoaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasMoreMessages => $composableBuilder(
    column: $table.hasMoreMessages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSummariesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $ChatSummariesTable> {
  $$ChatSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get messagesLoaded => $composableBuilder(
    column: $table.messagesLoaded,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasMoreMessages => $composableBuilder(
    column: $table.hasMoreMessages,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ChatSummariesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatSummariesTable,
          ChatSummary,
          $$ChatSummariesTableFilterComposer,
          $$ChatSummariesTableOrderingComposer,
          $$ChatSummariesTableAnnotationComposer,
          $$ChatSummariesTableCreateCompanionBuilder,
          $$ChatSummariesTableUpdateCompanionBuilder,
          (
            ChatSummary,
            BaseReferences<_$ChatDatabase, $ChatSummariesTable, ChatSummary>,
          ),
          ChatSummary,
          PrefetchHooks Function()
        > {
  $$ChatSummariesTableTableManager(_$ChatDatabase db, $ChatSummariesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> messagesLoaded = const Value.absent(),
                Value<bool> hasMoreMessages = const Value.absent(),
                Value<String?> lastMessageJson = const Value.absent(),
                Value<int?> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSummariesCompanion(
                peerId: peerId,
                name: name,
                unreadCount: unreadCount,
                messagesLoaded: messagesLoaded,
                hasMoreMessages: hasMoreMessages,
                lastMessageJson: lastMessageJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerId,
                required String name,
                Value<int> unreadCount = const Value.absent(),
                Value<bool> messagesLoaded = const Value.absent(),
                Value<bool> hasMoreMessages = const Value.absent(),
                Value<String?> lastMessageJson = const Value.absent(),
                Value<int?> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSummariesCompanion.insert(
                peerId: peerId,
                name: name,
                unreadCount: unreadCount,
                messagesLoaded: messagesLoaded,
                hasMoreMessages: hasMoreMessages,
                lastMessageJson: lastMessageJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatSummariesTable,
      ChatSummary,
      $$ChatSummariesTableFilterComposer,
      $$ChatSummariesTableOrderingComposer,
      $$ChatSummariesTableAnnotationComposer,
      $$ChatSummariesTableCreateCompanionBuilder,
      $$ChatSummariesTableUpdateCompanionBuilder,
      (
        ChatSummary,
        BaseReferences<_$ChatDatabase, $ChatSummariesTable, ChatSummary>,
      ),
      ChatSummary,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      required String messageId,
      required String peerId,
      required int timestampMs,
      required String payloadJson,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<String> messageId,
      Value<String> peerId,
      Value<int> timestampMs,
      Value<String> payloadJson,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessage,
            BaseReferences<_$ChatDatabase, $ChatMessagesTable, ChatMessage>,
          ),
          ChatMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$ChatDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                messageId: messageId,
                peerId: peerId,
                timestampMs: timestampMs,
                payloadJson: payloadJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String messageId,
                required String peerId,
                required int timestampMs,
                required String payloadJson,
              }) => ChatMessagesCompanion.insert(
                id: id,
                messageId: messageId,
                peerId: peerId,
                timestampMs: timestampMs,
                payloadJson: payloadJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessage,
        BaseReferences<_$ChatDatabase, $ChatMessagesTable, ChatMessage>,
      ),
      ChatMessage,
      PrefetchHooks Function()
    >;

class $ChatDatabaseManager {
  final _$ChatDatabase _db;
  $ChatDatabaseManager(this._db);
  $$ChatSummariesTableTableManager get chatSummaries =>
      $$ChatSummariesTableTableManager(_db, _db.chatSummaries);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
}
