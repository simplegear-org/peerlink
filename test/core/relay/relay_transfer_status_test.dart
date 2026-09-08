import 'package:peerlink/core/relay/relay_transfer_status.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes legacy persisted Russian transfer statuses', () {
    expect(
      RelayTransferStatus.normalize('Ошибка загрузки'),
      RelayTransferStatus.incomingDownloadFailed,
    );
    expect(
      RelayTransferStatus.normalize('Ожидает отправки (2 из 4)'),
      RelayTransferStatus.outgoingWaiting,
    );
    expect(
      RelayTransferStatus.normalize('Сохранение'),
      RelayTransferStatus.incomingSaving,
    );
  });

  test('keeps stable transfer status codes unchanged', () {
    expect(
      RelayTransferStatus.normalize(RelayTransferStatus.incomingDecrypting),
      RelayTransferStatus.incomingDecrypting,
    );
    expect(
      RelayTransferStatus.normalize(RelayTransferStatus.waitingPosition(1, 3)),
      RelayTransferStatus.outgoingWaiting,
    );
  });

  test('classifies transfer failures without localized text matching', () {
    expect(
      RelayTransferStatus.isFailure(RelayTransferStatus.incomingSaveFailed),
      isTrue,
    );
    expect(
      RelayTransferStatus.isFailure(RelayTransferStatus.incomingSaving),
      isFalse,
    );
  });
}
