import 'package:peerlink/core/relay/relay_transfer_status.dart';
import 'package:peerlink/ui/localization/app_language.dart';
import 'package:peerlink/ui/localization/app_strings.dart';
import 'package:test/test.dart';

void main() {
  test('localizes stable transfer status codes', () {
    const ru = AppStrings(AppLanguage.ru);
    const en = AppStrings(AppLanguage.en);

    expect(
      ru.translateTransferStatus(RelayTransferStatus.incomingDecrypting),
      'Расшифровка',
    );
    expect(
      en.translateTransferStatus(RelayTransferStatus.incomingDecrypting),
      'Decrypting',
    );
    expect(
      en.translateTransferStatus(RelayTransferStatus.incomingSaveFailed),
      'Save error',
    );
    expect(
      ru.translateTransferStatus(RelayTransferStatus.incomingDownloadComplete),
      'Загрузка',
    );
  });

  test('localizes legacy persisted transfer statuses through migration', () {
    const en = AppStrings(AppLanguage.en);

    expect(en.translateTransferStatus('Ошибка загрузки'), 'Download error');
    expect(en.translateTransferStatus('Сохранение'), 'Saving');
  });
}
