import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../calls/call_models.dart';
import '../firebase/firebase_push_payload.dart';
import '../node/node_facade.dart';
import 'app_file_logger.dart';
import 'contact_name_resolver.dart';
import 'push_token_service.dart';
import 'storage_service.dart';

typedef IosCallkitPushPayloadHandler =
    Future<void> Function(
      Map<String, dynamic> payload, {
      required String source,
    });

typedef IosCallkitCallStateGetter = CallState Function();
typedef IosCallkitCallStateStreamGetter = Stream<CallState> Function();
typedef IosCallkitPresentIncomingCallCallback =
    Future<void> Function({
      required String peerId,
      required String callId,
      required CallMediaType mediaType,
    });
typedef IosCallkitVoidCallback = Future<void> Function();
typedef IosCallkitSpeakerCallback = Future<void> Function(bool enabled);
typedef IosCallkitRegisterPushTokenCallback =
    Future<void> Function(String? token);

class IosCallkitFacadeAdapter {
  const IosCallkitFacadeAdapter({
    required this.getCallState,
    required this.getCallStateStream,
    required this.presentIncomingCallFromPush,
    required this.acceptIncomingCall,
    required this.rejectIncomingCall,
    required this.endCall,
    required this.setCallSpeakerOn,
    required this.registerPushDeviceToken,
  });

  final IosCallkitCallStateGetter getCallState;
  final IosCallkitCallStateStreamGetter getCallStateStream;
  final IosCallkitPresentIncomingCallCallback presentIncomingCallFromPush;
  final IosCallkitVoidCallback acceptIncomingCall;
  final IosCallkitVoidCallback rejectIncomingCall;
  final IosCallkitVoidCallback endCall;
  final IosCallkitSpeakerCallback setCallSpeakerOn;
  final IosCallkitRegisterPushTokenCallback registerPushDeviceToken;

  factory IosCallkitFacadeAdapter.fromNodeFacade(NodeFacade facade) {
    return IosCallkitFacadeAdapter(
      getCallState: () => facade.callState,
      getCallStateStream: () => facade.callStateStream,
      presentIncomingCallFromPush:
          ({
            required String peerId,
            required String callId,
            required CallMediaType mediaType,
          }) {
            return facade.presentIncomingCallFromPush(
              peerId: peerId,
              callId: callId,
              mediaType: mediaType,
            );
          },
      acceptIncomingCall: facade.acceptIncomingCall,
      rejectIncomingCall: facade.rejectIncomingCall,
      endCall: facade.endCall,
      setCallSpeakerOn: facade.setCallSpeakerOn,
      registerPushDeviceToken: facade.registerPushDeviceToken,
    );
  }
}

class IosCallkitService {
  IosCallkitService._({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool Function()? isIosOverride,
  }) : _methodChannel =
           methodChannel ??
           const MethodChannel('peerlink/callkit/methods'),
       _eventChannel =
           eventChannel ?? const EventChannel('peerlink/callkit/events'),
       _isIosOverride = isIosOverride;

  static final IosCallkitService instance = IosCallkitService._();

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final bool Function()? _isIosOverride;

  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<CallState>? _callStateSubscription;
  final StreamController<void> _openCallScreenController =
      StreamController<void>.broadcast();
  IosCallkitFacadeAdapter? _facade;
  IosCallkitPushPayloadHandler? _onPushPayload;
  final StorageService _storage = StorageService();
  final PushTokenService _pushTokens = PushTokenService();
  String? _lastVoipToken;
  String? _lastPresentedCallId;
  String? _lastOutgoingReportedCallId;
  bool _lastOutgoingReportedConnected = false;
  bool _hadBusyCallState = false;
  bool _refreshInFlight = false;

  Stream<void> get onOpenCallScreen => _openCallScreenController.stream;

  @visibleForTesting
  factory IosCallkitService.test({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool Function()? isIosOverride,
  }) {
    return IosCallkitService._(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
      isIosOverride: isIosOverride,
    );
  }

  Future<void> initialize(
    NodeFacade facade, {
    IosCallkitPushPayloadHandler? onPushPayload,
  }) async {
    return initializeWithAdapter(
      IosCallkitFacadeAdapter.fromNodeFacade(facade),
      onPushPayload: onPushPayload,
    );
  }

