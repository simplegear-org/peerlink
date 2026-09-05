import 'package:peerlink/core/runtime/self_hosted_deploy_service.dart';
import 'package:peerlink/ui/localization/app_language.dart';
import 'package:peerlink/ui/localization/app_strings.dart';
import 'package:test/test.dart';

void main() {
  test('self-hosted deploy stages are localized', () {
    const event = SelfHostedDeployStageEvent(
      stage: 1,
      totalStages: 14,
      kind: SelfHostedDeployStageKind.connectToServer,
    );

    final ru = const AppStrings(AppLanguage.ru).deployStage(
      event.stage,
      event.totalStages,
      const AppStrings(AppLanguage.ru).deployStageMessage(event),
    );
    final en = const AppStrings(AppLanguage.en).deployStage(
      event.stage,
      event.totalStages,
      const AppStrings(AppLanguage.en).deployStageMessage(event),
    );

    expect(ru, 'Этап 1/14: Подключение к серверу');
    expect(en, 'Step 1/14: Connect to server');
  });

  test('self-hosted deploy remote command error is localized', () {
    expect(
      const AppStrings(AppLanguage.ru).remoteCommandFailed(141),
      'Удаленная команда завершилась с кодом 141',
    );
    expect(
      const AppStrings(AppLanguage.en).remoteCommandFailed(141),
      'Remote command exited with code 141',
    );
  });

  test('self-hosted deploy readiness retry is localized', () {
    const event = SelfHostedDeployReadinessEvent(
      service: SelfHostedDeployServiceKind.relay,
      kind: SelfHostedDeployReadinessKind.notReadyYet,
      attempt: 2,
      error: 'connection refused',
    );

    expect(
      const AppStrings(AppLanguage.ru).deployReadiness(event),
      'relay еще не готов, повтор #2: connection refused',
    );
    expect(
      const AppStrings(AppLanguage.en).deployReadiness(event),
      'relay is not ready yet, retry #2: connection refused',
    );
  });
}
