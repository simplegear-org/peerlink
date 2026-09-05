import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('validation workflow runs required refactor guard commands', () {
    final workflow = File(
      '.github/workflows/validation.yml',
    ).readAsStringSync();

    expect(
      workflow,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test'));
  });

  test('required architecture guardrail suites exist', () {
    for (final path in _requiredArchitectureSuites) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
    }
  });

  test('required capability contract suites exist', () {
    for (final path in _requiredCapabilitySuites) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
    }
  });

  test('required critical-flow tests exist', () {
    for (final path in _requiredCriticalFlowTests) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
    }
  });
}

const _requiredArchitectureSuites = {
  'test/architecture/composition_dependency_test.dart',
  'test/architecture/feature_boundary_test.dart',
  'test/architecture/presentation_dependency_test.dart',
  'test/architecture/runtime_cleanup_test.dart',
  'test/architecture/shared_infrastructure_test.dart',
};

const _requiredCapabilitySuites = {
  'test/core/messaging/chat_service_test.dart',
  'test/core/calls/call_service_test.dart',
  'test/core/runtime/storage_service_chat_messages_test.dart',
  'test/core/runtime/peer_access_control_service_test.dart',
  'test/core/runtime/push_access_policy_sync_service_test.dart',
  'test/core/runtime/moderation_policy_service_test.dart',
};

const _requiredCriticalFlowTests = {
  'test/core/node/mesh_node_smoke_test.dart',
  'test/core/calls/call_service_smoke_test.dart',
  'test/core/calls/call_service_test.dart',
  'test/core/messaging/chat_service_test.dart',
  'test/ui/state/chat_inbound_service_test.dart',
  'test/ui/state/relay_media_transfer_service_test.dart',
  'test/ui/state/chat_outgoing_relay_media_resume_service_test.dart',
  'test/app/push/app_push_coordinator_test.dart',
  'test/ui/state/app_restriction_controller_test.dart',
};