  @visibleForTesting
  Future<void> initializeWithAdapter(
    IosCallkitFacadeAdapter facade, {
    IosCallkitPushPayloadHandler? onPushPayload,
  }) async {
    if (!_isSupportedPlatform()) {
      return;
    }
    _facade = facade;
    _onPushPayload = onPushPayload;
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppFileLogger.log(
          '[callkit] event stream error=$error',
          name: 'callkit',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    _callStateSubscription ??= facade.getCallStateStream().listen(_syncCallState);
    await refreshVoipRegistration(reason: 'initialize');
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _callStateSubscription?.cancel();
    _eventSubscription = null;
    _callStateSubscription = null;
    _facade = null;
    _onPushPayload = null;
    _hadBusyCallState = false;
    _refreshInFlight = false;
  }

  Future<void> refreshVoipRegistration({String reason = 'manual'}) async {
    if (!_isSupportedPlatform() || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      AppFileLogger.log(
        '[callkit] refresh voip registration reason=$reason',
        name: 'callkit',
      );
      try {
        await _methodChannel.invokeMethod<void>('refreshVoipRegistration');
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[callkit] native refreshVoipRegistration failed error=$error',
          name: 'callkit',
          error: error,
          stackTrace: stackTrace,
        );
      }
      final token = await _methodChannel.invokeMethod<String>('getVoipToken');
      await _registerVoipTokenIfNeeded(token, force: true);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[callkit] getVoipToken failed error=$error',
        name: 'callkit',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _handleNativeEvent(dynamic event) async {
    final facade = _facade;
    if (facade == null || event is! Map) {
      return;
    }
    final map = Map<String, dynamic>.from(event.cast<dynamic, dynamic>());
    final type = (map['type'] ?? '').toString().trim().toLowerCase();
    AppFileLogger.log(
      '[callkit] native event type=$type '
      'keys=${map.keys.join(",")} '
      'serversLength=${(map['servers'] ?? '').toString().length} '
      'priorityServersLength=${(map['priority_servers'] ?? '').toString().length}',
      name: 'callkit',
    );
    if (type == 'voip_token') {
      await _registerVoipTokenIfNeeded(map['token']?.toString());
      return;
    }
    if (type == 'call_incoming') {
      final payload = FirebasePushPayload.fromMap(map);
      if (!payload.hasPeerAndCallId) {
        return;
      }
      await _applyPushPayload(map, source: 'call_incoming');
      await facade.presentIncomingCallFromPush(
        peerId: payload.callPeerId,
        callId: payload.callId,
        mediaType: payload.callMediaType,
      );
      final localName = await _resolveLocalContactName(payload.callPeerId);
      if (localName != null) {
        try {
          await _methodChannel.invokeMethod<void>('updateIncomingCallerName', {
            'callId': payload.callId,
            'displayName': localName,
          });
        } catch (error, stackTrace) {
          AppFileLogger.log(
            '[callkit] updateIncomingCallerName failed error=$error',
            name: 'callkit',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      return;
    }
    if (type == 'call_action') {
      final action = (map['action'] ?? '').toString().trim().toLowerCase();
      if (action == 'accept') {
        final payload = FirebasePushPayload.fromMap(map);
        final state = facade.getCallState();
        final shouldRestoreIncomingState =
            !state.isIncoming && !state.isBusy && payload.hasPeerAndCallId;
        if (shouldRestoreIncomingState) {
          await facade.presentIncomingCallFromPush(
            peerId: payload.callPeerId,
            callId: payload.callId,
            mediaType: payload.callMediaType,
          );
        }
        await _applyPushPayload(map, source: 'call_accept');
        await facade.acceptIncomingCall();
      } else if (action == 'reject') {
        await facade.rejectIncomingCall();
      } else if (action == 'end') {
        await facade.endCall();
      }
      return;
    }
    if (type == 'audio_session_activated') {
      final state = facade.getCallState();
      if (state.isBusy) {
        try {
          await facade.setCallSpeakerOn(state.speakerOn);
          AppFileLogger.log(
            '[callkit] audio session activated, reapplied speaker=${state.speakerOn}',
            name: 'callkit',
          );
        } catch (error, stackTrace) {
          AppFileLogger.log(
            '[callkit] reapply speaker failed error=$error',
            name: 'callkit',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      return;
    }
    if (type == 'audio_session_deactivated') {
      AppFileLogger.log('[callkit] audio session deactivated', name: 'callkit');
      return;
    }
    if (type == 'open_call_screen') {
      _openCallScreenController.add(null);
      return;
    }
  }

  Future<void> _applyPushPayload(
    Map<String, dynamic> payload, {
    required String source,
  }) async {
    final handler = _onPushPayload;
    if (handler == null) {
      return;
    }
    try {
      await handler(Map<String, dynamic>.from(payload), source: source);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[callkit] push payload handler failed source=$source error=$error',
        name: 'callkit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _registerVoipTokenIfNeeded(
    String? token, {
    bool force = false,
  }) async {
    final facade = _facade;
    if (facade == null) {
      return;
    }
    final normalized = (token ?? '').trim();
    if (normalized.isEmpty) {
      return;
    }
    if (!force && normalized == _lastVoipToken) {
      return;
    }
    _lastVoipToken = normalized;
    try {
      await _storage.init();
      await _pushTokens.saveVoipToken(normalized);
    } catch (_) {}
    try {
      await facade.registerPushDeviceToken(null);
      AppFileLogger.log('[callkit] voip token registered', name: 'callkit');
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[callkit] register voip token failed error=$error',
        name: 'callkit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncCallState(CallState state) async {
    if (!_isSupportedPlatform()) {
      return;
    }
    await _syncOutgoingCallState(state);
    if (state.isBusy) {
      _hadBusyCallState = true;
      return;
    }
    final shouldDismissSystemCallUi =
        _hadBusyCallState &&
        (state.phase == CallPhase.idle ||
            state.phase == CallPhase.ended ||
            state.phase == CallPhase.failed);
    if (shouldDismissSystemCallUi) {
      _hadBusyCallState = false;
      _lastOutgoingReportedCallId = null;
      _lastOutgoingReportedConnected = false;
      try {
        await _methodChannel.invokeMethod<void>('endSystemCall');
      } catch (_) {}
    }
  }

  Future<void> _syncOutgoingCallState(CallState state) async {
    final isReportableOutgoingState =
        state.direction == CallDirection.outgoing &&
        (state.phase == CallPhase.outgoingRinging ||
            state.phase == CallPhase.connecting ||
            state.phase == CallPhase.active);
    if (!isReportableOutgoingState) {
      if (!state.isBusy) {
        _lastOutgoingReportedCallId = null;
        _lastOutgoingReportedConnected = false;
      }
      return;
    }

    final callId = (state.callId ?? '').trim();
    final peerId = (state.peerId ?? '').trim();
    if (callId.isEmpty || peerId.isEmpty) {
      return;
    }
    final displayName = await _resolveLocalContactName(peerId);
    if (_lastOutgoingReportedCallId != callId) {
      _lastOutgoingReportedCallId = callId;
      _lastOutgoingReportedConnected = false;
      try {
        await _methodChannel.invokeMethod<void>('startOutgoingCall', {
          'callId': callId,
          'peerId': peerId,
          'mediaType': state.mediaType.name,
          'displayName': displayName,
        });
        AppFileLogger.log(
          '[callkit] start outgoing reported callId=$callId peerId=$peerId',
          name: 'callkit',
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[callkit] start outgoing report failed error=$error',
          name: 'callkit',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    final connected = state.phase == CallPhase.active;
    final shouldUpdate =
        displayName != null || connected != _lastOutgoingReportedConnected;
    if (!shouldUpdate) {
      return;
    }
    _lastOutgoingReportedConnected = connected;
    try {
      await _methodChannel.invokeMethod<void>('updateOutgoingCall', {
        'callId': callId,
        'connected': connected,
        'displayName': displayName,
      });
      AppFileLogger.log(
        '[callkit] update outgoing reported callId=$callId connected=$connected',
        name: 'callkit',
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[callkit] update outgoing report failed error=$error',
        name: 'callkit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> notifyCallUiPresented(String? callId) async {
    if (!_isSupportedPlatform()) {
      return;
    }
    final normalizedCallId = (callId ?? '').trim();
    if (normalizedCallId.isEmpty || normalizedCallId == _lastPresentedCallId) {
      return;
    }
    _lastPresentedCallId = normalizedCallId;
    try {
      await _methodChannel.invokeMethod<void>('callUiPresented', {
        'callId': normalizedCallId,
      });
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> handleNativeEventForTesting(Map<String, dynamic> event) {
    return _handleNativeEvent(event);
  }

  bool _isSupportedPlatform() {
    if (kIsWeb) {
      return false;
    }
    final override = _isIosOverride;
    if (override != null) {
      return override();
    }
    return Platform.isIOS;
  }

  Future<String?> _resolveLocalContactName(String peerId) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      return null;
    }
    try {
      await _storage.init();
      final contacts = _storage.getContacts();
      Object? raw = contacts.get(normalizedPeerId);
      raw ??= contacts.get(normalizedPeerId.toLowerCase());
      raw ??= contacts.get(normalizedPeerId.toUpperCase());
      if (raw == null) {
        for (final key in contacts.keys) {
          if (key.trim().toLowerCase() == normalizedPeerId.toLowerCase()) {
            raw = contacts.get(key);
            break;
          }
        }
      }
      final resolved = ContactNameResolver.resolveFromEntry(
        raw,
        peerId: normalizedPeerId,
      ).trim();
      if (resolved.isEmpty || resolved == normalizedPeerId) {
        return null;
      }
      return resolved;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[callkit] local contact resolve failed peer=$normalizedPeerId error=$error',
        name: 'callkit',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
