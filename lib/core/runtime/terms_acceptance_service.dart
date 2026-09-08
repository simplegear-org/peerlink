// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'storage_service.dart';

class TermsAcceptanceState {
  final bool accepted;
  final String? version;
  final DateTime? acceptedAt;

  const TermsAcceptanceState({
    required this.accepted,
    required this.version,
    required this.acceptedAt,
  });
}

class TermsAcceptanceService {
  static const String currentTermsVersion = '2026-09-08';
  static const String termsAcceptedKey = 'peerlink.terms.accepted.v1';
  static const String termsVersionKey = 'peerlink.terms.version.v1';
  static const String termsAcceptedAtKey = 'peerlink.terms.accepted_at.v1';

  final SecureStorageBox settingsBox;

  const TermsAcceptanceService({required this.settingsBox});

  factory TermsAcceptanceService.forStorage(StorageService storage) {
    return TermsAcceptanceService(settingsBox: storage.getSettings());
  }

  TermsAcceptanceState get state {
    final accepted = settingsBox.get(termsAcceptedKey) == true;
    final version = (settingsBox.get(termsVersionKey) as String?)?.trim();
    final acceptedAtRaw = (settingsBox.get(termsAcceptedAtKey) as String?)
        ?.trim();
    return TermsAcceptanceState(
      accepted: accepted,
      version: version == null || version.isEmpty ? null : version,
      acceptedAt: acceptedAtRaw == null || acceptedAtRaw.isEmpty
          ? null
          : DateTime.tryParse(acceptedAtRaw),
    );
  }

  bool get isCurrentVersionAccepted {
    final current = state;
    return current.accepted && current.version == currentTermsVersion;
  }

  Future<void> acceptCurrentVersion({DateTime? acceptedAt}) async {
    final timestamp = (acceptedAt ?? DateTime.now().toUtc()).toUtc();
    await settingsBox.put(termsAcceptedKey, true);
    await settingsBox.put(termsVersionKey, currentTermsVersion);
    await settingsBox.put(termsAcceptedAtKey, timestamp.toIso8601String());
  }
}
