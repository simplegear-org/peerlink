import '../calls/call_models.dart';
import '../push/push_api_client.dart';
import '../push/push_event_factory.dart';
import '../push/push_event_service.dart';
import '../push/push_runtime_metadata_builder.dart';
import '../runtime/push_token_service.dart';
import '../security/identity_service.dart';

class MeshCallPushHelper {
  MeshCallPushHelper({
    required this.identity,
    required this.pushApiClient,
    required this.pushTokens,
    required this.resolvePushBaseUris,
    required this.pushBearerToken,
    required this.pushEventFactory,
    required this.pushEventService,
    required this.pushRuntimeMetadataBuilder,
    required this.platformName,
    required this.log,
  });

  final IdentityService identity;
  final PushApiClient pushApiClient;
  final PushTokenService pushTokens;
  final List<Uri> Function() resolvePushBaseUris;
  final String? Function() pushBearerToken;
  final PushEventFactory pushEventFactory;
  final PushEventService pushEventService;
  final PushRuntimeMetadataBuilder pushRuntimeMetadataBuilder;
  final String Function() platformName;
  final void Function(String message) log;
  String? _lastRegisterSignature;
  Future<void>? _registerFuture;

  Future<void> registerPushDeviceToken(String? token) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      log('push register skip: no endpoint');
      return;
    }
    final platform = platformName();
    final isApple = platform == 'ios' || platform == 'macos';
    final messageToken = isApple
        ? (pushTokens.apnsToken ?? '').trim()
        : (token ?? pushTokens.fcmToken ?? '').trim();
    final voipToken = isApple ? (pushTokens.voipToken ?? '').trim() : '';
    final messageProvider = isApple ? 'apns' : 'fcm';
    if (messageToken.isEmpty) {
      log(
        'push register skip: empty messageToken baseUris=${pushBaseUris.join(",")} '
        'platform=$platform hasVoip=${voipToken.isNotEmpty}',
      );
      return;
    }
    final registerSignature = _buildRegisterSignature(
      pushBaseUris: pushBaseUris,
      messageToken: messageToken,
      voipToken: voipToken,
      platform: platform,
    );
    if (_lastRegisterSignature == registerSignature) {
      log('push register skip: unchanged endpoints=${pushBaseUris.length}');
      return;
    }
    final inFlight = _registerFuture;
    if (inFlight != null) {
      if (_lastRegisterSignature == registerSignature) {
        log('push register skip: identical request in-flight');
        return inFlight;
      }
      await inFlight;
      if (_lastRegisterSignature == registerSignature) {
        log('push register skip: identical request already completed');
        return;
      }
    }
    final future = _registerPushDeviceTokenImpl(
      pushBaseUris: pushBaseUris,
      platform: platform,
      messageToken: messageToken,
      messageProvider: messageProvider,
      voipToken: voipToken,
      registerSignature: registerSignature,
    );
    _registerFuture = future;
    try {
      await future;
    } finally {
      if (identical(_registerFuture, future)) {
        _registerFuture = null;
      }
    }
  }

  Future<void> _registerPushDeviceTokenImpl({
    required List<Uri> pushBaseUris,
    required String platform,
    required String messageToken,
    required String messageProvider,
    required String voipToken,
    required String registerSignature,
  }) async {
    log(
      'push register start baseUris=${pushBaseUris.join(",")} platform=$platform '
      'messageTokenLength=${messageToken.length} hasVoip=${voipToken.isNotEmpty}',
    );
    final bearerToken = pushBearerToken();
    await Future.wait(
      pushBaseUris.map(
        (pushBaseUri) => pushApiClient.registerDevice(
          baseUri: pushBaseUri,
          identity: identity,
          userId: identity.nodeId,
          deviceId: identity.deviceId,
          messageToken: messageToken,
          messageProvider: messageProvider,
          voipToken: voipToken.isEmpty ? null : voipToken,
          platform: platform,
          appVersion: '',
          bearerToken: bearerToken,
        ),
      ),
    );
    _lastRegisterSignature = registerSignature;
    log(
      'push register done userId=${identity.nodeId} deviceId=${identity.deviceId} '
      'provider=$messageProvider hasVoip=${voipToken.isNotEmpty} endpoints=${pushBaseUris.length}',
    );
  }

  Future<void> registerVoipDeviceToken(String token) {
    return registerPushDeviceToken(token);
  }

  Future<void> unregisterPushDeviceToken(String token) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      log('push unregister skip: no endpoint');
      return;
    }
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      log('push unregister skip: empty token');
      return;
    }
    final bearerToken = pushBearerToken();
    await Future.wait(
      pushBaseUris.map(
        (pushBaseUri) => pushApiClient.unregisterDevice(
          baseUri: pushBaseUri,
          identity: identity,
          userId: identity.nodeId,
          deviceId: identity.deviceId,
          token: normalizedToken,
          bearerToken: bearerToken,
        ),
      ),
    );
    _lastRegisterSignature = null;
    log(
      'push unregister done userId=${identity.nodeId} deviceId=${identity.deviceId} '
      'endpoints=${pushBaseUris.length}',
    );
  }

  Future<void> unregisterVoipDeviceToken(String token) async {}

  Future<void> sendCallInvitePushEvent({
    required String calleeUserId,
    required String callId,
    required CallMediaType mediaType,
  }) async {
    final draft = pushEventFactory.buildCallInvite(
      callerUserId: identity.nodeId,
      calleeUserId: calleeUserId,
      callId: callId,
      mediaType: mediaType,
      servers: pushRuntimeMetadataBuilder.collectAvailableServers(),
      priorityServers: pushRuntimeMetadataBuilder.collectPriorityCallServers(
        calleeUserId,
      ),
    );
    await pushEventService.send(draft, logLabel: 'push call event');
    log(
      'push call event done caller=${identity.nodeId} callee=$calleeUserId '
      'callId=$callId mediaType=${mediaType.name}',
    );
  }

  Future<void> sendCallEndPushEvent({
    required String calleeUserId,
    required String callId,
  }) async {
    final draft = pushEventFactory.buildCallEnd(
      callerUserId: identity.nodeId,
      calleeUserId: calleeUserId,
      callId: callId,
    );
    await pushEventService.send(draft, logLabel: 'push call end');
    log(
      'push call end done caller=${identity.nodeId} callee=$calleeUserId callId=$callId',
    );
  }

  String _buildRegisterSignature({
    required List<Uri> pushBaseUris,
    required String messageToken,
    required String voipToken,
    required String platform,
  }) {
    final endpoints = pushBaseUris
        .map((item) => item.toString())
        .toList(growable: false)
      ..sort();
    return '${endpoints.join(",")}|$messageToken|$voipToken|$platform';
  }
}
