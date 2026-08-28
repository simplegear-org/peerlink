// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../security/identity_service.dart';
import 'moderation_api_client.dart';
import 'moderation_policy_service.dart';

class ModerationDeliveryService {
  final IdentityService identity;
  final ModerationApiClient apiClient;
  final ModerationPolicyService policyService;
  final List<Uri> Function() resolvePushBaseUris;
  final void Function(String message) log;

  const ModerationDeliveryService({
    required this.identity,
    required this.apiClient,
    required this.policyService,
    required this.resolvePushBaseUris,
    required this.log,
  });

  bool get restrictsOutgoingCommunication =>
      policyService.load().restrictsOutgoingCommunication;

  Future<void> submitReport(Map<String, dynamic> report) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      throw StateError('No push server is configured');
    }
    Object? lastError;
    for (final pushBaseUri in pushBaseUris) {
      try {
        await apiClient.sendReport(
          baseUri: pushBaseUri,
          identity: identity,
          report: report,
        );
        log('moderation report sent push=$pushBaseUri');
        return;
      } catch (error) {
        lastError = error;
        log('moderation report failed push=$pushBaseUri error=$error');
      }
    }
    throw StateError('Moderation report delivery failed: $lastError');
  }

  Future<void> submitAppeal(String text) async {
    final pushBaseUris = resolvePushBaseUris();
    if (pushBaseUris.isEmpty) {
      throw StateError('No push server is configured');
    }
    Object? lastError;
    for (final pushBaseUri in pushBaseUris) {
      try {
        await apiClient.sendAppeal(
          baseUri: pushBaseUri,
          identity: identity,
          text: text,
        );
        log('moderation appeal sent push=$pushBaseUri');
        return;
      } catch (error) {
        lastError = error;
        log('moderation appeal failed push=$pushBaseUri error=$error');
      }
    }
    throw StateError('Moderation appeal delivery failed: $lastError');
  }

  Future<Map<String, dynamic>?> fetchStatus() async {
    Object? lastError;
    for (final pushBaseUri in resolvePushBaseUris()) {
      try {
        final status = await apiClient.fetchStatus(
          baseUri: pushBaseUri,
          peerId: identity.nodeId,
        );
        log('moderation status fetched push=$pushBaseUri');
        return status;
      } catch (error) {
        lastError = error;
        log('moderation status failed push=$pushBaseUri error=$error');
      }
    }
    if (lastError != null) {
      log('moderation status unavailable error=$lastError');
    }
    return null;
  }
}
