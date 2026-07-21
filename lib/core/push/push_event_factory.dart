import '../calls/call_models.dart';
import '../runtime/account_membership_update_payload.dart';
import 'push_api_client.dart';

class PushRelayHint {
  final String? serverId;
  final List<String> servers;
  final String scopeKind;
  final String? blobId;
  final String? relayMessageId;

  const PushRelayHint({
    this.serverId,
    this.servers = const <String>[],
    required this.scopeKind,
    this.blobId,
    this.relayMessageId,
  });

  bool get isEmpty =>
      (serverId == null || serverId!.trim().isEmpty) &&
      servers.isEmpty &&
      (blobId == null || blobId!.trim().isEmpty) &&
      (relayMessageId == null || relayMessageId!.trim().isEmpty);
}

class PushEventDraft {
  final List<String> recipientUserIds;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? notification;
  final PushDeliveryOptions delivery;

  const PushEventDraft({
    required this.recipientUserIds,
    required this.payload,
    this.notification,
    this.delivery = const PushDeliveryOptions(),
  });
}

class PushEventFactory {
  const PushEventFactory();

  PushEventDraft buildDirectMessage({
    required String senderUserId,
    required String directPeerId,
    required String messageId,
    PushServersMetadata? servers,
    PushRelayHint? relayHint,
    String? notificationType,
    Map<String, dynamic>? data,
  }) {
    final relayPayload = _buildRelayPayload(relayHint);
    final serversPayload = _buildServersPayload(servers);
    final payload = <String, dynamic>{
      'type': 'direct_update',
      'directPeerId': directPeerId,
      'lastSeq': messageId,
      'senderUserId': senderUserId,
      'schemaVersion': 'push-v1.1',
    };
    if (relayPayload != null) {
      payload['relay'] = relayPayload;
    }
    if (serversPayload != null) {
      payload['servers'] = serversPayload;
    }
    if (data != null && data.isNotEmpty) {
      payload.addAll(data);
    }
    return PushEventDraft(
      recipientUserIds: <String>[directPeerId],
      payload: payload,
      notification: _buildMessageNotification(notificationType),
    );
  }

  PushEventDraft buildGroupMessage({
    required String senderUserId,
    required String groupId,
    required String messageId,
    required List<String> recipientUserIds,
    PushServersMetadata? servers,
    PushRelayHint? relayHint,
    String? notificationType,
  }) {
    final relayPayload = _buildRelayPayload(relayHint);
    final serversPayload = _buildServersPayload(servers);
    final payload = <String, dynamic>{
      'type': 'group_update',
      'groupId': groupId,
      'lastSeq': messageId,
      'senderUserId': senderUserId,
      'schemaVersion': 'push-v1.1',
    };
    if (relayPayload != null) {
      payload['relay'] = relayPayload;
    }
    if (serversPayload != null) {
      payload['servers'] = serversPayload;
    }
    return PushEventDraft(
      recipientUserIds: recipientUserIds,
      payload: payload,
      notification: _buildMessageNotification(notificationType),
    );
  }

  PushEventDraft buildAccountMembershipUpdate({
    required String senderUserId,
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
    PushServersMetadata? servers,
  }) {
    final serversPayload = _buildServersPayload(servers);
    final payload = <String, dynamic>{
      'type': 'account_membership_update',
      'accountMembershipUpdate': update.toJson(),
    };
    if (serversPayload != null) {
      payload['servers'] = serversPayload;
    }
    return PushEventDraft(
      recipientUserIds: <String>[directPeerId],
      payload: payload,
    );
  }

  PushEventDraft buildCallInvite({
    required String callerUserId,
    required String calleeUserId,
    required String callId,
    required CallMediaType mediaType,
    PushServersMetadata? servers,
    PushServersMetadata? priorityServers,
    bool standard = true,
    bool voip = true,
  }) {
    final serversPayload = _buildServersPayload(servers);
    final priorityServersPayload = _buildServersPayload(priorityServers);
    final payload = <String, dynamic>{
      'type': 'call_invite',
      'callerUserId': callerUserId,
      'calleeUserId': calleeUserId,
      'callId': callId,
      'mediaType': mediaType.name,
    };
    if (serversPayload != null) {
      payload['servers'] = serversPayload;
    }
    if (priorityServersPayload != null) {
      payload['priority_servers'] = priorityServersPayload;
    }
    return PushEventDraft(
      recipientUserIds: <String>[calleeUserId],
      payload: payload,
      notification: <String, dynamic>{
        'title': 'PeerLink',
        'body': mediaType == CallMediaType.video
            ? 'Видеозвонок'
            : 'Входящий звонок',
      },
      delivery: PushDeliveryOptions(standard: standard, voip: voip),
    );
  }

  PushEventDraft buildCallEnd({
    required String callerUserId,
    required String calleeUserId,
    required String callId,
    bool standard = true,
    bool voip = true,
  }) {
    return PushEventDraft(
      recipientUserIds: <String>[calleeUserId],
      payload: <String, dynamic>{
        'type': 'call_invite',
        'callerUserId': callerUserId,
        'calleeUserId': calleeUserId,
        'callId': callId,
        'mediaType': 'end',
        'callAction': 'end',
      },
      delivery: PushDeliveryOptions(standard: standard, voip: voip),
    );
  }

  Map<String, dynamic>? _buildMessageNotification(String? type) {
    final normalized = (type ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    return <String, dynamic>{
      'title': 'PeerLink',
      'body': _displayNotificationType(normalized),
    };
  }

  String _displayNotificationType(String normalized) {
    switch (normalized) {
      case 'text':
        return 'Text';
      case 'photo':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice':
        return 'Voice';
      case 'geo':
        return 'Location';
      case 'file':
        return 'File';
      default:
        return normalized[0].toUpperCase() +
            (normalized.length > 1 ? normalized.substring(1) : '');
    }
  }

  Map<String, dynamic>? _buildRelayPayload(PushRelayHint? relayHint) {
    if (relayHint == null || relayHint.isEmpty) {
      return null;
    }
    final serverId = relayHint.serverId?.trim();
    final servers =
        relayHint.servers
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final blobId = relayHint.blobId?.trim();
    final relayMessageId = relayHint.relayMessageId?.trim();
    return <String, dynamic>{
      if (serverId != null && serverId.isNotEmpty) 'serverId': serverId,
      if (servers.isNotEmpty) 'servers': servers,
      'scopeKind': relayHint.scopeKind.trim(),
      if (blobId != null && blobId.isNotEmpty) 'blobId': blobId,
      if (relayMessageId != null && relayMessageId.isNotEmpty)
        'relayMessageId': relayMessageId,
    };
  }

  Map<String, dynamic>? _buildServersPayload(PushServersMetadata? servers) {
    if (servers == null) {
      return null;
    }
    return <String, dynamic>{
      'bootstrap': servers.bootstrap,
      'relay': servers.relay,
      'push': servers.push,
      'turn': servers.turn.map((item) => item.toJson()).toList(growable: false),
    };
  }
}
