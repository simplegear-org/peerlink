import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

part 'chat_database.g.dart';

class ChatSummaries extends Table {
  TextColumn get peerId => text()();
  TextColumn get name => text()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get messagesLoaded => boolean().withDefault(const Constant(false))();
  BoolColumn get hasMoreMessages => boolean().withDefault(const Constant(true))();
  TextColumn get lastMessageJson => text().nullable()();
  IntColumn get updatedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {peerId};
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get messageId => text().unique()();
  TextColumn get peerId => text()();
  IntColumn get timestampMs => integer()();
  TextColumn get payloadJson => text()();
}

LazyDatabase _openChatDatabase(String directory) {
  return LazyDatabase(() async {
    final dbFile = File('$directory/peerlink_chat.sqlite');
    await dbFile.parent.create(recursive: true);
    debugPrint('[ChatDatabaseService] Opening sqlite at ${dbFile.path}');
    return NativeDatabase(dbFile);
  });
}

@DriftDatabase(tables: [ChatSummaries, ChatMessages])
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase({required String directory}) : super(_openChatDatabase(directory));

  @override
  int get schemaVersion => 1;

  Future<void> upsertChatSummary(String peerId, Map<String, dynamic> json) async {
    final rawLast = json['lastMessage'];
    String? lastMessageJson;
    int? updatedAtMs;
    if (rawLast is Map<String, dynamic>) {
      lastMessageJson = jsonEncode(rawLast);
      final rawTimestamp = rawLast['timestamp'] as String?;
      updatedAtMs = DateTime.tryParse(rawTimestamp ?? '')?.millisecondsSinceEpoch;
    }

    await into(chatSummaries).insertOnConflictUpdate(
      ChatSummariesCompanion(
        peerId: Value(peerId),
        name: Value((json['name'] as String?) ?? peerId),
        unreadCount: Value((json['unreadCount'] as int?) ?? 0),
        messagesLoaded: Value((json['messagesLoaded'] as bool?) ?? false),
        hasMoreMessages: Value((json['hasMoreMessages'] as bool?) ?? true),
        lastMessageJson: Value(lastMessageJson),
        updatedAtMs: Value(updatedAtMs),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getAllChatSummariesAsJson() async {
    final rows = await (select(chatSummaries)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAtMs,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
            (t) => OrderingTerm(expression: t.peerId),
          ]))
        .get();

    return rows.map(_summaryRowToJson).toList(growable: false);
  }

  Future<Map<String, dynamic>?> getChatSummaryAsJson(String peerId) async {
    final row = await (select(chatSummaries)..where((t) => t.peerId.equals(peerId)))
        .getSingleOrNull();
    return row == null ? null : _summaryRowToJson(row);
  }

  Future<void> deleteChatSummary(String peerId) {
    return (delete(chatSummaries)..where((t) => t.peerId.equals(peerId))).go();
  }

  Future<void> upsertMessage(Map<String, dynamic> json) async {
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '');
    final messageId = json['id'] as String;
    final peerId = json['peerId'] as String;
    final timestampMs = timestamp?.millisecondsSinceEpoch ?? 0;
    final payloadJson = jsonEncode(json);

    await customStatement(
      '''
      INSERT INTO chat_messages (message_id, peer_id, timestamp_ms, payload_json)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(message_id) DO UPDATE SET
        peer_id = excluded.peer_id,
        timestamp_ms = excluded.timestamp_ms,
        payload_json = excluded.payload_json
      ''',
      <Object>[messageId, peerId, timestampMs, payloadJson],
    );
  }

  Future<void> upsertMessages(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) {
      return;
    }
    await transaction(() async {
      for (final message in messages) {
        await upsertMessage(message);
      }
    });
  }

  Future<void> replaceMessages(
    String peerId,
    List<Map<String, dynamic>> messages,
  ) async {
    await transaction(() async {
      await (delete(chatMessages)..where((t) => t.peerId.equals(peerId))).go();
      if (messages.isEmpty) {
        return;
      }
      for (final message in messages) {
        await upsertMessage(message);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getMessagesAsJson(String peerId) async {
    final query = select(chatMessages)
      ..where((t) => t.peerId.equals(peerId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.timestampMs),
        (t) => OrderingTerm(expression: t.id),
      ]);
    final rows = await query.get();
    return rows.map(_messageRowToJson).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getLatestMessagesAsJson(
    String peerId,
    int limit,
  ) async {
    final query = select(chatMessages)
      ..where((t) => t.peerId.equals(peerId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.timestampMs, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await query.get();
    final json = rows.map(_messageRowToJson).toList(growable: false);
    return json.reversed.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getMessagesPageAsJson(
    String peerId,
    int offset,
    int limit,
  ) async {
    final query = select(chatMessages)
      ..where((t) => t.peerId.equals(peerId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.timestampMs, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    final json = rows.map(_messageRowToJson).toList(growable: false);
    return json.reversed.toList(growable: false);
  }

  Future<int> countMessages(String peerId) async {
    final expr = chatMessages.id.count();
    final query = selectOnly(chatMessages)
      ..addColumns([expr])
      ..where(chatMessages.peerId.equals(peerId));
    final row = await query.getSingle();
    return row.read(expr) ?? 0;
  }

  Future<int?> getMessageOffsetFromNewest(String peerId, String messageId) async {
    final target = await (select(chatMessages)
          ..where(
            (t) => t.peerId.equals(peerId) & t.messageId.equals(messageId),
          ))
        .getSingleOrNull();
    if (target == null) {
      return null;
    }

    final Expression<int> newerExpr = chatMessages.id.count();
    final newerQuery = selectOnly(chatMessages)
      ..addColumns([newerExpr])
      ..where(
        chatMessages.peerId.equals(peerId) &
            ((chatMessages.timestampMs.isBiggerThanValue(target.timestampMs)) |
                (chatMessages.timestampMs.equals(target.timestampMs) &
                    chatMessages.id.isBiggerThanValue(target.id))),
      );
    final newerRow = await newerQuery.getSingle();
    return newerRow.read<int>(newerExpr) ?? 0;
  }

  Future<void> deleteMessages(String peerId) {
    return (delete(chatMessages)..where((t) => t.peerId.equals(peerId))).go();
  }

  Future<void> deleteAllData() async {
    await batch((batch) {
      batch.deleteAll(chatMessages);
      batch.deleteAll(chatSummaries);
    });
  }

  Future<void> deleteMessagesByIds(String peerId, List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return;
    }
    await (delete(chatMessages)
          ..where(
            (t) => t.peerId.equals(peerId) & t.messageId.isIn(messageIds),
          ))
        .go();
  }

  Future<List<Map<String, dynamic>>> getConversationHeadsAsJson() async {
    final rows = await customSelect(
      '''
      SELECT m.peer_id, m.payload_json
      FROM chat_messages m
      INNER JOIN (
        SELECT peer_id, MAX(timestamp_ms) AS max_timestamp
        FROM chat_messages
        GROUP BY peer_id
      ) latest
      ON latest.peer_id = m.peer_id AND latest.max_timestamp = m.timestamp_ms
      ORDER BY m.timestamp_ms DESC, m.id DESC
      ''',
      readsFrom: {chatMessages},
    ).get();

    final seenPeers = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final peerId = row.read<String>('peer_id');
      final payload = row.read<String>('payload_json');
      if (seenPeers.contains(peerId)) {
        continue;
      }
      seenPeers.add(peerId);
      result.add(jsonDecode(payload) as Map<String, dynamic>);
    }
    return result;
  }

  Future<void> clearAll() async {
    await batch((batch) {
      batch.deleteAll(chatMessages);
      batch.deleteAll(chatSummaries);
    });
  }

  Map<String, dynamic> _summaryRowToJson(ChatSummary row) {
    return <String, dynamic>{
      'peerId': row.peerId,
      'name': row.name,
      'unreadCount': row.unreadCount,
      'messagesLoaded': row.messagesLoaded,
      'hasMoreMessages': row.hasMoreMessages,
      'lastMessage': row.lastMessageJson == null
          ? null
          : jsonDecode(row.lastMessageJson!) as Map<String, dynamic>,
    };
  }

  Map<String, dynamic> _messageRowToJson(ChatMessage row) {
    return jsonDecode(row.payloadJson) as Map<String, dynamic>;
  }
}

class ChatDatabaseService {
  static ChatDatabase? _database;
  static bool _initialized = false;
  static Future<void>? _initializationFuture;
  static Future<void>? _recoveryFuture;
  static String? _directory;

  static Future<void> initialize({required String directory}) async {
    _directory = directory;
    if (_initialized) {
      debugPrint('[ChatDatabaseService] Already initialized');
      return;
    }

    final currentInitialization = _initializationFuture;
    if (currentInitialization != null) {
      debugPrint('[ChatDatabaseService] Awaiting in-flight initialization');
      await currentInitialization;
      return;
    }

    debugPrint('[ChatDatabaseService] Initializing...');
    _initializationFuture = () async {
      try {
        _database = ChatDatabase(directory: directory);
        await _database!.customSelect('SELECT 1').get();
        debugPrint('[ChatDatabaseService] SQLite probe succeeded');
        _initialized = true;
        debugPrint('[ChatDatabaseService] Initialized successfully');
      } catch (e, stack) {
        debugPrint('[ChatDatabaseService] Failed to initialize: $e\n$stack');
        rethrow;
      } finally {
        _initializationFuture = null;
      }
    }();

    await _initializationFuture;
  }

  static bool get isInitialized => _initialized && _database != null;

  static ChatDatabase get instance {
    final database = _database;
    if (database == null) {
      throw StateError('ChatDatabaseService not initialized');
    }
    return database;
  }

  static Future<T> runWithRecovery<T>(
    Future<T> Function(ChatDatabase database) action, {
    required String operation,
  }) async {
    try {
      return await action(instance);
    } catch (error, stack) {
      if (!_isRecoverableSqliteError(error)) {
        rethrow;
      }

      debugPrint(
        '[ChatDatabaseService] Recoverable sqlite error during $operation: '
        '$error\n$stack',
      );
      await _recover();
      return action(instance);
    }
  }

  static bool _isRecoverableSqliteError(Object error) {
    final text = error.toString();
    return text.contains('SqliteException(14)') ||
        text.contains('unable to open database file');
  }

  static Future<void> _recover() async {
    final currentRecovery = _recoveryFuture;
    if (currentRecovery != null) {
      debugPrint('[ChatDatabaseService] Awaiting in-flight recovery');
      await currentRecovery;
      return;
    }

    final directory = _directory;
    if (directory == null || directory.isEmpty) {
      throw StateError('ChatDatabaseService directory is not configured');
    }

    _recoveryFuture = () async {
      debugPrint('[ChatDatabaseService] Recovery started');
      final existing = _database;
      _database = null;
      _initialized = false;
      try {
        if (existing != null) {
          await existing.close();
        }
      } catch (error, stack) {
        debugPrint('[ChatDatabaseService] Close before recovery failed: $error\n$stack');
      }

      final dbDirectory = Directory(directory);
      await dbDirectory.create(recursive: true);
      await initialize(directory: directory);
      debugPrint('[ChatDatabaseService] Recovery completed');
    }();

    try {
      await _recoveryFuture;
    } finally {
      _recoveryFuture = null;
    }
  }
}
