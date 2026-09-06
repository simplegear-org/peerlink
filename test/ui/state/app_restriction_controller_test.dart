import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/moderation_policy_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/ui/state/app_restriction_controller.dart';
import 'package:peerlink/ui/state/settings_controller.dart';

class _FakeSettingsController implements SettingsController {
  bool accepted = false;

  @override
  bool get isCurrentTermsAccepted => accepted;

  @override
  Future<void> acceptCurrentTerms() async {
    accepted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRestrictionNode implements IdentityApi, ModerationApi, CallsApi {
  Map<String, dynamic>? status;
  int endCallCount = 0;
  CallState currentCallState = CallState.idle;

  @override
  String get peerId => 'peer-1';

  @override
  CallState get callState => currentCallState;

  @override
  Future<void> endCall() async {
    endCallCount += 1;
  }

  @override
  Future<Map<String, dynamic>?> fetchModerationStatus() async => status;

  @override
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late StorageService storage;
  late _FakeSettingsController settings;
  late _FakeRestrictionNode node;

  setUp(() async {
    await StorageService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp(
      'peerlink_restriction_test_',
    );
    storage = StorageService();
    await storage.initForTesting(rootDirectory: tempDir);
    settings = _FakeSettingsController();
    node = _FakeRestrictionNode();
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts terms through settings controller', () async {
    final controller = AppRestrictionController(
      identity: node,
      moderation: node,
      calls: node,
      settingsController: settings,
      storage: storage,
    );

    expect(controller.gate.shouldShowTermsGate, isTrue);

    await controller.acceptCurrentTerms();

    expect(settings.accepted, isTrue);
    expect(controller.gate.shouldShowTermsGate, isFalse);
  });

  test('refresh applies ban and ends active call', () async {
    settings.accepted = true;
    node
      ..status = <String, dynamic>{
        'score': <String, dynamic>{
          'policyState': 'banned',
          'reportCount': 7,
          'reporterCount': 3,
        },
      }
      ..currentCallState = const CallState(
        phase: CallPhase.active,
        peerId: 'peer-2',
        callId: 'call-1',
      );
    final controller = AppRestrictionController(
      identity: node,
      moderation: node,
      calls: node,
      settingsController: settings,
      storage: storage,
    );

    final changed = await controller.refreshModerationStatus(reason: 'test');

    expect(changed, isTrue);
    expect(controller.moderationPolicy.isBanned, isTrue);
    expect(controller.gate.canHandleExternalInteraction, isFalse);
    expect(node.endCallCount, 1);
    expect(ModerationPolicyService.forStorage(storage).load().isBanned, isTrue);
  });
}
