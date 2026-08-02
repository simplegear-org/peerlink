import '../security/identity_service.dart';
import 'push_api_client.dart';
import 'push_event_factory.dart';
import 'push_payload_size_limiter.dart';

class PushEventService {
  PushEventService({
    required this.identity,
    required this.pushApiClient,
    required this.resolvePushBaseUris,
    required this.pushBearerToken,
    required this.log,
    this.payloadSizeLimiter = const PushPayloadSizeLimiter(),
  });

  final IdentityService identity;
  final PushApiClient pushApiClient;
  final List<Uri> Function() resolvePushBaseUris;
  final String? Function() pushBearerToken;
  final void Function(String message) log;
  final PushPayloadSizeLimiter payloadSizeLimiter;

  Future<void> send(PushEventDraft draft, {required String logLabel}) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      log('$logLabel skip: no endpoint');
      return;
    }
    final bearerToken = pushBearerToken();
    final payload = payloadSizeLimiter.compact(draft.payload);
    final originalSize = payloadSizeLimiter.transportSizeBytes(draft.payload);
    final compactedSize = payloadSizeLimiter.transportSizeBytes(payload);
    if (compactedSize < originalSize) {
      log('$logLabel compacted payload bytes=$originalSize->$compactedSize');
    }
    await Future.wait(
      pushBaseUris.map(
        (pushBaseUri) => pushApiClient.sendPushEvent(
          baseUri: pushBaseUri,
          identity: identity,
          senderUserId: identity.nodeId,
          recipientUserIds: draft.recipientUserIds,
          payload: payload,
          notification: draft.notification,
          delivery: draft.delivery,
          bearerToken: bearerToken,
        ),
      ),
    );
  }
}
