import '../runtime/storage_service.dart';

enum ReliablePendingOperationKind { directPayload, groupPayload, groupMembers }

class ReliablePendingOperation {
  final String operationId;
  final ReliablePendingOperationKind kind;
  final String? targetId;
  final Map<String, dynamic>? payload;
  final List<String>? recipients;
  final String? messageId;
  final bool forcePlain;
  final String? groupId;
  final String? ownerPeerId;
  final List<String>? memberPeerIds;
  final int? ttlSeconds;
  int attempts = 0;
  int nextAttemptMs = 0;

  ReliablePendingOperation.directOrGroupPayload({
    required this.operationId,
    required this.targetId,
    required this.payload,
    required ReliablePendingOperationKind operationKind,
    required this.recipients,
    required this.messageId,
    required this.forcePlain,
  }) : kind = operationKind,
       groupId = null,
       ownerPeerId = null,
       memberPeerIds = null,
       ttlSeconds = null;

  ReliablePendingOperation.groupMembers({
    required this.operationId,
    required this.groupId,
    required this.ownerPeerId,
    required this.memberPeerIds,
    required this.ttlSeconds,
  }) : kind = ReliablePendingOperationKind.groupMembers,
       targetId = null,
       payload = null,
       recipients = null,
       messageId = null,
       forcePlain = false;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operationId': operationId,
    'kind': kind.name,
    'targetId': targetId,
    'payload': payload,
    'recipients': recipients,
    'messageId': messageId,
    'forcePlain': forcePlain,
    'groupId': groupId,
    'ownerPeerId': ownerPeerId,
    'memberPeerIds': memberPeerIds,
    'ttlSeconds': ttlSeconds,
    'attempts': attempts,
    'nextAttemptMs': nextAttemptMs,
  };

  static ReliablePendingOperation? fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'];
    final operationId = json['operationId'];
    if (kindRaw is! String || operationId is! String) {
      return null;
    }
    final kind = ReliablePendingOperationKind.values.where(
      (value) => value.name == kindRaw,
    );
    if (kind.isEmpty) {
      return null;
    }
    final resolvedKind = kind.first;
    final attempts = json['attempts'];
    final nextAttemptMs = json['nextAttemptMs'];
    ReliablePendingOperation operation;
    switch (resolvedKind) {
      case ReliablePendingOperationKind.directPayload:
      case ReliablePendingOperationKind.groupPayload:
        final targetId = json['targetId'];
        final payload = json['payload'];
        if (targetId is! String || payload is! Map) {
          return null;
        }
        operation = ReliablePendingOperation.directOrGroupPayload(
          operationId: operationId,
          targetId: targetId,
          payload: Map<String, dynamic>.from(payload),
          operationKind: resolvedKind,
          recipients: json['recipients'] is List
              ? (json['recipients'] as List).whereType<String>().toList(
                  growable: false,
                )
              : null,
          messageId: json['messageId'] as String?,
          forcePlain: json['forcePlain'] == true,
        );
      case ReliablePendingOperationKind.groupMembers:
        final groupId = json['groupId'];
        final ownerPeerId = json['ownerPeerId'];
        final memberPeerIds = json['memberPeerIds'];
        final ttlSeconds = json['ttlSeconds'];
        if (groupId is! String ||
            ownerPeerId is! String ||
            memberPeerIds is! List ||
            ttlSeconds is! int) {
          return null;
        }
        operation = ReliablePendingOperation.groupMembers(
          operationId: operationId,
          groupId: groupId,
          ownerPeerId: ownerPeerId,
          memberPeerIds: memberPeerIds.whereType<String>().toList(
            growable: false,
          ),
          ttlSeconds: ttlSeconds,
        );
    }
    operation.attempts = attempts is int ? attempts : 0;
    operation.nextAttemptMs = nextAttemptMs is int ? nextAttemptMs : 0;
    return operation;
  }

  void registerFailure() {
    attempts += 1;
    final backoffSeconds = attempts < 6 ? 2 << (attempts - 1) : 60;
    final delayMs = backoffSeconds * 1000;
    nextAttemptMs = DateTime.now().millisecondsSinceEpoch + delayMs;
  }
}

class ReliablePendingOperationStore {
  final SecureStorageBox? _stateBox;
  final String _stateKey;
  final void Function(String message) _log;
  final Map<String, ReliablePendingOperation> _operations =
      <String, ReliablePendingOperation>{};

  ReliablePendingOperationStore({
    required SecureStorageBox? stateBox,
    required String stateKey,
    required void Function(String message) log,
  }) : _stateBox = stateBox,
       _stateKey = stateKey,
       _log = log;

  bool get isEmpty => _operations.isEmpty;

  bool contains(String operationId) => _operations.containsKey(operationId);

  List<ReliablePendingOperation> snapshot() =>
      List<ReliablePendingOperation>.from(_operations.values);

  Future<void> restore() async {
    final box = _stateBox;
    if (box == null) {
      return;
    }
    final raw = box.get(_stateKey);
    if (raw is! List) {
      return;
    }
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final operation = ReliablePendingOperation.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (operation == null) {
        continue;
      }
      _operations[operation.operationId] = operation;
    }
    if (_operations.isNotEmpty) {
      _log('pending:restored count=${_operations.length}');
    }
  }

  Future<void> upsert(ReliablePendingOperation operation) async {
    _operations[operation.operationId] = operation;
    await persist();
  }

  Future<void> remove(String operationId) async {
    if (_operations.remove(operationId) == null) {
      return;
    }
    await persist();
  }

  Future<void> persist() async {
    final box = _stateBox;
    if (box == null) {
      return;
    }
    final payload = _operations.values
        .map((item) => item.toJson())
        .toList(growable: false);
    await box.put(_stateKey, payload);
  }
}
