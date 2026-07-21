import '../security/identity_service.dart';
import 'push_api_client.dart';
import 'push_event_factory.dart';

class PushEventService {
  PushEventService({
    required this.identity,
    required this.pushApiClient,
    required this.resolvePushBaseUris,
    required this.pushBearerToken,
    required this.log,
  });

  final IdentityService identity;
  final PushApiClient pushApiClient;
  final List<Uri> Function() resolvePushBaseUris;
  final String? Function() pushBearerToken;
  final void Function(String message) log;

  Future<void> send(PushEventDraft draft, {required String logLabel}) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      log('$logLabel skip: no endpoint');
      return;
    }
    final bearerToken = pushBearerToken();
    await Future.wait(
      pushBaseUris.map(
        (pushBaseUri) => pushApiClient.sendPushEvent(
          baseUri: pushBaseUri,
          identity: identity,
          senderUserId: identity.nodeId,
          recipientUserIds: draft.recipientUserIds,
          payload: draft.payload,
          notification: draft.notification,
          delivery: draft.delivery,
          bearerToken: bearerToken,
        ),
      ),
    );
  }
}
