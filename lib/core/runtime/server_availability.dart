// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class ServerAvailability {
  final bool? isAvailable;
  final String? error;
  final DateTime? checkedAt;

  const ServerAvailability({
    required this.isAvailable,
    this.error,
    this.checkedAt,
  });

  const ServerAvailability.unknown()
      : isAvailable = null,
        error = null,
        checkedAt = null;

  factory ServerAvailability.available({DateTime? checkedAt}) {
    return ServerAvailability(
      isAvailable: true,
      checkedAt: checkedAt,
    );
  }

  factory ServerAvailability.unavailable({
    required String error,
    DateTime? checkedAt,
  }) {
    return ServerAvailability(
      isAvailable: false,
      error: error,
      checkedAt: checkedAt,
    );
  }

  String label({
    String availableLabel = 'доступен',
    String unavailableLabel = 'ошибка подключения',
    String unknownLabel = 'ожидание проверки',
    bool includeErrorDetails = false,
  }) {
    if (isAvailable == null) {
      return unknownLabel;
    }
    if (isAvailable == true) {
      return availableLabel;
    }
    if (!includeErrorDetails || error == null || error!.trim().isEmpty) {
      return unavailableLabel;
    }
    return '$unavailableLabel: $error';
  }
}
