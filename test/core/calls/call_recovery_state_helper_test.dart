import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_recovery_state_helper.dart';

void main() {
  const helper = CallRecoveryStateHelper();

  group('CallRecoveryStateHelper', () {
    test('tracks active ICE recovery as visible recovery phase', () {
      const activeState = CallState(
        phase: CallPhase.active,
        mediaType: CallMediaType.video,
      );

      final recovering = helper.startRecovery(
        currentState: activeState,
        kind: CallRecoveryKind.ice,
        status: 'Восстанавливаем соединение',
      );

      expect(recovering.phase, CallPhase.recovering);
      expect(recovering.recoveryKind, CallRecoveryKind.ice);
      expect(recovering.recoveryAttempt, 1);
      expect(recovering.recoveryReturnPhase, CallPhase.active);
      expect(recovering.debugStatus, 'Восстанавливаем соединение');

      final restored = helper.completeRecovery(
        currentState: recovering,
        status: 'Соединение восстановлено',
      );

      expect(restored.phase, CallPhase.active);
      expect(restored.recoveryKind, isNull);
      expect(restored.recoveryAttempt, 0);
      expect(restored.recoveryReturnPhase, isNull);
    });

    test('increments attempt while staying in same recovery kind', () {
      final first = helper.startRecovery(
        currentState: const CallState(phase: CallPhase.connecting),
        kind: CallRecoveryKind.ice,
        status: 'Восстанавливаем ICE',
      );
      final second = helper.startRecovery(
        currentState: first,
        kind: CallRecoveryKind.ice,
        status: 'Повторно восстанавливаем ICE',
      );

      expect(second.phase, CallPhase.recovering);
      expect(second.recoveryAttempt, 2);
      expect(second.recoveryReturnPhase, CallPhase.connecting);
    });

    test('switches recovery kind with reset attempt counter', () {
      final iceRecovery = helper.startRecovery(
        currentState: const CallState(phase: CallPhase.active),
        kind: CallRecoveryKind.ice,
        status: 'Восстанавливаем ICE',
      );
      final cameraRecovery = helper.startRecovery(
        currentState: iceRecovery,
        kind: CallRecoveryKind.camera,
        status: 'Переключаем камеру',
      );

      expect(cameraRecovery.recoveryKind, CallRecoveryKind.camera);
      expect(cameraRecovery.recoveryAttempt, 1);
      expect(cameraRecovery.recoveryReturnPhase, CallPhase.active);
    });
  });
}
