// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Locale-independent values stored in [Message.transferStatus].
///
/// Legacy Russian values remain readable through [normalize] so existing
/// persisted messages continue to work after the status-code migration.
class RelayTransferStatus {
  static const String outgoingQueued = 'transfer.outgoing.queued';
  static const String outgoingPreparing = 'transfer.outgoing.preparing';
  static const String outgoingUploadingRelay =
      'transfer.outgoing.uploading_relay';
  static const String outgoingFinalizing = 'transfer.outgoing.finalizing';
  static const String outgoingWaiting = 'transfer.outgoing.waiting';
  static const String outgoingSent = 'transfer.outgoing.sent';
  static const String outgoingSendFailed = 'transfer.outgoing.send_failed';
  static const String outgoingRetrying = 'transfer.outgoing.retrying';

  static const String incomingRelayFetching =
      'transfer.incoming.relay_fetching';
  static const String incomingRetrying = 'transfer.incoming.retrying';
  static const String incomingDownloading = 'transfer.incoming.downloading';
  static const String incomingDownloadComplete =
      'transfer.incoming.download_complete';
  static const String incomingDecrypting = 'transfer.incoming.decrypting';
  static const String incomingSaving = 'transfer.incoming.saving';
  static const String incomingDownloadFailed =
      'transfer.incoming.download_failed';
  static const String incomingDecryptFailed =
      'transfer.incoming.decrypt_failed';
  static const String incomingSaveFailed = 'transfer.incoming.save_failed';
  static const String incomingMessageUpdateFailed =
      'transfer.incoming.message_update_failed';

  static const String relayNotConfigured = 'transfer.relay.not_configured';
  static const String relayUnavailable = 'transfer.relay.unavailable';
  static const String fileUnavailable = 'transfer.file_unavailable';
  static const String notGroupMember = 'transfer.group.not_member';
  static const String noParticipants = 'transfer.group.no_participants';
  static const String canceled = 'transfer.canceled';

  static String waitingPosition(int position, int total) =>
      '$outgoingWaiting:$position:$total';

  static String? normalize(String? status) {
    final value = status?.trim();
    if (value == null || value.isEmpty) {
      return value;
    }
    if (value.startsWith('Ожидает отправки')) {
      return outgoingWaiting;
    }
    if (value.startsWith('$outgoingWaiting:')) {
      return outgoingWaiting;
    }
    return switch (value) {
      'В очереди' => outgoingQueued,
      'Подготовка' => outgoingPreparing,
      'Загрузка в relay' => outgoingUploadingRelay,
      'Финализация' => outgoingFinalizing,
      'Ожидает отправки' => outgoingWaiting,
      'Отправлено' => outgoingSent,
      'Ошибка отправки' => outgoingSendFailed,
      'Повторная отправка' => outgoingRetrying,
      'Получение из relay' => incomingRelayFetching,
      'Повторная загрузка' => incomingRetrying,
      'Загрузка' => incomingDownloading,
      'Загрузка завершена' => incomingDownloadComplete,
      'Расшифровка' => incomingDecrypting,
      'Сохранение' => incomingSaving,
      'Ошибка загрузки' => incomingDownloadFailed,
      'Ошибка расшифровки' => incomingDecryptFailed,
      'Ошибка сохранения' => incomingSaveFailed,
      'Ошибка обновления сообщения' => incomingMessageUpdateFailed,
      'Relay не настроен' => relayNotConfigured,
      'Relay недоступен' => relayUnavailable,
      'Файл недоступен' || 'Не удалось прочитать файл' => fileUnavailable,
      'Вы больше не участник чата' => notGroupMember,
      'Нет участников для отправки' => noParticipants,
      'Отменено' => canceled,
      _ => value,
    };
  }

  static bool isQueued(String? status) {
    final value = normalize(status);
    return value == outgoingQueued || value == outgoingWaiting;
  }

  static bool isRecoverableOutgoing(String? status) {
    final value = normalize(status);
    return value == outgoingQueued ||
        value == outgoingPreparing ||
        value == outgoingWaiting;
  }

  static bool isCanceled(String? status) => normalize(status) == canceled;

  static bool isFailure(String? status) {
    return switch (normalize(status)) {
      outgoingSendFailed ||
      incomingDownloadFailed ||
      incomingDecryptFailed ||
      incomingSaveFailed ||
      incomingMessageUpdateFailed ||
      relayNotConfigured ||
      relayUnavailable ||
      fileUnavailable ||
      notGroupMember ||
      noParticipants => true,
      _ => false,
    };
  }
}
