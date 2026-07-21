import 'dart:convert';

import '../calls/call_models.dart';

class FirebasePushPayload {
  final Map<String, dynamic> root;
  final Map<String, dynamic>? nestedData;
  final String type;
  final String senderPeerId;
  final String callId;
  final String callAction;
  final String mediaType;
  final String relayMessageId;
  final String groupId;
  final String directPeerId;
  final String notificationText;

  const FirebasePushPayload({
    required this.root,
    required this.nestedData,
    required this.type,
    required this.senderPeerId,
    required this.callId,
    required this.callAction,
    required this.mediaType,
    required this.relayMessageId,
    required this.groupId,
    required this.directPeerId,
    required this.notificationText,
  });

  factory FirebasePushPayload.fromMap(Map<String, dynamic> data) {
    final nestedData = _extractNestedData(data);
    return FirebasePushPayload(
      root: Map<String, dynamic>.from(data),
      nestedData: nestedData,
      type: _readString(data, nestedData, const <String>['type']).toLowerCase(),
      senderPeerId: _readString(data, nestedData, const <String>[
        'fromPeerId',
        'peerId',
        'callerUserId',
        'senderUserId',
      ]),
      callId: _readString(data, nestedData, const <String>[
        'callId',
        'call_id',
      ]),
      callAction: _readString(data, nestedData, const <String>[
        'callAction',
        'call_action',
      ]).toLowerCase(),
      mediaType: _readString(data, nestedData, const <String>[
        'mediaType',
        'media_type',
      ]).toLowerCase(),
      relayMessageId: _readString(data, nestedData, const <String>[
        'relayMessageId',
      ]),
      groupId: _readString(data, nestedData, const <String>['groupId']),
      directPeerId: _readString(data, nestedData, const <String>[
        'directPeerId',
      ]),
      notificationText: _readString(data, nestedData, const <String>[
        'message',
        'text',
      ]),
    );
  }

  bool get isCallInvite => type == 'call_invite';

  bool get isCallEnd => callAction == 'end' || mediaType == 'end';

  bool get isCallPayload => isCallInvite || isCallEnd;

  bool get isVideoCall => mediaType == CallMediaType.video.name;

  CallMediaType get callMediaType =>
      isVideoCall ? CallMediaType.video : CallMediaType.audio;

  String get callPeerId => senderPeerId;

  bool get hasPeerAndCallId => callPeerId.isNotEmpty && callId.isNotEmpty;

  bool get isAccountMembershipUpdate => type == 'account_membership_update';

  bool get isGroupMembersUpdate =>
      type == 'group_members_update' || type == 'group_members';

  bool get isMessageLike =>
      type == 'group_update' || type == 'message' || type == 'direct_update';

  bool get hasRelayHint =>
      relayMessageId.isNotEmpty ||
      groupId.isNotEmpty ||
      directPeerId.isNotEmpty;

  Object? get rawServers =>
      _readValue(root, nestedData, const <String>['servers']);

  Object? get rawPriorityServers =>
      _readValue(root, nestedData, const <String>['priority_servers']);

  Object? get rawRelay => _readValue(root, nestedData, const <String>['relay']);

  List<String> get relayServers {
    final raw = rawRelay;
    if (raw is! Map) {
      return const <String>[];
    }
    final servers = raw['servers'];
    if (servers is! List) {
      return const <String>[];
    }
    return servers
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  Object? get rawAccountMembershipUpdate =>
      _readValue(root, nestedData, const <String>['accountMembershipUpdate']);

  Object? get rawGroupMembers =>
      _readValue(root, nestedData, const <String>['groupMembers']);

  static Map<String, dynamic>? _extractNestedData(Map<String, dynamic> data) {
    final nested = data['data'];
    if (nested is Map) {
      return nested.map((key, value) => MapEntry(key.toString(), value));
    }
    if (nested is String && nested.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(nested);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _readString(
    Map<String, dynamic> data,
    Map<String, dynamic>? nestedData,
    List<String> keys,
  ) {
    final value = _readValue(data, nestedData, keys);
    return value?.toString().trim() ?? '';
  }

  static Object? _readValue(
    Map<String, dynamic> data,
    Map<String, dynamic>? nestedData,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return data[key];
      }
      if (nestedData != null && nestedData.containsKey(key)) {
        return nestedData[key];
      }
    }
    return null;
  }
}
